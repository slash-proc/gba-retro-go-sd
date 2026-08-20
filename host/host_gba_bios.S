/* Open-source GBA BIOS blob for the desktop host build (not Thumb device asm). */
#if defined(__APPLE__)
	.section __TEXT,__const
	.globl _open_gba_bios_rom
	.p2align 2
_open_gba_bios_rom:
#else
	.section .rodata
	.globl open_gba_bios_rom
	.type open_gba_bios_rom, @object
	.align 2
open_gba_bios_rom:
#endif
	.incbin "open_gba_bios.bin"
#if !defined(__APPLE__)
	.size open_gba_bios_rom, . - open_gba_bios_rom
#endif
