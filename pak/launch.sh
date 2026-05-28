#!/bin/sh
DIR="$(dirname "$0")"
cd "$DIR" || exit 1

[ -z "$PLATFORM" ] && PLATFORM="tg5040"

export PAK_DIR="$DIR"
export LD_LIBRARY_PATH="$DIR/lib/$PLATFORM:$DIR/lib:$LD_LIBRARY_PATH"

# Auto-install the boot hook on first launch (idempotent thereafter).
if [ -n "$USERDATA_PATH" ] && [ ! -f "$USERDATA_PATH/.hooks/boot.d/battery-care.sh" ]; then
    "$DIR/installer.sh" enable
fi

# Reconcile daemon with current settings.cfg before showing the menu.
"$DIR/hook-handler.sh" ensure

"$DIR/bin/$PLATFORM/batterycare.elf" > "$DIR/battery-care.log" 2>&1
