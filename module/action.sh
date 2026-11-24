#!/system/bin/sh
# Caventus interactive action for KernelSU Manager Action button

MODDIR=${0%/*}

"$MODDIR/bin/caventus-ctl.sh" compact
echo ""
"$MODDIR/bin/caventus-ctl.sh" status
echo ""
echo "Tip: To recompile existing apps to speed-profile (run once while charging):"
echo "  su -c \"$MODDIR/bin/caventus-ctl.sh recompile\""
