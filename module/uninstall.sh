#!/system/bin/sh
# Caventus cleanup script on module removal

PID_FILE="/data/adb/caventus/watchdog.pid"
if [ -f "$PID_FILE" ]; then
  _pid=$(cat "$PID_FILE" 2>/dev/null || true)
  case "$_pid" in
    ''|*[!0-9]*) ;;
    *) kill "$_pid" 2>/dev/null || true ;;
  esac
fi

rm -rf /data/adb/caventus
