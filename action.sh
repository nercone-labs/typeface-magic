# shellcheck shell=ash
MODDIR=${0%/*}
FS_MODDIR="$MODDIR"
. "$MODDIR/common/lib.sh"
echo "== TypeFace Magic =="
echo "API: $(getprop ro.build.version.sdk)"
for f in "$FS_SRC_MAIN" "$FS_SRC_FALLBACK" "$FS_SRC_CUSTOM"; do
  [ -f "$f" ] || continue
  if grep -q "$FS_MARK" "$f"; then echo "[applied] $f"; else echo "[not applied] $f"; fi
done
echo
echo "== typeface_magic.log (last 40 lines) =="
tail -n 40 "$FS_LOG" 2>/dev/null
