# shellcheck shell=ash
MODDIR=${0%/*}
FS_MODDIR="$MODDIR"
. "$MODDIR/common/lib.sh"

# This runs before the package manager starts, and the module directory is removed right after.
FS_RECORD=$(cat "$FS_COMPONENTS" 2>/dev/null)
[ -n "$FS_RECORD" ] || exit 0
FS_LOG=/dev/null
( fs_wait_boot; fs_components "" "$FS_RECORD" ) < /dev/null > /dev/null 2>&1 &
