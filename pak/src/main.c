#include <stdio.h>
#include <stdlib.h>

#include <SDL2/SDL_ttf.h>

#include "defines.h"
#include "api.h"
#include "config.h"
#include "msettings.h"

#include "ui_fonts.h"
#include "settings.h"
#include "settings_io.h"

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    InitSettings();
    CFG_init(NULL, NULL);
    SDL_Surface *screen = GFX_init(MODE_MAIN);
    PAD_init();
    PWR_init();
    TTF_Init();
    Fonts_load();
    SettingsIO_load();

    fprintf(stderr, "battery-care: ready  screen %dx%d  charge_limit=%d\n",
            screen->w, screen->h, SettingsIO_getChargeLimit());

    SettingsModule_run(screen);

    Fonts_unload();
    TTF_Quit();
    PWR_quit();
    PAD_quit();
    GFX_quit();
    CFG_quit();
    QuitSettings();
    return 0;
}
