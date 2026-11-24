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
  CUR_ZRAM=$(cat /sys/block/zram0/disksize 2>/dev/null || echo 0)
  case "$CUR_ZRAM" in ''|*[!0-9]*) CUR_ZRAM=0 ;; esac
  CUR_ALGO=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "unknown")
  ui_print "- Current zRAM: $((CUR_ZRAM / 1048576)) MB | algos: $CUR_ALGO"
  case "$CUR_ALGO" in
    *lz77eh*) ui_print "- lz77eh HW   : YES (GS101 Emerald Hill)" ;;
    *)        ui_print "- lz77eh HW   : NO (will fallback to zstd/lz4)" ;;
  esac
  case "$CUR_ALGO" in
    *zstd*) ui_print "- zstd support: YES" ;;
    *)      ui_print "! Warning: zstd not listed in comp_algorithm." ;;
  esac
fi

CUR_FILTER=$(getprop dalvik.vm.dex2oat-filter)
ui_print "- ART filter  : ${CUR_FILTER:-unset} -> speed-profile"

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/caventus-ctl.sh" 0 0 0755
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644

ui_print "----------------------------------------------"
ui_print "- Installed v1.3.0 cleanly (overlay-free)."
ui_print "- Oriole Optimal boot-safe defaults will apply"
ui_print "  automatically on first reboot:"
ui_print "  4 GB lz77eh + mmd, speed-profile, PSI LMKD,"
ui_print "  GS101 sched/CPUFreq/UFS/Mali, SF stock (off)."
ui_print "- Open KernelSU Manager -> WebUI to customize"
ui_print "  all profiles & run ART speed-profile recompile."
ui_print "- Or tap Action (Run) in KernelSU Manager."
ui_print "- Reboot to apply all boot-time optimizations."
ui_print "=============================================="
