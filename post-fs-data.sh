# shellcheck shell=ash
MODDIR=${0%/*}
FS_MODDIR="$MODDIR"
. "$MODDIR/common/lib.sh"

[ -f "$FS_LOG" ] && [ "$(wc -c < "$FS_LOG")" -gt 65536 ] && mv -f "$FS_LOG" "$FS_LOG.old"

BOOTLOOP_GUARD=3
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
if [ "${BOOTLOOP_GUARD:-0}" -gt 0 ] 2>/dev/null; then
  n=$(cat "$MODDIR/.bootcount" 2>/dev/null)
  n=$(( ${n:-0} + 1 ))
  if [ "$n" -gt "$BOOTLOOP_GUARD" ]; then
    rm -f "$MODDIR/.bootcount" "$FS_STATE" "$FS_DST_MAIN" "$FS_DST_FALLBACK" "$FS_DST_CUSTOM"
    touch "$MODDIR/disable"
    fs_log "WARN: Modules were disabled because boot completion failed $BOOTLOOP_GUARD times in a row."
    exit 0
  fi
  echo "$n" > "$MODDIR/.bootcount"
fi

fs_generate_all
