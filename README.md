# Battery Care Pak For TrimUI Brick

<img width="1024" height="768" alt="menu" src="https://github.com/user-attachments/assets/9ebc81f7-4896-4200-ac4a-3a642d1b4ff8" />

## Description

I have my TrimUI Brick on display and plugged-in playing demos or music all day at my workstation.
Although the Brick appears to correctly bypass the battery when fully saturated, I don't like
daily-use, always-plugged-in, battery-powered devices charging beyond 80%.

The Battery Care Pak allows the user to set a lower battery charge threshold (like 80%). While the
device is awake, it will charge only to that percentage and then switch to USB Power only.

## User Disclaimer

Battery Care is shared free with the TrimUI community and provided **as-is, without any
warranty**. It changes charging behavior at the hardware-register level, so use it at
your own risk. The author accepts no liability for any damage to your device or battery.

## Dev Disclaimer

I am an experienced developer, but note this is a personal-use project that's been human-directed but 100% slop-coded. Thus beware, here be dragons.

## Supported Platforms

- **tg5040** — TrimUI Brick
- I have no other devices to test with

## Behaviour

| Setting | Effect |
|---|---|
| Limit 50–95% | Daemon stops charging at the limit; the device runs on USB power (AXP2202 NVDC bypass) with the cell at zero current. Charging re-enables at `limit − 5%` (hysteresis) to avoid thrashing; the app shows the band, e.g. `85–90%`. |
| Off (100%) | Daemon stopped, charger restored; charges to 100% like stock. |

## Known issues

The cap is software-only and applies only while the device is awake.

- **Deep sleep** Deep sleep pauses the Battery Care daemon. This means
  that whatever charging state you were in when you entered deep sleep will
  continue. If the Brick was in a 'Charging' mode when it enter deep sleep,
  it will continue to charge uncapped to 100%. If the Brick was in a 'USB Power'
  mode, it will not charge during deep sleep. Awakening the device resumes
  the daemon and Battery Care operates normally again.
- **Powered off.** The daemon isn't running, so charging is uncapped to 100%. The boot
  hook re-applies the cap once NextUI is back up.

### Possible software fix

- Allowlisting the daemon from being suspended during deep sleep in NextUI.

### Possible hardware fix

The AXP2202's constant-charge-voltage register (`0x64`, AXP717-compatible `CV_CHG_SET`)
sets the charge-termination voltage. Lowering it caps charging in hardware — no daemon —
so the cap would hold through deep sleep and power-off charging:

| `0x64` | CV target | approx. max |
|---|---|---|
| `0` | 4.0 V | ~80–85% |
| `1` | 4.1 V | ~90% |
| `2` | 4.2 V | 100% (default) |

- This would mean the loss of user-set percentage-based thresholds, as only voltage steps
can be set (4.0 / 4.1 / 4.2 V).

## Install

1. Download `Battery.Care.pak.zip` from the [latest release](https://github.com/tyrannotorus/c-trimui-battery-care-pak/releases).
2. Copy it to `/mnt/SDCARD/Tools/tg5040/` (mount the SD card or `adb push`).
3. Extract it so the `Battery Care.pak` folder lands directly in `/mnt/SDCARD/Tools/tg5040/`, then delete the zip. (If your unzip tool dots the name to `Battery.Care.pak`, rename it back to `Battery Care.pak`.)
4. On device, open **Tools → Battery Care**.
5. **Left/Right** on **Charge Limit** to set the ceiling (or **Off**), then exit. Takes effect immediately; re-arms on every boot.

> **Note:** `launch.sh` must sit directly inside `Battery Care.pak/`. Some unzip tools
> double-wrap the archive — if you see `Battery Care.pak/Battery Care.pak/`, copy the
> inner folder.

## Build

Cross-compiled in the NextUI `tg5040` Docker toolchain. Needs `docker` (and `adb` for `push`).

```sh
cd pak
make pak     # clone NextUI (first run), cross-compile, assemble build/Battery Care.pak/
make pakz    # also zip to build/Battery.Care.pak.zip
make push    # build + adb push to a connected device
make clean   # remove build artifacts
```

### Hardware

- PMIC: AXP2202 on i2c-6 @ `0x34`, via regmap debugfs `/sys/kernel/debug/regmap/6-0034/registers`.
- Reg `0x19` bit 1 = charger enable. Clear (`0x06`→`0x04`) to stop charging, set (`0x04`→`0x06`) to resume; `0x06` is the default.
- With the charger disabled and USB plugged, the NVDC path runs the system off USB and leaves the battery idle (zero current, no float wear).
- Status reads: charge state from `COMM_STAT1` (reg `0x01`) bits[2:0] — `0`=tri-charge, `1`=pre-charge, `2`=constant-current, `3`=constant-voltage, `4`=charge-done, `5`=not-charging. The UI reports *Charging* only for pre-charge/CC/CV (`1`/`2`/`3`). Battery % from `axp2202-battery/capacity`; USB presence from `axp2202-usb/online`.

### Components

| File | Role |
|---|---|
| `pak/src/{main,settings,settings_io}.c` | UI binary `batterycare.elf`. 3-row menu: Charge Limit (editable), Current Charge + Power State (read-only). On change: writes `settings.cfg`, calls `hook-handler.sh ensure`. Reads PMIC regs only to display. |
| `pak/src/ui_{utils,fonts}.{c,h}` | Vendored verbatim from NextUI. Leave as-is. |
| `pak/daemon/battery-care-daemon.sh` | The enforcer. 30 s poll: read capacity, toggle reg `0x19` bit 1 with 5% hysteresis. |
| `pak/hook-handler.sh` | `start\|stop\|reload\|ensure`. Owns the pidfile; stop=SIGTERM, reload=SIGUSR1; restores charger on stop. |
| `pak/installer.sh` | Installs/removes the boot hook. |
| `pak/hooks/boot.sh` | Boot hook (→ `.hooks/boot.d/`). Starts the daemon, or self-removes + restores charger if the pak is gone. |
| `pak/launch.sh` | Pak entry. Installs boot hook if missing, runs `hook-handler ensure`, execs the elf. |
| `pak/{Makefile,src/Makefile}` | Docker cross-compile + assemble + push. |

### Control flow

- **Change value** → write `settings.cfg` → `hook-handler ensure` → target<100: start or SIGUSR1 the daemon; target=100 (Off): stop + restore charger.
- **Boot** → `.hooks/boot.d/battery-care.sh` → `hook-handler ensure` → daemon re-applies the cap (kernel resets reg `0x19` at boot).
- **Deep sleep** → daemon frozen; reg `0x19` preserved, so an already-capped battery holds, but charging below the cap continues until wake (see Known issues).
- **Uninstall** → daemon sees its dir gone next tick → restores charger + exits; boot hook self-removes next boot.

### Invariants (don't "fix" without reading)

- Only reg `0x19` bit 1 is ever written, always read-modify-write. Restore = `cur | 2` = `0x06`.
- Kernel resets reg `0x19` on reboot (boot hook re-applies) but preserves it across deep sleep (no resume hook needed).
- Daemon must `trap '' HUP`: busybox HUPs the orphaned daemon when its launching shell exits. Reload is SIGUSR1, not HUP.
- No `nohup`/`setsid` on device. Daemon is launched `"$DAEMON" >> "$LOG" 2>&1 &` with the parent writing the pidfile. It survives in NextUI's process tree; launching via `adb shell` does NOT (adb kills its child group). Test daemon lifetime via the app, not adb.
- UI `HYST_PERCENT` (settings.c) must equal daemon `HYST` (both 5).
- Target 100 = Off = no daemon running.

### State on device

| Path | Purpose |
|---|---|
| `/mnt/SDCARD/Tools/tg5040/Battery Care.pak/` | Installed pak |
| `$USERDATA_PATH/Battery Care/settings.cfg` | `target=NN` (survives uninstall) |
| `$USERDATA_PATH/.hooks/boot.d/battery-care.sh` | Boot hook (installed by launch.sh) |
| `$LOGS_PATH/battery-care-daemon.log` | Daemon log |
| `/tmp/battery-care-daemon.pid` | Daemon pidfile (parent-written) |

### Build pipeline

`make pak` shallow-clones NextUI into `pak/ext/NextUI` (gitignored), stages `pak/src/` +
`pak/res/` into `ext/NextUI/workspace/batterycare/`, then cross-compiles in
`ghcr.io/loveretro/tg5040-toolchain`, linking NextUI's common sources + `libmsettings`.
Output assembles to `pak/build/Battery Care.pak/`. `USERDATA_PATH`/`LOGS_PATH`/`PLATFORM`
are set by NextUI at runtime; scripts fall back to tg5040 defaults when run by hand.
clangd flags NextUI headers (`defines.h`, `api.h`) as missing — they resolve only in
Docker, which is the source of truth.

## License

Battery Care is licensed under the **GNU General Public License v3.0** (see
[`LICENSE`](LICENSE)). It builds against and vendors source from
[NextUI](https://github.com/LoveRetro/NextUI) (`ui_utils.*`, `ui_fonts.*`, and the
common build sources), which is GPLv3 — so this derivative work is GPLv3 as well.

### Credits

- **NextUI** by LoveRetro — the launcher, toolchain, and common UI sources this pak
  builds on. GPLv3.
- **Rounded Mplus 1c** (`pak/res/font.ttf`) — © 2016 The Rounded M+ Project Authors,
  licensed under the [SIL Open Font License 1.1](https://openfontlicense.org/). The
  font's own metadata embeds this copyright notice and license reference, as the OFL
  permits for bundled software.
