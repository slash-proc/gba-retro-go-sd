/*
 * Desktop entry: init SDL, then jump into the same CORE_ENTRY as on device.
 */

#include <stdio.h>
#include <stdlib.h>

#include "host_compat.h"
#include "host_platform.h"

#ifndef HOST_SCALE
#define HOST_SCALE 2
#endif

#ifndef HOST_CORE_ENTRY
#define HOST_CORE_ENTRY app_main
#endif

extern void HOST_CORE_ENTRY(uint8_t load_state, uint8_t start_paused, int8_t save_slot);

int main(int argc, char **argv)
{
    const char *title =
#if defined(PROJECT_KIND_HOMEBREW)
        "Retro-Go Homebrew (host)";
#else
        "Retro-Go GBA (host)";
#endif
    const char *rom = getenv("HOST_ROM");

    if (argc > 1 && argv[1] && argv[1][0])
        rom = argv[1];

    if (!rom || !rom[0]) {
        fprintf(stderr, "usage: %s <rom.gba>   (or set HOST_ROM)\n", argv[0]);
        return 1;
    }

    if (host_platform_init(title, HOST_SCALE) != 0)
        return 1;

    gw_core_bridge_init();
    host_set_rom_path(rom);

    printf("host: Esc or close window to quit\n");
    printf("host: Arrows=D-pad  Z=B  X=A  Enter=Start  Shift=Select  A/S=L/R\n");
    printf("host: F1=save state  F2=load state  (./host_saves/)\n");
    printf("host: ROM %s\n", rom);

    HOST_CORE_ENTRY(0, 0, -1);

    host_platform_shutdown();
    return 0;
}
