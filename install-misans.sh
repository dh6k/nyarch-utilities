#!/usr/bin/env bash
# Install MiSans (downloaded from hyperos.mi.com/font) on Nyarch / Arch
# and make it the first choice for every language, with Noto kept as
# fallback behind it -- NOT deleted.
#
# Why Noto stays: the official MiSans Global family is split into
# separate files (MiSans, MiSans TC, MiSans L3, MiSans Latin, ...).
# MiSans Latin alone covers no CJK, and MiSans L3 covers ONLY rare
# characters (it does not include the common L1+L2 set), so neither
# can be put first on its own. Japanese / Korean coverage of the
# downloaded file is also not guaranteed -- if a glyph is missing
# from MiSans, fontconfig falls through to Noto instead of tofu
# or AR PL New Sung.
#
# Rendering defaults (verified on the author's 15.6" Nyarch laptop):
# antialias on, hintstyle hintslight, subpixel rgba none,
# lcdfilter lcdnone (grayscale anti-aliasing, no subpixel).
# NOTE: rgba rgb + hintmedium was tried first and looked bad on
# this machine (colour fringing / uneven strokes at 11pt), and
# hintmedium + rgba none still looked bad. hintslight + rgba none
# is the combination that looks clean. Do not "improve" this back
# to rgb/medium without re-testing on the real machine.
#
# Usage:
#   1. Download the MiSans zip(s) in a browser from
#      https://hyperos.mi.com/font/en/download/ (accept the licence).
#   2. chmod +x install-misans.sh
#      ./install-misans.sh ~/Downloads/MiSans*.zip
#   You may pass several zips at once (e.g. MiSans + MiSans TC).
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <MiSans zip> [more zips...]" >&2
    echo "Example: $0 ~/Downloads/MiSans*.zip" >&2
    exit 1
fi
command -v unzip >/dev/null 2>&1 || { echo "Missing unzip. Install it first: sudo pacman -S unzip" >&2; exit 1; }
command -v fc-cache >/dev/null 2>&1 || { echo "Missing fontconfig (fc-cache)." >&2; exit 1; }

TARGET="$HOME/.local/share/fonts/MiSans"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TARGET"

echo "== 1. Extract fonts =="
FOUND=0
for zip in "$@"; do
    [ -f "$zip" ] || { echo "Not found: $zip" >&2; exit 1; }
    echo "Unzipping: $zip"
    unzip -o -q "$zip" -d "$TMP"
done
# Copy every .ttf/.otf found at any depth in the zip(s).
while IFS= read -r -d '' f; do
    cp "$f" "$TARGET/"
    FOUND=$((FOUND + 1))
done < <(find "$TMP" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -print0)
if [ "$FOUND" -eq 0 ]; then
    echo "ERROR: no .ttf/.otf found in the given zip(s)." >&2
    exit 1
fi
echo "Installed $FOUND font file(s) to: $TARGET"
ls "$TARGET"

echo
echo "== 2. Write fontconfig (MiSans first, Noto as fallback) =="
FONT_CONF="$HOME/.config/fontconfig/fonts.conf"
mkdir -p "$HOME/.config/fontconfig"
if [ -f "$FONT_CONF" ]; then
    BACKUP="$FONT_CONF.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$FONT_CONF" "$BACKUP"
    echo "Backed up previous fonts.conf to: $BACKUP"
fi

cat > "$FONT_CONF" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- MiSans first for everything. Both spellings are listed because
       the downloaded family may be named "MiSans" or "MiSans VF";
       fontconfig silently ignores names that are not installed. -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>MiSans</family>
      <family>MiSans VF</family>
      <family>Noto Sans</family>
      <family>Noto Sans CJK JP</family>
      <family>Noto Sans CJK KR</family>
      <family>Noto Sans CJK SC</family>
      <family>Noto Sans CJK TC</family>
    </prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>Noto Serif CJK JP</family>
      <family>Noto Serif CJK KR</family>
      <family>Noto Serif CJK SC</family>
    </prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>Noto Sans Mono CJK JP</family>
      <family>Noto Sans Mono CJK KR</family>
      <family>Noto Sans Mono CJK SC</family>
    </prefer>
  </alias>

  <!-- Per-language strong prepends. Noto stays second in each list,
       so a glyph MiSans does not have falls back to Noto, not to
       AR PL New Sung. -->
  <match target="pattern">
    <test qual="any" name="family"><string>sans-serif</string></test>
    <test qual="any" name="lang" compare="contains"><string>ja</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>MiSans</string></edit>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK JP</string></edit>
  </match>
  <match target="pattern">
    <test qual="any" name="family"><string>sans-serif</string></test>
    <test qual="any" name="lang" compare="contains"><string>ko</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>MiSans</string></edit>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK KR</string></edit>
  </match>
  <match target="pattern">
    <test qual="any" name="family"><string>sans-serif</string></test>
    <test qual="any" name="lang" compare="contains"><string>zh-cn</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>MiSans</string></edit>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK SC</string></edit>
  </match>
  <match target="pattern">
    <test qual="any" name="family"><string>sans-serif</string></test>
    <test qual="any" name="lang" compare="contains"><string>zh-tw</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>MiSans TC</string></edit>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK TC</string></edit>
  </match>
  <match target="pattern">
    <test qual="any" name="family"><string>sans-serif</string></test>
    <test qual="any" name="lang" compare="contains"><string>zh-hk</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>MiSans TC</string></edit>
    <edit name="family" mode="prepend" binding="strong"><string>Noto Sans CJK TC</string></edit>
  </match>

  <!-- Rendering verified on the author's 15.6" Nyarch laptop:
       grayscale anti-aliasing, no subpixel. Do NOT tick KDE's
       "Exclude range from anti-aliasing" with the default 8-15pt
       range: UI fonts at 9-11pt sit inside it, so it would switch
       anti-aliasing off exactly for the UI. -->
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>none</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcdnone</const></edit>
  </match>
</fontconfig>
EOF
echo "Wrote: $FONT_CONF"

echo
echo "== 3. Rebuild cache and verify =="
fc-cache -fv >/dev/null
echo "--- Installed MiSans families ---"
fc-list | grep -i "MiSans" | sed 's/:.*style.*//' | sort -u || echo "(none found -- check the zip contents)"
echo "--- First match per language ---"
for lang in ja ko zh-cn zh-tw; do
    printf '%-6s -> ' "$lang"
    fc-match "sans-serif:lang=$lang"
done
echo "--- Does MiSans itself claim ja/ko? (empty = falls back to Noto, expected) ---"
echo "ja: $(fc-list :lang=ja | grep -i MiSans | head -1 || true)"
echo "ko: $(fc-list :lang=ko | grep -i MiSans | head -1 || true)"

echo
echo "== 4. Sync KDE Xft settings (so System Settings matches fontconfig) =="
if command -v kwriteconfig6 >/dev/null 2>&1; then
    kwriteconfig6 --file kdeglobals --group General --key XftAntialias true
    kwriteconfig6 --file kdeglobals --group General --key XftHintStyle hintslight
    kwriteconfig6 --file kdeglobals --group General --key XftSubPixel none
    echo "KDE Xft: antialias=true, hintstyle=hintslight, subpixel=none"
else
    echo "kwriteconfig6 not found, skipping KDE sync (fontconfig above still applies)."
fi
echo "--- Rendering actually applied ---"
fc-match -v "sans-serif" | grep -E "antialias:|hintstyle:|rgba:|lcdfilter:" || true
echo "(Subpixel is off here on purpose: rgb/medium looked bad on"
echo " the author's machine. See the header comment.)"

echo
echo "Done. Restart open apps to see it. No reboot needed."
echo "Then in KDE: System Settings > Appearance > Fonts > set the"
echo "interface font to MiSans, so apps asking for the UI font get it"
echo "directly instead of only via fallback."
echo "KDE apps already running may need a logout/login to pick up"
echo "the new Xft settings."
