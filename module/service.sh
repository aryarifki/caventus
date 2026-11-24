#!/system/bin/sh
# Caventus late-boot service script

MODDIR=${0%/*}

elapsed=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$elapsed" -lt 180 ]; do
  sleep 2
  elapsed=$((elapsed + 2))
done

# Wait for Android 17 mmd / init zram0 setup to settle (max 20s)
zwait=0
while [ -r /sys/block/zram0/initstate ] && [ "$(cat /sys/block/zram0/initstate 2>/dev/null)" != "1" ] && [ "$zwait" -lt 20 ]; do
  sleep 1
  zwait=$((zwait + 1))
done
sleep 5

CONF_DIR="/data/adb/caventus"
CONF_FILE="$CONF_DIR/config.env"
mkdir -p "$CONF_DIR" 2>/dev/null || true

if [ ! -f "$CONF_FILE" ]; then
  "$MODDIR/bin/caventus-ctl.sh" init-defaults >/dev/null 2>&1 || true
fi

exec "$MODDIR/bin/caventus-ctl.sh" apply
