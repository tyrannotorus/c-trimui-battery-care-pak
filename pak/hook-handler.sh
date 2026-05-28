#!/bin/sh
# Battery Care hook handler — start/stop/reload/ensure for the daemon.
# Invoked by launch.sh, the in-app value-cycle, and the boot hook.
#
# Usage:
#   hook-handler.sh start    Start the daemon if not already running.
#   hook-handler.sh stop     Stop the daemon and restore the charger bit.
#   hook-handler.sh reload   Signal the daemon (SIGUSR1) to re-read settings.cfg.
#   hook-handler.sh ensure   Reconcile daemon state with settings.cfg.

DIR="$(dirname "$0")"
PIDFILE="/tmp/battery-care-daemon.pid"
DAEMON="$DIR/daemon/battery-care-daemon.sh"
REGS="/sys/kernel/debug/regmap/6-0034/registers"

: "${USERDATA_PATH:=/mnt/SDCARD/.userdata/tg5040}"
: "${LOGS_PATH:=$USERDATA_PATH/logs}"
CFG="$USERDATA_PATH/Battery Care/settings.cfg"
LOG="$LOGS_PATH/battery-care-daemon.log"

log() { printf '[hook-handler] %s\n' "$*" >&2; }

# Verify a PID really is our daemon (not a recycled PID handed out by the kernel).
# Inspects /proc/$pid/cmdline for our script name.
is_our_daemon() {
    pid="$1"
    [ -n "$pid" ] && [ -d "/proc/$pid" ] || return 1
    cl=$(tr -d '\0' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$cl" in
        *battery-care-daemon.sh*) return 0 ;;
    esac
    return 1
}

is_running() {
    [ -f "$PIDFILE" ] || return 1
    pid=$(cat "$PIDFILE" 2>/dev/null) || return 1
    is_our_daemon "$pid"
}

get_pid() { [ -f "$PIDFILE" ] && cat "$PIDFILE" 2>/dev/null; }

# Restore reg 0x19 bit 1 to 1 (charger enabled), preserving other bits.
restore_charger() {
    [ -f "$REGS" ] || return
    val=$(grep '^19:' "$REGS" 2>/dev/null | awk '{print $2}')
    [ -z "$val" ] && return
    new=$(( 0x$val | 2 ))
    printf '19 %02x\n' "$new" > "$REGS" 2>/dev/null
}

start_daemon() {
    if is_running; then
        log "already running (pid=$(get_pid))"
        return 0
    fi
    [ -x "$DAEMON" ] || { log "daemon missing at $DAEMON"; return 1; }
    mkdir -p "$LOGS_PATH"
    "$DAEMON" >> "$LOG" 2>&1 &
    echo $! > "$PIDFILE"
    log "started pid=$! (logs: $LOG)"
}

stop_daemon() {
    if is_running; then
        pid=$(get_pid)
        kill -TERM "$pid" 2>/dev/null
        # Daemon's SIGTERM handler restores charger and exits within ~1s.
        n=0
        while [ $n -lt 5 ] && is_our_daemon "$pid"; do
            n=$((n+1))
            sleep 1
        done
        if is_our_daemon "$pid"; then
            kill -9 "$pid" 2>/dev/null
            log "force-killed pid=$pid"
        else
            log "stopped pid=$pid"
        fi
    fi
    rm -f "$PIDFILE"
    # Always restore — covers crashed-daemon recovery too.
    restore_charger
}

reload_daemon() {
    if is_running; then
        kill -USR1 "$(get_pid)" 2>/dev/null
        log "SIGUSR1 sent to pid=$(get_pid)"
    else
        log "not running; starting instead"
        start_daemon
    fi
}

read_target() {
    if [ -f "$CFG" ]; then
        awk -F= '/^target=/ { print $2; exit }' "$CFG" 2>/dev/null | tr -d '[:space:]'
    else
        echo 100
    fi
}

ensure_state() {
    target=$(read_target)
    case "$target" in
        ''|*[!0-9]*) target=100 ;;
    esac
    if [ "$target" -ge 100 ]; then
        stop_daemon
    elif is_running; then
        reload_daemon
    else
        start_daemon
    fi
}

case "$1" in
    start)  start_daemon ;;
    stop)   stop_daemon ;;
    reload) reload_daemon ;;
    ensure) ensure_state ;;
    *)      echo "usage: $0 start|stop|reload|ensure" >&2; exit 2 ;;
esac
