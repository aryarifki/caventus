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
  CUR_ZRAM_MB=$(awk -v b="$CUR_ZRAM" 'BEGIN { printf "%.0f", int(b / 1048576) }' 2>/dev/null || echo 0)
  CUR_ALGO=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "unknown")
  ui_print "- Current zRAM: ${CUR_ZRAM_MB} MB | algos: $CUR_ALGO"
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
set_perm "$MODPATH/bin/caventus-diag.sh" 0 0 0755
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644

ui_print "----------------------------------------------"
ui_print "- Installed v1.4.1 cleanly (overlay-free)."
ui_print "- 64-bit safe mmd sync: 5 GB lz77eh zRAM,"
ui_print "  anti-odrefresh ART, relaxed PSI LMKD,"
ui_print "  GS101 stock-safe sched."
ui_print "- Built-in Forensic Diagnostic Capture exports"
ui_print "  to /sdcard/Download/Caventus-Logs/ & WebUI."
ui_print "- Open KernelSU Manager -> WebUI to capture"
ui_print "  logs, tune profiles & run speed-profile."
ui_print "- Or tap Action (Run) in KernelSU Manager."
ui_print "- Reboot to apply all boot-time optimizations."
ui_print "=============================================="
