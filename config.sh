# shellcheck shell=ash
# ============================================================================
#  TypeFace Magic Configuration File
#  To apply changes, reinstall the module and reboot.
#  (Changes are detected at boot, and the font customization XML is regenerated.)
# ============================================================================

# Font families to replace
#   sans-serif            … System Default Font (Roboto)
#   sans-serif-condensed  … Roboto Condensed
#   roboto-flex           … Roboto Flex, explicitly specified by some UI elements (such as the Clock app)
#   google-sans*          … Google Sans fonts defined in Pixel's /product/etc/fonts_customization.xml
SANS_FAMILIES="sans-serif sans-serif-condensed roboto-flex google-sans google-sans-*"
SERIF_FAMILIES="serif"
MONO_FAMILIES="monospace serif-monospace"

# Even if they do not match the names above, "named" families referencing the following font files will be replaced.
# (Countermeasure for Pixel / OEM devices that define Google Sans or Roboto under custom names. Do not include extensions.)
# Judgment order: Name -> MONO_FILES -> SERIF_FILES -> SANS_FILES
SANS_FILES="Roboto-* RobotoStatic-* RobotoFlex-* GoogleSans*"
SERIF_FILES="NotoSerif NotoSerif-*"
MONO_FILES="DroidSansMono CutiveMono RobotoMono* GoogleSansMono* GoogleSansCode*"

# Insert the bundled font family immediately before the CJK fallback family for the specified languages.
# (Effective when displaying Japanese with typefaces that are not replaced, such as casual / cursive.)
# Example: CJK_LANGS="ja ko zh-Hans zh-Hant"
CJK_LANGS="ja"

# Fixed values for variable axes other than wght/ital (comma-separated, e.g. "opsz=14,GRAD=0").
# If empty, the font's default values are used.
SANS_AXES=""
SERIF_AXES=""
MONO_AXES=""

# If this many consecutive boots fail to reach sys.boot_completed,
# the generated XML is removed and the module is automatically disabled. Set 0 to disable this guard.
BOOTLOOP_GUARD=3
