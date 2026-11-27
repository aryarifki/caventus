#!/system/bin/sh
# Caventus interactive Action script for KernelSU Manager Run/Execute button

MODDIR=${0%/*}
CTL="$MODDIR/bin/caventus-ctl.sh"
CONF_FILE="/data/adb/caventus/config.env"

ACTION_MODE="both"
ART_DEX2OAT_FILTER="speed-profile"
RECOMPILE_SCOPE="all"

if [ -f "$CONF_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONF_FILE"
fi

echo "=============================================="
echo "  Caventus — Pixel 6 (oriole) Action Runner   "
echo "=============================================="
echo "Mode: ${ACTION_MODE:-both} | Filter: ${ART_DEX2OAT_FILTER:-speed-profile} | Scope: ${RECOMPILE_SCOPE:-all}"
echo ""

case "${ACTION_MODE:-both}" in
  compact)
    "$CTL" compact
    ;;
  recompile)
    "$CTL" recompile --filter="${ART_DEX2OAT_FILTER:-speed-profile}" --scope="${RECOMPILE_SCOPE:-all}"
    ;;
  diag)
    "$CTL" diag-capture --duration=15 --export=1 --tag=action
    ;;
  both|*)
    "$CTL" compact
    echo ""
    "$CTL" recompile --filter="${ART_DEX2OAT_FILTER:-speed-profile}" --scope="${RECOMPILE_SCOPE:-all}"
    ;;
esac

echo ""
"$CTL" status
echo ""
echo "Action finished."
