#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "defines.h"
#include "api.h"
#include "ui_utils.h"
#include "ui_fonts.h"
#include "settings.h"
#include "settings_io.h"

#define CHARGE_LIMIT_MIN  50
#define CHARGE_LIMIT_MAX  100
#define CHARGE_LIMIT_STEP 5
#define HYST_PERCENT      5     /* must match daemon's HYST */
#define POWER_POLL_MS     1000

enum {
    SETTING_CHARGE_LIMIT   = 0,
    SETTING_CURRENT_CHARGE = 1,
    SETTING_POWER_STATE    = 2,
    SETTING_COUNT          = 3,
};

static const char *SETTINGS_ITEMS[SETTING_COUNT] = {
    "Charge Limit",
    "Current Charge",
    "Power State",
};

/* Only the charge-limit row is interactive; the other two are live read-outs. */
static bool is_selectable(int index) {
    return index == SETTING_CHARGE_LIMIT;
}

/* ---------- live hardware probes -------------------------------------------- */

typedef enum {
    POWER_BATTERY,    /* USB unplugged */
    POWER_CHARGING,   /* USB plugged, charger active, current into battery */
    POWER_USB,        /* USB plugged, no charge current (NVDC bypass or full) */
} PowerState;

#define CAP_PATH        "/sys/class/power_supply/axp2202-battery/capacity"
#define USB_ONLINE_PATH "/sys/class/power_supply/axp2202-usb/online"
#define REGS_PATH       "/sys/kernel/debug/regmap/6-0034/registers"

static int read_int_file(const char *path) {
    FILE *fp = fopen(path, "r");
    if (!fp) return -1;
    int v = -1;
    if (fscanf(fp, "%d", &v) != 1) v = -1;
    fclose(fp);
    return v;
}

/* Parse the regmap debugfs dump for two registers: 0x19 and 0x01.
 * Returns 0 on success, -1 on read failure. */
static int read_pmic_regs(int *reg19, int *comm_stat1) {
    *reg19 = -1; *comm_stat1 = -1;
    FILE *fp = fopen(REGS_PATH, "r");
    if (!fp) return -1;
    char line[64];
    while (fgets(line, sizeof(line), fp)) {
        if (line[0] == '1' && line[1] == '9' && line[2] == ':')
            *reg19 = (int)strtol(line + 3, NULL, 16);
        else if (line[0] == '0' && line[1] == '1' && line[2] == ':')
            *comm_stat1 = (int)strtol(line + 3, NULL, 16);
        if (*reg19 >= 0 && *comm_stat1 >= 0) break;
    }
    fclose(fp);
    return (*reg19 >= 0 && *comm_stat1 >= 0) ? 0 : -1;
}

static PowerState read_power_state(void) {
    int usb = read_int_file(USB_ONLINE_PATH);
    if (usb <= 0) return POWER_BATTERY;

    int reg19, comm_stat1;
    if (read_pmic_regs(&reg19, &comm_stat1) != 0)
        return POWER_USB; /* USB plugged but PMIC read failed — best guess */

    int charger_on = reg19 & 0x02;
    int chg_stat   = comm_stat1 & 0x07;
    /* chg_stat: 0=TRI 1=PRE 2=CC 3=CV 4=DONE 5=NCHG */
    if (charger_on && (chg_stat == 1 || chg_stat == 2 || chg_stat == 3))
        return POWER_CHARGING;
    return POWER_USB;
}

/* ---------- menu rendering helpers ------------------------------------------ */

static void value_str(int index, char *out, size_t out_size) {
    switch (index) {
        case SETTING_CHARGE_LIMIT: {
            int v = SettingsIO_getChargeLimit();
            if (v >= CHARGE_LIMIT_MAX) snprintf(out, out_size, "Off");
            else                       snprintf(out, out_size, "%d-%d%%", v - HYST_PERCENT, v);
            break;
        }
        case SETTING_CURRENT_CHARGE: {
            int cap = read_int_file(CAP_PATH);
            if (cap < 0) snprintf(out, out_size, "--");
            else         snprintf(out, out_size, "%d%%", cap);
            break;
        }
        case SETTING_POWER_STATE:
            switch (read_power_state()) {
                case POWER_CHARGING: snprintf(out, out_size, "Charging");  break;
                case POWER_USB:      snprintf(out, out_size, "USB Power"); break;
                case POWER_BATTERY:  snprintf(out, out_size, "Battery");   break;
            }
            break;
        default:
            snprintf(out, out_size, "?");
            break;
    }
}

/* Shell out to hook-handler.sh to start/stop/reload the daemon. */
static void run_hook_handler(const char *action) {
    const char *pak = getenv("PAK_DIR");
    if (!pak) {
        fprintf(stderr, "settings: PAK_DIR unset; cannot %s daemon\n", action);
        return;
    }
    char cmd[768];
    snprintf(cmd, sizeof(cmd), "\"%s/hook-handler.sh\" %s", pak, action);
    int rc = system(cmd);
    if (rc != 0) {
        fprintf(stderr, "settings: hook-handler.sh %s exited %d\n", action, rc);
    }
}

static void value_cycle(int index, int delta) {
    switch (index) {
        case SETTING_CHARGE_LIMIT: {
            int v = SettingsIO_getChargeLimit() + delta * CHARGE_LIMIT_STEP;
            if (v < CHARGE_LIMIT_MIN) v = CHARGE_LIMIT_MAX;
            if (v > CHARGE_LIMIT_MAX) v = CHARGE_LIMIT_MIN;
            SettingsIO_setChargeLimit(v);
            SettingsIO_save();
            run_hook_handler("ensure");
            break;
        }
        /* Other rows are read-only. */
    }
}

static void settings_render_badge(SDL_Surface *screen, int index, bool selected,
                                  int item_y, int item_h) {
    (void)selected;
    SDL_Color color = uintToColour(THEME_COLOR4);
    char buf[32];
    value_str(index, buf, sizeof(buf));
    SDL_Surface *txt = TTF_RenderUTF8_Blended(Fonts_getMedium(), buf, color);
    if (!txt) return;
    int x = screen->w - txt->w - SCALE1(PADDING * 2);
    int y = item_y + (item_h - txt->h) / 2;
    SDL_BlitSurface(txt, NULL, screen, &(SDL_Rect){x, y});
    SDL_FreeSurface(txt);
}

/* Step selection to the next selectable row in the given direction (-1/+1),
 * skipping read-only rows. Returns the same index if none other is selectable. */
static int next_selectable(int from, int dir) {
    int i = from;
    for (int n = 0; n < SETTING_COUNT; n++) {
        i = (i + dir + SETTING_COUNT) % SETTING_COUNT;
        if (is_selectable(i)) return i;
    }
    return from;
}

void SettingsModule_run(SDL_Surface *screen) {
    int selected = SETTING_CHARGE_LIMIT;
    int dirty = 1;
    int show_setting = 0;
    uint32_t last_poll = SDL_GetTicks();

    SimpleMenuConfig config = {
        .title        = "Battery Care",
        .items        = SETTINGS_ITEMS,
        .item_count   = SETTING_COUNT,
        .btn_b_label  = "EXIT",
        .btn_a_label  = NULL,
        .get_label    = NULL,
        .render_badge = settings_render_badge,
        .get_icon     = NULL,
        .render_text  = NULL,
    };

    while (1) {
        GFX_startFrame();
        PAD_poll();

        if (PAD_justPressed(BTN_B)) {
            return;
        } else if (PAD_justRepeated(BTN_UP)) {
            selected = next_selectable(selected, -1);
            dirty = 1;
        } else if (PAD_justRepeated(BTN_DOWN)) {
            selected = next_selectable(selected, +1);
            dirty = 1;
        } else if (PAD_justRepeated(BTN_LEFT)) {
            value_cycle(selected, -1);
            dirty = 1;
        } else if (PAD_justRepeated(BTN_RIGHT)) {
            value_cycle(selected, +1);
            dirty = 1;
        }

        /* Tick the live read-out rows so they refresh without input. */
        uint32_t now = SDL_GetTicks();
        if (now - last_poll >= POWER_POLL_MS) {
            last_poll = now;
            dirty = 1;
        }

        PWR_update(&dirty, &show_setting, NULL, NULL);

        if (dirty) {
            render_simple_menu(screen, show_setting, selected, &config);
            GFX_flip(screen);
            dirty = 0;
        } else {
            GFX_sync();
        }
    }
}
