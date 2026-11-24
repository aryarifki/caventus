#!/system/bin/sh
# Caventus installer guard and permission setup for Pixel 6 (oriole)

SKIPUNZIP=0

if [ "$ARCH" != "arm64" ]; then
  abort "! Caventus requires arm64 (Pixel 6 / oriole). Detected: $ARCH"
fi

DEV=$(getprop ro.product.device)
[ -z "$DEV" ] && DEV=$(getprop ro.product.vendor.device)
[ -z "$DEV" ] && DEV=$(getprop ro.build.product)

if [ "$DEV" != "oriole" ] && [ ! -f /sdcard/.caventus_force ]; then
  abort "! Device '$DEV' is not Pixel 6 (oriole). Create /sdcard/.caventus_force to override."
fi

ui_print "=============================================="
ui_print "  Caventus — Pixel 6 (oriole) RAM Optimizer   "
ui_print "=============================================="
ui_print "- Device      : $DEV (arch=$ARCH, API=$API)"
ui_print "- Android     : $(getprop ro.build.version.release) ($(getprop ro.build.display.id))"
ui_print "- Kernel      : $(uname -r)"

MEM_TOTAL_KB=$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)
[ -n "$MEM_TOTAL_KB" ] && ui_print "- MemTotal    : $((MEM_TOTAL_KB / 1024)) MB"

if [ -r /sys/block/zram0/disksize ]; then
  CUR_ZRAM=$(cat /sys/block/zram0/disksize 2>/dev/null)
  CUR_ALGO=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)
  ui_print "- Current zRAM: $((CUR_ZRAM / 1048576)) MB | algos: $CUR_ALGO"
  case "$CUR_ALGO" in
    *zstd*) ui_print "- zstd support: YES" ;;
    *)      ui_print "! Warning: zstd not listed in comp_algorithm; runtime will fallback to lz4/lzo-rle." ;;
  esac
fi

CUR_FILTER=$(getprop dalvik.vm.dex2oat-filter)
ui_print "- ART filter  : ${CUR_FILTER:-unset} -> speed-profile"

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/caventus-ctl.sh" 0 0 0755

ui_print "----------------------------------------------"
ui_print "- Installed cleanly (overlay-free, no /system)."
ui_print "- Reboot to apply 4 GB zstd zRAM, LMKD & ART."
ui_print "- Optional (while charging): run"
ui_print "  su -c \"/data/adb/modules/caventus_oriole_ram/bin/caventus-ctl.sh recompile\""
ui_print "=============================================="
