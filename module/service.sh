#!/system/bin/sh
# Caventus late-boot service script

MODDIR=${0%/*}

elapsed=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$elapsed" -lt 180 ]; do
  sleep 2
  elapsed=$((elapsed + 2))
done

# Allow Android init swapon_all / zram writeback setup to settle first
sleep 8

CONF_DIR="/data/adb/caventus"
CONF_FILE="$CONF_DIR/config.env"
mkdir -p "$CONF_DIR" 2>/dev/null || true

if [ ! -f "$CONF_FILE" ]; then
  "$MODDIR/bin/caventus-ctl.sh" reset-defaults >/dev/null 2>&1 || true
fi

exec "$MODDIR/bin/caventus-ctl.sh" apply
