# Game Boy Advance — Retro-Go SD core

Standalone Game & Watch Retro-Go SD core for **Nintendo Game Boy Advance**,
using [gpSP](https://github.com/libretro/gpsp) (`src/gpsp/`, GPL-2) plus the
Game & Watch port (`src/main_gba.c`, `src/porting/`, `src/m4a/`).

This is a freestanding Cortex-M7 image linked into `RAM_EMU` (plus an
ITCM code segment). Cold code/rodata ships as a QSPI sidecar (`gba.xip`).
It talks to the firmware **only** through `gw_firmware_abi_t`. You do not
link against the firmware ELF.

| | |
|--|--|
| Packer | `sdk/tools/pack_core.py` (`CORE`) |
| SD path | `/cores/gba.bin` + `/cores/gba.xip` |
| Tab | dirname `gba`, extensions `.gba`, parse=rom, cheats `ggcodes` |
| BIOS (optional) | `/bios/gba/gba_bios.bin` (falls back to bundled open BIOS) |

Headers, ABI bridge, linker scripts, and packers are vendored under
`sdk/`. You do **not** need a firmware checkout to compile.

## Requirements

**Local build**

- `arm-none-eabi-gcc` (v10+, same family as the firmware; hard-float
  `fpv5-d16` is mandatory — ABI calling convention must match)
- GNU Make
- Python 3 + Pillow (`pip install -r requirements.txt`) for packaging logos

**Docker build** (no host toolchain)

- Docker
- Image [`sylverb/retro-go-sd-builder`](https://hub.docker.com/r/sylverb/retro-go-sd-builder)
  (same tag as the firmware repo, default `v1.5`)

## Quick start

```bash
make
# or: make docker
# desktop SDL (debug): make host && ./gba_host game.gba
```

Produces `gba.bin` and `gba.xip`. Copy **both** to `/cores/` on the SD card.

- ROMs: `/roms/gba/*.gba`
- Optional official BIOS: `/bios/gba/gba_bios.bin` (exactly 16 KiB)

Requires firmware whose ABI matches `SDK_VERSION` in this repository.

Useful Docker targets:

- `make docker` — build + pack in the local builder image
- `make docker_pull` — refresh the image from Docker Hub
- `make docker_shell` — interactive shell in the same mount

Desktop (SDL2/SDL3) for local debug without a device:

```bash
make host
./gba_host /path/to/game.gba
```

Override the image tag if needed: `make docker RELEASE_VERSION=v1.5`.

The packed header version is taken from `git describe --tags --dirty`
(`CORE_VERSION`; override with `make CORE_VERSION=v1.2.3`). No tags →
`NOTAG` → header `0.0.0`. Release tags should be `vX.Y.Z` so the Info
dialog can show a semantic version.

## Releases (GitHub tags `v*`)

Pushing a tag `vX.Y.Z` (with a matching `## [vX.Y.Z]` section in
`CHANGELOG.md`) creates a GitHub Release with **two** zip assets only:

| Asset | Contents |
|-------|----------|
| `gba-vX.Y.Z.zip` | SD layout: `cores/gba.bin` + `cores/gba.xip` |
| `gba-vX.Y.Z-debug.zip` | `gba_core.elf`, linker `.map`, and a short README |

Unzip the install archive onto the SD card root. For a crash PC/LR:

```bash
unzip gba-v1.0.0-debug.zip
arm-none-eabi-addr2line -e gba_core.elf -f -C -a 0x<PC> 0x<LR>
```

Needs `arm-none-eabi-addr2line` on `PATH`, or the `sylverb/retro-go-sd-builder`
Docker image. From a repo checkout you can also use
`python3 scripts/resolve_addr.py --elf …` — see the README inside the debug zip.

## Layout

```
Makefile            Project build + pack + docker
ld/gba_core.ld      RAM_EMU + ITCM + XIP linker script
gba_redefines       gpSP symbol prefix (avoids ABI collisions)
src/main_gba.c      Device glue (ROM XIP, audio, savestates, blit)
src/gpsp/           gpSP interpreter / PPU / APU / memory
src/porting/        Front-end stubs, idle table, BIOS HLE, bilinear
src/m4a/            M4A mixer HLE
src/assets/         Pad + header 1bpp logos (from firmware icons/, inverted)
sdk/                Vendored ABI, bridge, linker fragments, packers
scripts/            Sync helper, release staging
```

## Memory (short)

| Region | What lives there |
|--------|------------------|
| **ITCM** (64 KiB, code only) | `cpu.o` interpreter, `m4a_gpsp.o`, `update_scanline` |
| **DTCM** (~104 KiB bump) | 240×160 framebuffer (75 KiB); BIOS + sound ring if they fit |
| **AHB** (leftover heap) | Cheat table; overflow from DTCM |
| **RAM_EMU** | Remaining hot text, `savestate.o`, BSS (IWRAM/EWRAM/VRAM/backup) |
| **QSPI XIP** (`gba.xip`) | Cold text (serial, cheats, bilinear, rest of `video.o`) + leftover rodata |

ITCM is **not** used for data. Do not call `dtc_init()` from the core — the
launcher already bump-allocated tables in DTCM.

Include order in `src/main_gba.c`: firmware-style headers first, then
`#include "gw_core_bridge.h"` last (macros rewrite `ACTIVE_FILE` /
`common_emu_state`).

## Controls

The unit has no GBA shoulders. **Y = L**, **X = R**.

## License

GPL-2 (see `LICENSE` and `src/gpsp/COPYING`). SDK glue originated as MIT
template code; combined with gpSP the distributed core is GPL-2.
