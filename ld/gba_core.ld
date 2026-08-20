/*
 * Game Boy Advance (gpSP) core linker script.
 *
 *   RAM_EMU  — entry + main_gba + hot video (scanline_text) + remaining
 *              hot text + .data/.bss. No bios/sound/FB here: those are
 *              dtc_*'d at runtime. Cheats use the AHB heap (cold).
 *   ITCM     — hot CODE only (no .data/.bss/.rodata):
 *                cpu.o interpreter, m4a_gpsp.o (called from cpu),
 *                video update_scanline (every scanline from the interpreter).
 *              Remaining ITCM is too tight for render_scanline_text (~21 KiB)
 *              or the sprite/effects helpers; those stay in RAM_EMU.
 *              ITCM may still hold absolute veneers into XIP — main_gba
 *              patches those after caching gba.xip (same pass as RAM_EMU).
 *
 * Plus a non-packaged XIP sidecar (.xip_gba + .rodata_gba @ GBA_CODE
 * 0xDEC00000) shipped as gba.xip and cached into QSPI at runtime
 * (see src/main_gba.c gba_cache_xip_to_flash()).
 *
 * Objects land in a flat build/ dir (basenames only).
 */

INCLUDE gnw_ram_emu.ld
INCLUDE gnw_itcm_core.ld

MEMORY
{
  RAM_EMU  (xrw) : ORIGIN = __RAM_EMU_START__,  LENGTH = __RAM_EMU_LENGTH__
  ITCM     (xrw) : ORIGIN = __ITCM_CORE_START__, LENGTH = __ITCM_CORE_LENGTH__
  /* Sentinel / XIP link address only — payload ships as gba.xip, not in the CORE bin. */
  GBA_CODE (x)   : ORIGIN = 0xDEC00000,         LENGTH = 512K
}

SECTIONS
{
  /* ------------------------------------------------------------------ */
  /* Segment 0: RAM_EMU — entry, main_gba (whole), hot video text that  */
  /* does not fit ITCM, cpu/m4a rodata, then .bss.                      */
  /* ------------------------------------------------------------------ */
  .core_entry __RAM_EMU_START__ :
  {
    KEEP(*(.core_entry))
    KEEP(*(.gw_core_bridge_probe))
    . = ALIGN(4);

    /* main_gba.o whole — holds GBA_CODE_BASE and the sentinel patch pass;
     * the pass must not walk itself. Symbols bound the patch range start. */
    _GBA_MAIN_CODE_START = .;
    build/main_gba.o (.data .data* .text .text* .rodata .rodata*)
    . = ALIGN(4);
    _GBA_MAIN_CODE_END = .;

    /* Hottest remaining video that does not fit leftover ITCM. */
    build/video.o (.text._Z20render_scanline_text*)
    build/video.o (.text._Z13render_object*)
    build/video.o (.text._ZL16render_w_effects*)
    build/video.o (.text._ZL9order_obj*)

    /* Remaining .data from every object (main_gba already claimed). */
    *(.data .data*)

    /* Hot .text: everything except cpu/m4a_gpsp (→ITCM) and cold XIP files.
     * savestate.o stays in RAM_EMU: its bson parse path calls strlen/memcmp
     * per key and must not run from XIP through ABI veneers. */
    EXCLUDE_FILE(
      build/cpu.o
      build/m4a_gpsp.o
      build/video.o
      build/serial.o
      build/serial_proto.o
      build/gbp.o
      build/rfu.o
      build/input.o
      build/gba_frontend.o
      build/m4a_hle.o
      build/cheats.o
      build/gba_idle_loop.o
      build/bilinear.o
    ) *(.text .text*)

    /* cpu.o / m4a_gpsp.o run from ITCM. Their *rodata* must stay in RAM
     * (ITCM is code-only). Absolute veneers into XIP that the linker emits
     * in ITCM are patched at runtime (see gba_cache_xip_to_flash). */
    build/cpu.o (.rodata .rodata*)
    build/m4a_hle.o (.rodata .rodata*)
    build/m4a_gpsp.o (.rodata .rodata*)

    *(.glue_7)
    *(.glue_7t)

    . = ALIGN(4);
    __CORE_INIT_ARRAY_START__ = .;
    KEEP(*(SORT(.init_array.*)))
    KEEP(*(.init_array*))
    __CORE_INIT_ARRAY_END__ = .;

    /* Align inside this section (not between sections): an empty trailing
     * .data would otherwise leave a VMA gap that objcopy does not emit. */
    . = ALIGN(8);
  } >RAM_EMU

  .data :
  {
    *(.data*)
  } >RAM_EMU

  __CORE_CODE_END__ = .;
  _OVERLAY_GBA_BSS_START = __CORE_CODE_END__;
  _GBA_SENTINEL_PATCH_END = __CORE_CODE_END__;

  .bss _OVERLAY_GBA_BSS_START (NOLOAD) :
  {
    . = ALIGN(8);
    *(.bss*)
    *(COMMON)
  } >RAM_EMU

  __CORE_BSS_END__ = .;

  ASSERT(__CORE_BSS_END__ <= __RAM_EMU_END__,
         "Error: GBA core RAM_EMU segment (code+data+bss) overflows RAM_EMU")

  /* ------------------------------------------------------------------ */
  /* Segment ITCM: hot CODE only. No .data / .bss / .rodata.            */
  /* ------------------------------------------------------------------ */
  .core_itcm __ITCM_CORE_START__ :
  {
    . = ALIGN(4);
    __CORE_ITCM_CODE_START__ = .;
    build/cpu.o (.text*)
    build/m4a_gpsp.o (.text*)
    build/video.o (.text.update_scanline)
    . = ALIGN(4);
    __CORE_ITCM_CODE_END__ = .;
  } >ITCM

  __CORE_ITCM_BSS_END__ = __CORE_ITCM_CODE_END__;

  ASSERT(__CORE_ITCM_BSS_END__ <= __ITCM_CORE_START__ + __ITCM_CORE_LENGTH__,
         "Error: GBA core ITCM segment (hot code) overflows the 64K ITCM region")

  /* ------------------------------------------------------------------ */
  /* XIP sidecar (NOT a pack segment) — cold text then remaining rodata */
  /* as one contiguous GBA_CODE image → gba.xip.                        */
  /* ------------------------------------------------------------------ */
  .xip_gba :
  {
    . = ALIGN(8);
    __xip_gba_start__ = .;
    build/video.o (.text .text*)
    build/serial.o (.text .text*)
    build/serial_proto.o (.text .text*)
    build/gbp.o (.text .text*)
    build/rfu.o (.text .text*)
    build/input.o (.text .text*)
    build/gba_frontend.o (.text .text*)
    build/m4a_hle.o (.text .text*)
    build/cheats.o (.text .text*)
    build/gba_idle_loop.o (.text .text*)
    build/bilinear.o (.text .text*)
  } >GBA_CODE

  .rodata_gba :
  {
    . = ALIGN(8);
    __rodata_gba_start__ = .;
    *(.rodata .rodata*)
    . = ALIGN(4);
    __rodata_gba_end__ = .;
    __xip_gba_end__ = .;
  } >GBA_CODE

  ASSERT(__xip_gba_end__ <= ORIGIN(GBA_CODE) + LENGTH(GBA_CODE),
         "Error: GBA XIP (.xip_gba + .rodata_gba) overflows 512K GBA_CODE")

  __exidx_start = .;
  __exidx_end = .;

  /DISCARD/ :
  {
    *(.fini_array*)
    *(.preinit_array*)
    *(.ARM.exidx*)
    *(.ARM.extab*)
    *(.comment)
    *(.ARM.attributes)
  }
}
