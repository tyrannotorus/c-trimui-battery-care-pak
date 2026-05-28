#include "settings_io.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/types.h>

#define CHARGE_LIMIT_MIN     50
#define CHARGE_LIMIT_MAX     100
#define CHARGE_LIMIT_STEP    5
#define CHARGE_LIMIT_DEFAULT 100   /* No cap until user opts in. */

static int  s_charge_limit = CHARGE_LIMIT_DEFAULT;
static char s_config_path[512] = {0};

static int clamp_step(int v) {
    if (v < CHARGE_LIMIT_MIN) v = CHARGE_LIMIT_MIN;
    if (v > CHARGE_LIMIT_MAX) v = CHARGE_LIMIT_MAX;
    /* Snap to the nearest step boundary. */
    v = ((v + CHARGE_LIMIT_STEP / 2) / CHARGE_LIMIT_STEP) * CHARGE_LIMIT_STEP;
    return v;
}

static void resolve_config_path(void) {
    if (s_config_path[0]) return;
    const char *base = getenv("USERDATA_PATH");
    if (!base || !*base) {
        fprintf(stderr, "settings_io: USERDATA_PATH not set\n");
        s_config_path[0] = '\0';
        return;
    }
    snprintf(s_config_path, sizeof(s_config_path),
             "%s/Battery Care/settings.cfg", base);
}

/* mkdir -p for the parent directory of s_config_path. */
static void ensure_parent_dir(void) {
    char buf[512];
    snprintf(buf, sizeof(buf), "%s", s_config_path);
    char *slash = strrchr(buf, '/');
    if (!slash) return;
    *slash = '\0';
    for (char *p = buf + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(buf, 0755) != 0 && errno != EEXIST) { /* swallow */ }
            *p = '/';
        }
    }
    if (mkdir(buf, 0755) != 0 && errno != EEXIST) { /* swallow */ }
}

void SettingsIO_load(void) {
    resolve_config_path();
    FILE *fp = fopen(s_config_path, "r");
    if (!fp) return;

    char line[128];
    while (fgets(line, sizeof(line), fp)) {
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = line;
        char *val = eq + 1;
        size_t vl = strlen(val);
        while (vl > 0 && (val[vl-1] == '\n' || val[vl-1] == '\r' || val[vl-1] == ' '))
            val[--vl] = '\0';

        if (strcmp(key, "target") == 0) {
            s_charge_limit = clamp_step(atoi(val));
        }
    }
    fclose(fp);
}

void SettingsIO_save(void) {
    resolve_config_path();
    ensure_parent_dir();

    /* Atomic write: tmp file then rename. */
    char tmp[600];
    snprintf(tmp, sizeof(tmp), "%s.tmp", s_config_path);
    FILE *fp = fopen(tmp, "w");
    if (!fp) {
        fprintf(stderr, "settings_io: open %s failed: %s\n", tmp, strerror(errno));
        return;
    }
    fprintf(fp, "target=%d\n", s_charge_limit);
    fclose(fp);
    if (rename(tmp, s_config_path) != 0) {
        fprintf(stderr, "settings_io: rename %s -> %s: %s\n",
                tmp, s_config_path, strerror(errno));
    }
}

int  SettingsIO_getChargeLimit(void)        { return s_charge_limit; }
void SettingsIO_setChargeLimit(int percent) { s_charge_limit = clamp_step(percent); }
