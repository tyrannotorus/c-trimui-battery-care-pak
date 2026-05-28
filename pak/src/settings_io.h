#ifndef __BATTERYCARE_SETTINGS_IO_H__
#define __BATTERYCARE_SETTINGS_IO_H__

/* Persisted Battery Care settings.
 * File lives at $USERDATA_PATH/Battery Care/settings.cfg.
 * Format: simple key=value lines. Current keys: target=<50..100, step 5>. */

void SettingsIO_load(void);  /* Loads file into memory. Defaults if missing/malformed. */
void SettingsIO_save(void);  /* Writes current values to file. mkdir -p as needed. */

int  SettingsIO_getChargeLimit(void);
void SettingsIO_setChargeLimit(int percent);

#endif
