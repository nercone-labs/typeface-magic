# shellcheck shell=ash

FS_MARK="typeface-magic: generated file"
FS_PREFIX="TypeFaceMagic"
FS_LIB="$FS_MODDIR/common"
FS_CONF="$FS_MODDIR/typeface_magic.conf"
FS_STATE="$FS_MODDIR/.state"
FS_LOG="$FS_MODDIR/typeface_magic.log"
FS_COMPONENTS="$FS_MODDIR/.components"

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

fs_unescape() {
  # shellcheck disable=SC2059
  while IFS= read -r _l; do printf "$_l"; done
}

# fs_table FILE TAG
#   Print "offset length" of the table TAG.
fs_table() {
  # shellcheck disable=SC2046
  set -- "$1" "$2" $(fs_bytes "$1" 4 2)
  [ $# -eq 4 ] || return 1
  fs_bytes "$1" 12 $(( ($3 * 256 + $4) * 16 )) | awk -v TAG="$2" '
    BEGIN { for (i = 32; i < 127; i++) ORD[sprintf("%c", i)] = i }
    function u32(i) { return (($i * 256 + $(i+1)) * 256 + $(i+2)) * 256 + $(i+3) }
    { for (i = 1; i + 15 <= NF; i += 16)
        if ($i == ORD[substr(TAG, 1, 1)] && $(i+1) == ORD[substr(TAG, 2, 1)] &&
            $(i+2) == ORD[substr(TAG, 3, 1)] && $(i+3) == ORD[substr(TAG, 4, 1)]) {
          printf "%d %d", u32(i+8), u32(i+12); exit
        }
    }'
}

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
  _fv=$(fs_table "$_f" fvar | cut -d' ' -f1)
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

# fs_rename FILE FAMILY
#   Rewrite the family names (name IDs 1, 4, 16, 21) of FILE to FAMILY.
fs_rename() {
  _rf=$1; _rn=$2
  # shellcheck disable=SC2046
  set -- $(fs_table "$_rf" name)
  [ $# -eq 2 ] || return 1
  # shellcheck disable=SC2046
  set -- "$1" "$2" $(fs_bytes "$_rf" 4 2)
  [ $# -eq 4 ] || return 1
  _rd=$(( 12 + ($3 * 256 + $4) * 16 ))
  _rs=$(wc -c < "$_rf")
  _rm=$( { fs_bytes "$_rf" 0 "$_rd"; echo; fs_bytes "$_rf" "$1" "$2"; echo; } | \
    awk -v NAME="$_rn" -v DIR_OUT="$_rf.dir" -v NAME_OUT="$_rf.name" -f "$FS_LIB/namegen.awk")
  _rc=$?
  # shellcheck disable=SC2086
  set -- $_rm
  if [ $_rc -ne 0 ] || [ $# -ne 5 ]; then
    fs_log "ERROR: Cannot rename ${_rf##*/}: $_rm"
    rm -f "$_rf.dir" "$_rf.name"
    return 1
  fi
  {
    fs_unescape < "$_rf.dir"
    [ "$1" -gt "$_rd" ] && tail -c +$(( _rd + 1 )) "$_rf" | head -c $(( $1 - _rd ))
    fs_unescape < "$_rf.name"
    tail -c +$(( $2 + 1 )) "$_rf"
  } > "$_rf.tmp"
  _rc=$?
  if [ $_rc -eq 0 ] && [ "$3" -ge 0 ]; then
    # shellcheck disable=SC2059
    printf "$5" | dd of="$_rf.tmp" bs=1 seek=$(( $3 + 8 )) count=4 conv=notrunc 2>/dev/null
    _rc=$?
  fi
  rm -f "$_rf.dir" "$_rf.name"
  [ "$_rs" -lt "$2" ] && _rs=$2
  if [ $_rc -ne 0 ] || [ "$(wc -c < "$_rf.tmp")" -ne $(( _rs + $4 )) ]; then rm -f "$_rf.tmp"; return 1; fi
  mv -f "$_rf.tmp" "$_rf"
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

# ---------------------------------------------------------------------------
# Component Control
# ---------------------------------------------------------------------------
fs_wait_boot() {
  until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
}

# fs_component_state USER COMPONENT
#   Print the enabled state of COMPONENT for USER: "default", "enabled" or "disabled".
fs_component_state() {
  _p=${2%%/*}; _n=${2#*/}
  case "$_n" in .*) _n="$_p$_n" ;; esac
  dumpsys package "$_p" 2>/dev/null | awk -v U="$1" -v N="$_n" '
    function indent() { return match($0, /[^ ]/) - 1 }
    /^ *User [0-9]+: / { u = ($2 == U ":"); m = ""; next }
    !u { next }
    m != "" && indent() <= h { m = "" }
    /^ *(disabled|enabled)Components:$/ { m = $1; sub(/Components:$/, "", m); h = indent(); next }
    m != "" { s = $0; gsub(/ /, "", s); if (s == N) { r = m; exit } }
    END { print (r == "" ? "default" : r) }'
}

# fs_components LIST RECORD
#   Disable the components in LIST for every user, and restore the components in RECORD
#   (lines of "USER COMPONENT STATE" disabled by this module) that are no longer in LIST to their former STATE.
#   Components already disabled by others are left alone. Print the new RECORD.
fs_components() {
  _users=$(pm list users 2>/dev/null | sed -n 's/.*UserInfo{\([0-9][0-9]*\):.*/\1/p' | tr '\n' ' ')
  if [ -z "$_users" ]; then
    fs_log "ERROR: Cannot list users. Components are left unchanged."
    [ -n "$2" ] && printf '%s\n' "$2"
    return 1
  fi
  {
    printf '%s\n' "$2" | while read -r _u _c _s; do
      [ -n "$_s" ] || continue
      case " $_users " in *" $_u "*) ;; *) continue ;; esac
      case " $1 " in *" $_c "*) continue ;; esac
      case "$_s" in enabled) _a=enable ;; *) _a=default-state ;; esac
      if pm "$_a" --user "$_u" "$_c" >/dev/null 2>&1; then
        fs_log "restored: $_c (user $_u, $_s)"
      else
        fs_log "ERROR: Cannot restore $_c (user $_u, $_s)"
        echo "$_u $_c $_s"
      fi
    done
    for _u in $_users; do
      for _c in $1; do
        _s=$(printf '%s\n' "$2" | awk -v U="$_u" -v C="$_c" '$1 == U && $2 == C { print $3; exit }')
        _was=$_s
        if [ -z "$_was" ]; then
          _s=$(fs_component_state "$_u" "$_c")
          if [ "$_s" = disabled ]; then
            fs_log "skipped: $_c (user $_u) is already disabled"
            continue
          fi
        fi
        if pm disable --user "$_u" "$_c" >/dev/null 2>&1; then
          [ -n "$_was" ] || fs_log "disabled: $_c (user $_u, $_s)"
        else
          fs_log "WARN: Cannot disable $_c (user $_u)"
          [ -n "$_was" ] || continue
        fi
        echo "$_u $_c $_s"
      done
    done
  } | sort -u
}

# fs_apply_components LIST
#   Run fs_components with the record of this module and save the new record.
fs_apply_components() {
  _r=$(fs_components "$1" "$(cat "$FS_COMPONENTS" 2>/dev/null)")
  if [ -z "$_r" ]; then rm -f "$FS_COMPONENTS"; return 0; fi
  echo "$_r" > "$FS_COMPONENTS.tmp" && mv -f "$FS_COMPONENTS.tmp" "$FS_COMPONENTS"
}
