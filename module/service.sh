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

"$MODDIR/bin/caventus-ctl.sh" diag-boot-snapshot pre >/dev/null 2>&1 || true
"$MODDIR/bin/caventus-ctl.sh" apply
"$MODDIR/bin/caventus-ctl.sh" diag-boot-snapshot post >/dev/null 2>&1 || true

AUTO_BOOT_DIAG=1
if [ -f "$CONF_FILE" ]; then
  _abd=$(grep -m1 '^AUTO_BOOT_DIAG=' "$CONF_FILE" 2>/dev/null | cut -d= -f2 || echo 1)
  [ -n "$_abd" ] && AUTO_BOOT_DIAG="$_abd"
fi

if [ "$AUTO_BOOT_DIAG" = "1" ]; then
  (
    sleep 10
    "$MODDIR/bin/caventus-ctl.sh" diag-capture --duration=0 --export=1 --tag=boot >/dev/null 2>&1
  ) </dev/null >/dev/null 2>&1 &
fi

exit 0
