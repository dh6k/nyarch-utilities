# nyarch-utilities

Small standalone utilities for Nyarch Linux (Arch-based, KDE Plasma).

## material-you-setup.sh

One-shot setup + self-maintaining Material You theming stack for KDE Plasma.

### What it does

1. Installs `kde-material-you-colors`, `adwaita-material-you` (AUR) and `inotify-tools` (repo) via paru/yay
2. Patches both tools for `materialyoucolor` v3 compatibility (3 spots, idempotent)
3. Sets up a wallpaper watcher: re-runs `adwmu` automatically when the Plasma wallpaper changes (systemd user service + inotify)
4. Installs itself to `/usr/local/bin` and drops a pacman hook that re-applies the patches after every relevant package update

### Usage

```bash
git clone https://github.com/dh6k/nyarch-utilities.git
cd nyarch-utilities
chmod +x material-you-setup.sh
./material-you-setup.sh [--scheme dark|light] [--variant V]  # full setup — run AS YOUR USER (no sudo)
# V: default | vibrant | expressive | "fruit salad" | muted
# (--variant chỉ là fallback; xem "Settings sync" bên dưới)
```

### Settings sync

The wallpaper hook doesn't just watch for wallpaper changes — it also watches
`~/.config/kde-material-you-colors/config.conf` and syncs the widget's
**Color scheme** selection to `adwmu`'s `-V` variant:

| Widget scheme | adwmu variant |
|---|---|
| Vibrant, Rainbow | `vibrant` |
| Expressive | `expressive` |
| FruitSalad | `fruit salad` |
| Monochrome | `muted` |
| Content, Fidelity, Neutral, TonalSpot | `default` |

So picking "Vibrant" in the widget (like in the screenshot) automatically
re-applies the GTK theme with `-V vibrant` — no manual flags needed.
`--variant` is only used as a fallback when the widget's config can't be read.

Patch-only mode (used by the pacman hook, or re-run manually after updates):

```bash
sudo ./material-you-setup.sh --patch-only
```

### Why the patches?

`kde-material-you-colors` and `adwaita-material-you` were written against the
`materialyoucolor` v2 API. v3 is a breaking rewrite:

| # | File | v2 → v3 change |
|---|------|----------------|
| 1 | `kde_material_you_colors/utils/extra_image_utils.py` | `ScoreOptions` dropped the `dislike_filter` kwarg |
| 2 | `kde_material_you_colors/utils/m3_scheme_utils.py` | `palette.tone(x)` now returns an ARGB int directly instead of an RGBA list |
| 3 | `adwmu` (`adwaita-material-you/main.py`) | `Scheme.dark(argb).props` values are ARGB ints now, not RGBA lists |

All patches are idempotent — if upstream ever fixes v3 support properly,
re-running the script is a safe no-op.

### Requirements

- Arch-based distro with KDE Plasma
- `paru` or `yay`
- `python-materialyoucolor3` (pulled in automatically as a dependency)

## install-gnome-terminal-shim.sh

`gnome-terminal` → `konsole` compatibility shim (+ auto-accept).

Nyarch Updater (flatpak `moe.nyarchlinux.updater`) hardcodes `gnome-terminal`
when spawning update commands via `flatpak-spawn --host`:

```
gnome-terminal -- bash -c "<updateCmd> ; echo Done - Press enter to exit; read _"
```

If you migrated GNOME → KDE and removed `gnome-terminal`, every update fails
with a generic "An error occurred during the update process".

This script installs `/usr/local/bin/gnome-terminal`, a shim that translates
the call to `konsole -e` and rewrites known update commands to auto-accept
prompts:

| Command | Rewritten to |
|---|---|
| `paru\|yay\|pikaur\|trizen -Sua` | append `--noconfirm` |
| `pacman -Syu` | append `--noconfirm` |
| `flatpak update` | append `-y` |

Anything else passes through untouched.

### Usage

```bash
chmod +x install-gnome-terminal-shim.sh
./install-gnome-terminal-shim.sh   # asks for sudo to write /usr/local/bin
```

### Notes

- `--noconfirm` on AUR helpers skips the PKGBUILD diff review — the main AUR
  safety net. Your machine, your call.
- The sudo password is still prompted as usual; this only auto-accepts Y/n prompts.
- Tip: Nyarch Updater's *system* update command doesn't need the shim — it's a
  GSettings key (`system-update-command`) editable right in the app's Settings UI.
  Set it to `sudo pacman -Syu --noconfirm` directly.

## install-misans.sh

Install MiSans (Xiaomi HyperOS font, downloaded from
https://hyperos.mi.com/font/en/download/) as the system-wide sans-serif
for every language, including CJK — and fix the common fallback trap
where Japanese / Simplified Chinese fall back to `AR PL New Sung`
(thin Song/Ming serif, hard to read at UI sizes) instead of a clean sans.

### What it does

1. Extracts every `.ttf`/`.otf` from the given MiSans zip(s) to
   `~/.local/share/fonts/MiSans` (per-user, no sudo needed for install)
2. Backs up an existing `~/.config/fontconfig/fonts.conf` with a
   timestamp, then writes a new one: MiSans VF first for `sans-serif`,
   static MiSans second, Noto kept behind it as fallback
3. Adds strong per-language prepends, VF first:
   `ja` -> MiSans VF + MiSans + Noto Sans CJK JP,
   `ko` -> MiSans VF + MiSans + Noto Sans CJK KR,
   `zh-cn` -> MiSans VF + MiSans + Noto Sans CJK SC,
   `zh-tw`/`zh-hk` -> MiSans TC VF + MiSans TC + Noto Sans CJK TC
4. Sets rendering in the same `fonts.conf`, verified on the
   author's 15.6" Nyarch laptop: anti-aliasing on,
   `hintstyle: hintslight`, `rgba: none`, `lcdfilter: lcdnone`
   (grayscale anti-aliasing, no subpixel)
5. Syncs the matching KDE Xft settings (`XftAntialias`,
   `XftHintStyle`, `XftSubPixel` in `kdeglobals`, via `kwriteconfig6`
   when available), rebuilds the font cache, and prints the first
   `fc-match` per language plus the rendering actually applied

### Usage

```bash
chmod +x install-misans.sh
./install-misans.sh ~/Downloads/MiSans.zip
# multiple zips at once, e.g. MiSans + MiSans TC:
./install-misans.sh ~/Downloads/MiSans.zip ~/Downloads/MiSans-TC.zip
```

Then restart apps that were already open (no reboot needed), and in
KDE set System Settings > Appearance > Fonts to MiSans VF so apps asking
for the UI font get it directly instead of only via fallback.

### Notes

- MiSans Global is split into separate files (MiSans, MiSans TC,
  MiSans L3, MiSans Latin, ...). MiSans Latin alone covers no CJK,
  so downloading only that file will not change CJK rendering.
- MiSans L3 covers only rare characters (GB 18030-2022 Level 3) and
  does not include the common Level 1+2 set — never put it first
  on its own.
- Japanese / Korean coverage of the downloaded file is not
  guaranteed. That is why Noto is kept as fallback: a glyph MiSans
  does not have falls through to Noto, not to tofu or AR PL New Sung.
- Check the result with `fc-match "sans-serif:lang=ja"`,
  `fc-match "sans-serif:lang=ko"`, `fc-match "sans-serif:lang=zh-cn"`.
- VF first: `MiSans VF` is the variable font for Simplified
  Chinese, `MiSans TC VF` for Traditional Chinese. Static MiSans /
  MiSans TC stay second in case a glyph is missing from the VF.
  Noto CJK variable-font packages share the same family names as
  the static ones, so they cannot be forced by name alone — if the
  VF package is installed instead of the static one, that VF will
  be used automatically under the same name. [Unverified on the
  author's machine: check with `fc-list | grep -i "CJK"` to see
  which families are actually installed there.]
- Rendering tuning: `rgba: rgb` + `hintmedium` was tried first
  and looked bad on the author's machine (colour fringing /
  uneven strokes at 11pt), and `hintmedium` + `rgba: none` still
  looked bad — `hintslight` + `rgba: none` is the combination that
  looks clean, so that is the default here. Do not "improve" it
  back to `rgb`/`medium` without re-testing on the real machine.
  Verify with `fc-match -v "sans-serif" | grep -E "rgba:|hintstyle:"`
  — it should show `hintstyle: 1` (= hintslight) and `rgba: 5` (= none).
  Do not tick KDE's "Exclude range from anti-aliasing"
  with the default 8-15pt range: UI fonts at 9-11pt sit inside it,
  so it would switch anti-aliasing off exactly for the UI.
