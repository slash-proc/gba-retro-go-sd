# Game Boy Advance (gpSP) — standalone Retro-Go SD core.
#
#   make                  — build + pack → gba.bin + gba.xip
#   make host             — desktop SDL build → ./gba_host [rom.gba]
#   make docker           — same build inside Docker (no host toolchain)
#   make docker_shell     — interactive shell in the builder image
#
# BUILD_DIR must stay `build`: ld/gba_core.ld names objects as build/*.o.

#######################################
# Project identity
#######################################
PROJECT_KIND ?= core

CORE_NAME  := gba
CORE_ENTRY := app_main_gba

CORE_C_SOURCES := \
src/gpsp/gba_memory.c \
src/gpsp/sound.c \
src/gpsp/main.c \
src/gpsp/savestate.c \
src/gpsp/input.c \
src/gpsp/cheats.c \
src/gpsp/serial.c \
src/gpsp/serial_proto.c \
src/gpsp/gbp.c \
src/gpsp/rfu.c \
src/porting/gba_frontend.c \
src/porting/gba_idle_loop.c \
src/porting/gba_audio_filter.c \
src/main_gba.c \
src/porting/gba_bios_hle.c \
src/m4a/m4a_hle.c \
src/m4a/m4a_gpsp.c \
src/porting/bilinear.c

CORE_CXX_SOURCES := \
src/gpsp/cpu.cc \
src/gpsp/video.cc

CORE_ASM_SOURCES := \
src/porting/gba_bios.S

CORE_C_INCLUDES := \
-Isrc/gpsp \
-Isrc/gpsp/libretro/libretro-common/include \
-Isrc/m4a \
-Isrc/porting

# Relative path so Docker bind-mounts work (do NOT use $(abspath)).
GNW_CORE_SDK ?= sdk
# Must match EXCLUDE_FILE / .core_itcm paths in ld/gba_core.ld.
BUILD_DIR ?= build

#######################################
# Kind-specific compile defs + packing
#######################################
ifeq ($(PROJECT_KIND),core)
# COVERFLOW=1 CHEAT_CODES=1 MAX_CHEAT_CODES=13: match release firmware
# retro_emulator_file_t layout. gpSP's own MAX_CHEATS (20 engine slots) is
# a different constant in src/gpsp/cheats.h.
#
# ROM_BUFFER_SIZE=0    cart XIP from QSPI — not buffered in RAM.
# OBJ_PER_LINE_MAX=32  caps sprite-line BSS (~120 KB saved vs gpSP default).
# BUFFER_SIZE=4096     audio ring (gpSP default is 128 KB).
# GBA_DTCM_BUFFERS     bios / sound / cheats allocated at runtime (DTCM/AHB).
CORE_C_DEFS := \
-DPROJECT_KIND_CORE=1 \
-DCOVERFLOW=1 \
-DCHEAT_CODES=1 \
-DMAX_CHEAT_CODES=13 \
-DROM_BUFFER_SIZE=0 \
-DOBJ_PER_LINE_MAX=32 \
-DBUFFER_SIZE=4096 \
-DGBA_SOUND_FREQUENCY=48000 \
-DGBA_M4A_HLE \
-DGBA_BIOS_HLE \
-DGBA_DTCM_BUFFERS

PACKED_BIN  := $(CORE_NAME).bin
XIP_BIN     := $(CORE_NAME).xip
# The generic sidecar name the shared release tooling reads.
RO_BIN      := $(XIP_BIN)
PAD_LOGO    := src/assets/pad.bmp
HEADER_LOGO := src/assets/header.bmp

CORE_LDSCRIPT := ld/gba_core.ld
CORE_EXTRA_SEGMENTS := itcm:core_itcm
CORE_ASFLAGS := -Isrc/gpsp/bios

else
$(error PROJECT_KIND must be 'core' (got '$(PROJECT_KIND)'))
endif

include $(GNW_CORE_SDK)/Makefile
include host/Makefile.host

PACK_CORE := $(GNW_CORE_SDK)/tools/pack_core.py

#######################################
# Packed header version
#######################################
# gnw_core_meta_t only stores major.minor.patch (0..255).
# CORE_VERSION is the full git describe string passed to the packer; it
# extracts the leading vX.Y.Z (NOTAG / missing tags → 0.0.0).
# Override: make CORE_VERSION=v1.2.3
CORE_VERSION ?= $(shell git describe --tags --dirty 2>/dev/null || echo NOTAG)

# gpSP's main.c shares a basename with nothing else here, but pin it so a
# future vpath collision cannot pick the wrong main.c (firmware Makefile
# had this exact trap against Core/Src/main.c).
$(BUILD_DIR)/main.o: src/gpsp/main.c $(REDEFINE_SYMS_FILE) | $(BUILD_DIR)
	$(V)$(ECHO) [ CC ] $(notdir $<)
	$(V)$(CC) -c $(CFLAGS) $< -o $@
	$(V)$(CP) --redefine-syms=$(REDEFINE_SYMS_FILE) $@
	$(V)$(call CORE_APPLY_EXTRA_REDEFINE,$@)

GBA_WARN_OFF := -Wno-parentheses -Wno-unknown-pragmas -Wno-strict-aliasing -Wno-comment \
	-Wno-unused-function -Wno-stack-usage -Wno-unused-variable \
	-Wno-unused-but-set-variable -Wno-sign-compare -Wno-format

CFLAGS   += $(GBA_WARN_OFF)
CXXFLAGS += $(GBA_WARN_OFF)

# Size-first default (-Os) for cold files. Per-frame / per-sample paths
# match the firmware GBA core: gba_memory/cpu at -O3, video/sound/HLE at -O2.
GBA_CFLAGS_O2   = $(filter-out -Os,$(CFLAGS)) -O2
GBA_CFLAGS_O3   = $(filter-out -Os,$(CFLAGS)) -O3
GBA_CXXFLAGS_O2 = $(filter-out -Os,$(CXXFLAGS)) -O2
GBA_CXXFLAGS_O3 = $(filter-out -Os,$(CXXFLAGS)) -O3

$(BUILD_DIR)/gba_memory.o:       CFLAGS   := $(GBA_CFLAGS_O3)
$(BUILD_DIR)/cpu.o:              CXXFLAGS := $(GBA_CXXFLAGS_O3)
$(BUILD_DIR)/video.o:            CXXFLAGS := $(GBA_CXXFLAGS_O2)
$(BUILD_DIR)/sound.o:            CFLAGS   := $(GBA_CFLAGS_O2)
$(BUILD_DIR)/gba_bios_hle.o:     CFLAGS   := $(GBA_CFLAGS_O2)
$(BUILD_DIR)/m4a_hle.o:          CFLAGS   := $(GBA_CFLAGS_O2)
$(BUILD_DIR)/m4a_gpsp.o:         CFLAGS   := $(GBA_CFLAGS_O2)

#######################################
# Pack
#######################################
.PHONY: pack

$(XIP_BIN): $(TARGET_ELF)
	$(V)$(ECHO) [ XIP ] $(XIP_BIN)
	$(V)$(CP) -O binary --only-section=.xip_gba --only-section=.rodata_gba $< $@
	$(V)$(SZ) --target=binary $@

pack: $(TARGET_BIN) $(BUILD_DIR)/gba_core_itcm.bin $(XIP_BIN) $(PAD_LOGO) $(HEADER_LOGO)
	$(V)$(ECHO) [ PACK CORE ] $(PACKED_BIN) version=$(CORE_VERSION)
	$(V)python3 $(PACK_CORE) \
		--elf $(TARGET_ELF) --bin $(TARGET_BIN) \
		--system name="Game Boy Advance",dirname=gba,pad_logo=$(PAD_LOGO),header_logo=$(HEADER_LOGO),ext=gba,parse=rom,cheat_ext=ggcodes \
		--logo-invert \
		--segment itcm:__ITCM_CORE_START__:__CORE_ITCM_CODE_END__:__CORE_ITCM_BSS_END__:$(BUILD_DIR)/gba_core_itcm.bin \
		--core-name "gpSP" \
		--version "$(CORE_VERSION)" \
		--out $(PACKED_BIN)

all: pack

.PHONY: print-PROJECT_KIND print-PACKED_BIN print-RO_BIN print-CORE_NAME print-DOCKER_IMAGE \
	print-TARGET_ELF print-TARGET_MAP print-XIP_BIN print-CORE_VERSION
print-PROJECT_KIND:
	@echo $(PROJECT_KIND)
print-PACKED_BIN:
	@echo $(PACKED_BIN)
# gba ships its execute-in-place blob beside the core, and the core
# aborts without it. It rides the generic sidecar path rather than a
# gba-only flag, so the shared script stays one file.
print-RO_BIN:
	@echo $(RO_BIN)
print-CORE_NAME:
	@echo $(CORE_NAME)
print-DOCKER_IMAGE:
	@echo $(DOCKER_IMAGE)
print-TARGET_ELF:
	@echo $(TARGET_ELF)
print-TARGET_MAP:
	@echo $(BUILD_DIR)/$(CORE_NAME)_core.map
print-XIP_BIN:
	@echo $(XIP_BIN)
print-CORE_VERSION:
	@echo $(CORE_VERSION)

clean::
	$(V)rm -f $(PACKED_BIN) $(XIP_BIN)

#######################################
# Docker (same image as firmware repo)
#######################################
.PHONY: docker docker_pull docker_shell

RELEASE_VERSION ?= v1.5
DOCKER_REPOSITORY ?= sylverb/retro-go-sd-builder
DOCKER_IMAGE ?= $(DOCKER_REPOSITORY):$(RELEASE_VERSION)

DOCKER_TTY_FLAG := $(shell if [ -t 0 ]; then echo -it; else echo; fi)
DOCKER_USER := $(shell id -u):$(shell id -g)
DOCKER_RUN := docker run --rm $(DOCKER_TTY_FLAG) \
	--user $(DOCKER_USER) \
	-v "$(CURDIR):/opt/workdir" \
	-w /opt/workdir \
	$(DOCKER_IMAGE)

docker:
	$(V)$(ECHO) "[ DOCKER ]" $(DOCKER_IMAGE) "PROJECT_KIND=$(PROJECT_KIND)"
	$(V)$(DOCKER_RUN) make --no-print-directory -j$$(nproc) PROJECT_KIND=$(PROJECT_KIND)

docker_pull:
	$(V)$(ECHO) "[ PULL ]" $(DOCKER_IMAGE)
	$(V)docker pull $(DOCKER_IMAGE)

docker_shell:
	$(DOCKER_RUN) bash
