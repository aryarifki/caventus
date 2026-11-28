#!/system/bin/sh
# Caventus cleanup script on module removal

PID_FILE="/data/adb/caventus/watchdog.pid"
DIAG_PID_FILE="/data/adb/caventus/diag-daemon.pid"
for _pf in "$PID_FILE" "$DIAG_PID_FILE"; do
  if [ -f "$_pf" ]; then
    _pid=$(cat "$_pf" 2>/dev/null || true)
    case "$_pid" in
      ''|*[!0-9]*) ;;
      *) kill "$_pid" 2>/dev/null || true ;;
    esac
  fi
done

rm -rf /data/adb/caventus
