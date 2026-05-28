#!/bin/sh
# Install/remove the Battery Care boot hook.
# Usage: installer.sh enable|disable

[ -n "$SDCARD_PATH" ]   || { echo "$0: SDCARD_PATH unset"   >&2; exit 1; }
[ -n "$PLATFORM" ]      || { echo "$0: PLATFORM unset"      >&2; exit 1; }
[ -n "$USERDATA_PATH" ] || { echo "$0: USERDATA_PATH unset" >&2; exit 1; }

PAK="$SDCARD_PATH/Tools/$PLATFORM/Battery Care.pak"
HOOKS_DST="$USERDATA_PATH/.hooks"
HOOK_NAME="battery-care.sh"

case "$1" in
    enable)
        mkdir -p "$HOOKS_DST/boot.d"
        cp "$PAK/hooks/boot.sh" "$HOOKS_DST/boot.d/$HOOK_NAME"
        chmod +x "$HOOKS_DST/boot.d/$HOOK_NAME"
        ;;
    disable)
        rm -f "$HOOKS_DST/boot.d/$HOOK_NAME"
        ;;
    *)
        echo "usage: $0 enable|disable" >&2; exit 2 ;;
esac
