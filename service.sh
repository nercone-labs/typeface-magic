# shellcheck shell=ash
MODDIR=${0%/*}
FS_MODDIR="$MODDIR"
. "$MODDIR/common/lib.sh"
fs_wait_boot
rm -f "$MODDIR/.bootcount"

[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
fs_apply_components "$DISABLE_COMPONENTS"
