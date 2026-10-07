# shellcheck shell=ash

FS_MARK="typeface-magic: generated file"
FS_PREFIX="TypeFaceMagic"
FS_LIB="$FS_MODDIR/common"
FS_CONF="$FS_MODDIR/typeface_magic.conf"
FS_STATE="$FS_MODDIR/.state"
FS_LOG="$FS_MODDIR/typeface_magic.log"

FS_SRC_MAIN=/system/etc/fonts.xml
FS_SRC_FALLBACK=/system/etc/font_fallback.xml
FS_SRC_CUSTOM=/product/etc/fonts_customization.xml
FS_DST_MAIN="$FS_MODDIR/system/etc/fonts.xml"
FS_DST_FALLBACK="$FS_MODDIR/system/etc/font_fallback.xml"
FS_DST_CUSTOM="$FS_MODDIR/system/product/etc/fonts_customization.xml"

fs_log() {
  echo "[$(date '+%F %T' 2>/dev/null)] $*" >> "$FS_LOG"
  if [ -n "$FS_INSTALLING" ]; then ui_print "  $*"; fi
}

fs_api() {
  if [ -n "$API" ]; then echo "$API"; else getprop ro.build.version.sdk; fi
}

fs_bytes() { od -An -v -tu1 -j "$2" -N "$3" "$1" 2>/dev/null | tr -s ' \n' '  '; }

fs_inspect() {
  FI_KIND=""; FI_VAR=0; FI_WMIN=400; FI_WMAX=400; FI_AXES=""
  _f=$1
  [ -s "$_f" ] || return 1
  # shellcheck disable=SC2046
  set -- $(fs_bytes "$_f" 0 12)
  [ $# -eq 12 ] || return 1
  case "$1.$2.$3.$4" in
    0.1.0.0|116.114.117.101) FI_KIND=ttf ;;   # 0x00010000 / 'true'
    79.84.84.79) FI_KIND=otf ;;               # 'OTTO'
    116.116.99.102) FI_KIND=ttc; return 2 ;;  # 'ttcf' is unsupported
    *) return 1 ;;
  esac
  _nt=$(( $5 * 256 + $6 ))
  [ "$_nt" -gt 0 ] && [ "$_nt" -lt 512 ] || return 1
  _fv=$(fs_bytes "$_f" 12 $(( _nt * 16 )) | awk '{
    for (i = 1; i + 15 <= NF; i += 16)
      if ($i == 102 && $(i+1) == 118 && $(i+2) == 97 && $(i+3) == 114) {
        printf "%d", $(i+8)*16777216 + $(i+9)*65536 + $(i+10)*256 + $(i+11); exit
      }
  }')
  [ -n "$_fv" ] || return 0   # no fvar = static
  # shellcheck disable=SC2046
  set -- $(fs_bytes "$_f" "$_fv" 16)
  [ $# -eq 16 ] || return 0
  _ao=$(( $5 * 256 + $6 )); _ac=$(( $9 * 256 + ${10} )); _as=$(( ${11} * 256 + ${12} ))
  [ "$_ac" -gt 0 ] && [ "$_ac" -lt 64 ] && [ "$_as" -ge 20 ] || return 0
  FI_AXES=$(fs_bytes "$_f" $(( _fv + _ao )) $(( _ac * _as )) | awk -v AS="$_as" '
    function fx(i,  v) { v = $i*16777216 + $(i+1)*65536 + $(i+2)*256 + $(i+3)
                         if (v >= 2147483648) v -= 4294967296
                         return v / 65536 }
    { for (i = 1; i + 15 <= NF; i += AS)
        printf "%c%c%c%c:%g:%g:%g ", $i, $(i+1), $(i+2), $(i+3), fx(i+4), fx(i+8), fx(i+12) }')
  for _a in $FI_AXES; do
    case "$_a" in
      wght:*)
        FI_VAR=1
        FI_WMIN=$(echo "$_a" | cut -d: -f2 | cut -d. -f1)
        FI_WMAX=$(echo "$_a" | cut -d: -f4 | cut -d. -f1)
        ;;
    esac
  done
  return 0
}

# ---------------------------------------------------------------------------
# XML Generation
# ---------------------------------------------------------------------------
fs_load_conf() {
  [ -f "$FS_MODDIR/config.sh" ] && . "$FS_MODDIR/config.sh"
  [ -f "$FS_CONF" ] && . "$FS_CONF"
  [ -n "$FS_ROLES" ]
}

fs_set_perm() {
  chown 0:0 "$1" 2>/dev/null
  chmod "$2" "$1" 2>/dev/null
  chcon u:object_r:system_file:s0 "$1" 2>/dev/null
}

# fs_gen_one SRC DST MODE SA
#   Return value  0=generated/not needed  1=failed(deleted DST)  3=Pending because SRC is already generated (mounted)
fs_gen_one() {
  _src=$1; _dst=$2; _mode=$3; _sa=$4
  if [ ! -f "$_src" ]; then rm -f "$_dst"; return 0; fi
  if grep -q "$FS_MARK" "$_src" 2>/dev/null; then return 3; fi
  mkdir -p "${_dst%/*}"
  _tmp="$_dst.tmp"; _rep="$FS_MODDIR/.report.tmp"
  rm -f "$_tmp" "$_rep"
  awk -v MODE="$_mode" -v SA="$_sa" -v ROLES="$FS_ROLES" \
      -v PAT_SANS="$SANS_FAMILIES" -v PAT_SERIF="$SERIF_FAMILIES" -v PAT_MONO="$MONO_FAMILIES" \
      -v FPAT_SANS="$SANS_FILES" -v FPAT_SERIF="$SERIF_FILES" -v FPAT_MONO="$MONO_FILES" \
      -v CJK="$CJK_LANGS" -v MARK="$FS_MARK" -v REPORT="$_rep" \
      -f "$FS_LIB/xmlgen.awk" "$_src" > "$_tmp"
  _rc=$?
  _ok=1
  [ $_rc -eq 0 ] && [ -s "$_tmp" ] || _ok=0
  grep -q "$FS_MARK" "$_tmp" 2>/dev/null || _ok=0
  for _t in familyset fonts-modification; do
    if grep -q "<$_t" "$_src"; then grep -q "</$_t>" "$_tmp" || _ok=0; fi
  done
  _o=$(grep -o '<family[ >]' "$_tmp" | wc -l); _c=$(grep -o '</family>' "$_tmp" | wc -l)
  _so=$(grep -o '<family[ >]' "$_src" | wc -l); _sc=$(grep -o '</family>' "$_src" | wc -l)
  [ $(( _o - _c )) -eq $(( _so - _sc )) ] || _ok=0
  if [ $_ok -ne 1 ]; then
    fs_log "ERROR: Failed to convert $_src (rc=$_rc). Cannot replace this XML."
    rm -f "$_tmp" "$_dst" "$_rep"
    return 1
  fi
  mv -f "$_tmp" "$_dst"
  fs_set_perm "$_dst" 0644
  fs_log "generated: $_src (mode=$_mode supportedAxes=$_sa)"
  if [ -f "$_rep" ]; then
    while IFS= read -r _l; do fs_log "    $_l"; done < "$_rep"
    rm -f "$_rep"
  fi
  return 0
}

fs_state_now() {
  {
    for _s in "$FS_SRC_MAIN" "$FS_SRC_FALLBACK" "$FS_SRC_CUSTOM"; do
      if [ -f "$_s" ]; then md5sum "$_s" 2>/dev/null; else echo "none $_s"; fi
    done
    md5sum "$FS_CONF" "$FS_MODDIR/config.sh" "$FS_LIB/xmlgen.awk" 2>/dev/null
    fs_api
  } | md5sum | cut -d' ' -f1
}

# Generate all XML (if needed). FORCE=1 to force regenerate.
fs_generate_all() {
  fs_load_conf || { fs_log "ERROR: typeface_magic.conf not found"; return 1; }
  _api=$(fs_api)
  _need=0
  [ "$FORCE" = 1 ] && _need=1
  [ -f "$FS_DST_MAIN" ] || _need=1
  [ -f "$FS_SRC_FALLBACK" ] && [ ! -f "$FS_DST_FALLBACK" ] && _need=1
  [ -f "$FS_SRC_CUSTOM" ] && [ ! -f "$FS_DST_CUSTOM" ] && _need=1
  if [ $_need -eq 0 ] && grep -q "$FS_MARK" "$FS_SRC_MAIN" 2>/dev/null; then
    # Already mounted, so Already using generated-version. Use as is.
    return 0
  fi
  _now=$(fs_state_now)
  [ $_need -eq 0 ] && [ "$(cat "$FS_STATE" 2>/dev/null)" = "$_now" ] && return 0

  _sa_new=0; [ "$_api" -ge 35 ] 2>/dev/null && _sa_new=1
  _pending=0
  fs_gen_one "$FS_SRC_MAIN" "$FS_DST_MAIN" main 0;              [ $? -eq 3 ] && _pending=1
  fs_gen_one "$FS_SRC_FALLBACK" "$FS_DST_FALLBACK" main 1;      [ $? -eq 3 ] && _pending=1
  fs_gen_one "$FS_SRC_CUSTOM" "$FS_DST_CUSTOM" custom $_sa_new; [ $? -eq 3 ] && _pending=1
  # If none to place to product, do not leave empty directory.
  rmdir "$FS_MODDIR/system/product/etc" "$FS_MODDIR/system/product" 2>/dev/null
  if [ $_pending -eq 0 ]; then echo "$_now" > "$FS_STATE"; else rm -f "$FS_STATE"; fi
  return 0
}
