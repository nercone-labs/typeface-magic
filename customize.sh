# shellcheck shell=ash

FS_MODDIR="$MODPATH"
FS_INSTALLING=1
. "$MODPATH/common/lib.sh"
. "$MODPATH/config.sh"

ui_print "*******************************"
ui_print "  TypeFace Magic"
ui_print "*******************************"

[ "$API" -ge 33 ] || abort "! This module requires Android 13 (API 33) or later (this environment: API $API)"
[ "$API" -le 37 ] || ui_print "! Unverified Android version (API $API). Continuing anyway."
if [ "$KSU" = true ]; then
  ui_print "- KernelSU: a metamodule such as meta-overlayfs is required to temporarily swap the system directory."
fi

rm -f "$FS_LOG" "$FS_STATE"
mkdir -p "$MODPATH/system/fonts"

fs_find() {
  for _e in ttf otf TTF OTF; do
    if [ -f "$MODPATH/fonts/$1.$_e" ]; then echo "$MODPATH/fonts/$1.$_e"; return 0; fi
  done
  return 1
}

fs_take() {
  FS_OUT=""
  _src=$(fs_find "$1") || return 1
  fs_inspect "$_src"
  case $? in
    0) ;;
    2) ui_print "! $(basename "$_src"): TTC (Font Collection) is not supported."; return 2 ;;
    *) ui_print "! $(basename "$_src"): Cannot read as TTF/OTF."; return 2 ;;
  esac
  FS_OUT="$FS_PREFIX-$1.$FI_KIND"
  mv -f "$_src" "$MODPATH/system/fonts/$FS_OUT" || return 2
  if [ "$FI_VAR" = 1 ]; then _d="Variable wght $FI_WMIN-$FI_WMAX"; else _d="Static"; fi
  [ -n "$FI_AXES" ] && _d="$_d / Axes: $FI_AXES"
  ui_print "  $1: $(basename "$_src") ($_d)"
  return 0
}

ui_print "- Checking fonts..."
FS_ROLES=""
for R in Sans Serif Mono; do
  r=$(echo "$R" | tr 'A-Z' 'a-z')
  fs_take "$R"; rc=$?
  if [ $rc -ne 0 ]; then
    [ "$R" = Sans ] && abort "! fonts/Sans.ttf (or .otf) not found."
    [ $rc -eq 1 ] && ui_print "  $R: None (using the system default)"
    continue
  fi
  u="$FS_OUT|$FI_VAR|$FI_WMIN|$FI_WMAX"
  fs_take "$R-Italic"
  if [ $? -eq 0 ]; then i="$FS_OUT|$FI_VAR|$FI_WMIN|$FI_WMAX"; else i="|0|400|400"; fi
  eval "ax=\${$(echo "$R" | tr 'a-z' 'A-Z')_AXES}"
  FS_ROLES="$FS_ROLES$r|$u|$i|$ax;"
done
echo "FS_ROLES='$FS_ROLES'" > "$FS_CONF"
rm -rf "$MODPATH/fonts"

ui_print "- Generating font customization XML..."
for s in "$FS_SRC_MAIN" "$FS_SRC_FALLBACK" "$FS_SRC_CUSTOM"; do
  [ -f "$s" ] && ui_print "  Detected: $s"
done
FORCE=1 fs_generate_all
if [ -f "$FS_DST_MAIN" ]; then
  ui_print "- Generated (Log: $MODPATH/typeface_magic.log)"
elif grep -q "$FS_MARK" "$FS_SRC_MAIN" 2>/dev/null; then
  ui_print "- An older version is still active, so the XML will be generated on the next boot."
else
  abort "! Failed to generate fonts.xml. Please check typeface_magic.log!"
fi

set_perm_recursive "$MODPATH/system" 0 0 0755 0644
ui_print "- The changes will take effect after a restart. To revert to the original settings, disable this module and reboot."
