#!/bin/sh
# Battery Care daemon.
#
# Polls battery SoC and toggles the AXP2202 charger-enable bit (reg 0x19 bit 1)
# to cap charging at a user-configured percentage. The target is read from
# settings.cfg on startup and on SIGUSR1 (sent by the app when the user changes
# the value). On SIGTERM/SIGINT we restore the charger to enabled.
#
# When run by hand for testing:  battery-care-daemon.sh
# Stop with Ctrl-C; the restore on exit is guaranteed by the trap.

set -u

REGS="/sys/kernel/debug/regmap/6-0034/registers"
CAP_FILE="/sys/class/power_supply/axp2202-battery/capacity"
USB_FILE="/sys/class/power_supply/axp2202-usb/online"
PIDFILE="/tmp/battery-care-daemon.pid"

POLL_SECONDS=30
HYST=5                   # re-enable when cap <= TARGET - HYST
TARGET_OFF=100           # target == 100 means "no cap"
CHARGER_BIT=2            # reg 0x19 bit 1

# Pluggable cfg path. NextUI exports USERDATA_PATH; fall back when invoked by hand.
: "${USERDATA_PATH:=/mnt/SDCARD/.userdata/tg5040}"
CFG="$USERDATA_PATH/Battery Care/settings.cfg"

# Our own pak directory (parent of daemon/). Resolved once at startup while it
# still exists; we stat it each tick to self-terminate if the user uninstalls.
PAK_DIR=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)

TARGET=$TARGET_OFF
SLEEP_PID=""

# Ignore SIGHUP from the get-go — when our launching shell exits, busybox sends
# HUP to the orphan group and would otherwise kill us. Reload via SIGUSR1.
trap '' HUP

log() {
    printf '[battery-care-daemon] %s %s\n' "$(date '+%H:%M:%S')" "$*" >&2
}

# Read reg 0x19 as a decimal integer.
read_reg19() {
    val=$(grep '^19:' "$REGS" 2>/dev/null | awk '{print $2}')
    [ -z "$val" ] && { echo ""; return 1; }
    printf '%d\n' "$((0x$val))"
}

write_reg19() {
    new=$1
    printf '19 %02x\n' "$new" > "$REGS" 2>/dev/null
}

restore_charger() {
    cur=$(read_reg19) || { log "restore: cannot read reg 0x19"; return; }
    new=$(( cur | CHARGER_BIT ))
    if [ "$cur" -ne "$new" ]; then
        write_reg19 "$new"
        log "restore: 0x19 $(printf 0x%02x $cur) -> $(printf 0x%02x $new)"
    fi
}

load_target() {
    if [ ! -f "$CFG" ]; then
        TARGET=$TARGET_OFF
        log "no cfg at $CFG; target=Off"
        return
    fi
    val=$(awk -F= '/^target=/ { print $2; exit }' "$CFG" 2>/dev/null | tr -d '[:space:]')
    case "$val" in
        ''|*[!0-9]*) TARGET=$TARGET_OFF ;;
        *)           TARGET=$val ;;
    esac
    log "loaded target=$TARGET from $CFG"
}

on_reload() {
    log "SIGUSR1 received; reloading target"
    load_target
    if [ "$TARGET" -ge "$TARGET_OFF" ]; then
        log "target reverted to Off; restoring and exiting"
        restore_charger
        exit 0
    fi
    # Interrupt sleep so the new target takes effect immediately.
    [ -n "$SLEEP_PID" ] && kill "$SLEEP_PID" 2>/dev/null
}

on_sigterm() {
    log "signal received; restoring and exiting"
    restore_charger
    exit 0
}

trap on_reload  USR1
trap on_sigterm INT TERM

# --- preflight ----------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    log "must run as root (need to write $REGS)"; exit 1
fi
if [ ! -f "$REGS" ]; then
    log "regmap debugfs not present at $REGS; is debugfs mounted?"; exit 1
fi
if [ ! -r "$CAP_FILE" ]; then
    log "capacity file missing at $CAP_FILE"; exit 1
fi

# Pidfile is written by hook-handler.sh (parent owns it). We leave it alone.

load_target
if [ "$TARGET" -ge "$TARGET_OFF" ]; then
    log "target=Off; nothing to do; restoring and exiting"
    restore_charger
    exit 0
fi

log "started; pid=$$ target=$TARGET hyst=$HYST poll=${POLL_SECONDS}s"

# --- main loop ----------------------------------------------------------------

while :; do
    # Self-terminate if our pak was uninstalled (file manager delete, etc.).
    # Restores the charger so an uninstall never leaves charging capped.
    if [ -n "$PAK_DIR" ] && [ ! -d "$PAK_DIR" ]; then
        log "pak directory gone ($PAK_DIR); restoring charger and exiting"
        restore_charger
        rm -f "$PIDFILE"
        exit 0
    fi

    cap=$(cat "$CAP_FILE" 2>/dev/null)
    usb=$(cat "$USB_FILE" 2>/dev/null)
    cur=$(read_reg19) || cur=""

    if [ -n "$cap" ] && [ -n "$usb" ] && [ -n "$cur" ]; then
        charger_on=$(( cur & CHARGER_BIT ))

        if [ "$usb" -eq 1 ]; then
            if [ "$cap" -ge "$TARGET" ] && [ "$charger_on" -ne 0 ]; then
                new=$(( cur & ~CHARGER_BIT ))
                write_reg19 "$new"
                log "cap=${cap}% >= target=${TARGET}%, charger OFF (0x19 $(printf 0x%02x $cur)->$(printf 0x%02x $new))"
            elif [ "$cap" -le $(( TARGET - HYST )) ] && [ "$charger_on" -eq 0 ]; then
                new=$(( cur | CHARGER_BIT ))
                write_reg19 "$new"
                log "cap=${cap}% <= target-hyst=$((TARGET - HYST))%, charger ON (0x19 $(printf 0x%02x $cur)->$(printf 0x%02x $new))"
            fi
        fi
    else
        log "skipping tick (read failure)  cap='$cap' usb='$usb' cur='$cur'"
    fi

    # Sleep interruptibly so SIGUSR1 (reload) can wake us.
    sleep "$POLL_SECONDS" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null
    SLEEP_PID=""
done
