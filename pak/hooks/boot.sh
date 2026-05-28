#!/bin/sh
# Battery Care boot hook. NextUI runs everything in $USERDATA_PATH/.hooks/boot.d/
# at startup. Self-healing: if our pak directory has been deleted, this script
# removes itself, kills any orphan daemon, and restores the charger bit.

PAK="$SDCARD_PATH/Tools/$PLATFORM/Battery Care.pak"
PIDFILE="/tmp/battery-care-daemon.pid"
REGS="/sys/kernel/debug/regmap/6-0034/registers"

if [ ! -d "$PAK" ]; then
    # Pak was uninstalled. Clean up.
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE" 2>/dev/null)
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null
        rm -f "$PIDFILE"
    fi
    if [ -f "$REGS" ]; then
        val=$(grep '^19:' "$REGS" 2>/dev/null | awk '{print $2}')
        if [ -n "$val" ]; then
            new=$(( 0x$val | 2 ))
            printf '19 %02x\n' "$new" > "$REGS" 2>/dev/null
        fi
    fi
    rm -f "$0"
    exit 0
fi

exec "$PAK/hook-handler.sh" ensure
