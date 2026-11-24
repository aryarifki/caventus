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
  cat <<'EOF' > "$CONF_FILE"
# Caventus user overrides (uncomment to customize, then reboot)
# ZRAM_SIZE_MB=4096
# ZRAM_ALGO=zstd
# VM_SWAPPINESS=80
# VM_VFS_CACHE_PRESSURE=100
# VM_WATERMARK_SCALE_FACTOR=60
# VM_DIRTY_BACKGROUND_RATIO=5
# VM_DIRTY_RATIO=15
# MGLRU_MIN_TTL_MS=1000
# SWAPOFF_HEADROOM_PCT=80
EOF
fi

exec "$MODDIR/bin/caventus-ctl.sh" apply
