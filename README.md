# material-you-setup

One-shot setup + self-maintaining Material You theming stack for KDE Plasma (Arch-based).

## What it does

1. Installs `kde-material-you-colors`, `adwaita-material-you` (AUR) and `inotify-tools` (repo) via paru/yay
2. Patches both tools for `materialyoucolor` v3 compatibility (3 spots, idempotent)
3. Sets up a wallpaper watcher: re-runs `adwmu` automatically when the Plasma wallpaper changes (systemd user service + inotify)
4. Installs itself to `/usr/local/bin` and drops a pacman hook that re-applies the patches after every relevant package update

## Usage

```bash
git clone https://github.com/dh6k/material-you-setup.git
cd material-you-setup
chmod +x material-you-setup.sh
./material-you-setup.sh [--scheme dark|light] [--variant V]  # full setup — run AS YOUR USER (no sudo)
# V: default | vibrant | expressive | "fruit salad" | muted
# (--variant chỉ là fallback; xem "Settings sync" bên dưới)
```

## Settings sync

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

## Why the patches?

`kde-material-you-colors` and `adwaita-material-you` were written against the
`materialyoucolor` v2 API. v3 is a breaking rewrite:

| # | File | v2 → v3 change |
|---|------|----------------|
| 1 | `kde_material_you_colors/utils/extra_image_utils.py` | `ScoreOptions` dropped the `dislike_filter` kwarg |
| 2 | `kde_material_you_colors/utils/m3_scheme_utils.py` | `palette.tone(x)` now returns an ARGB int directly instead of an RGBA list |
| 3 | `adwaita-material-you/main.py` | `Scheme.dark(argb).props` values are ARGB ints now, not RGBA lists |

All patches are idempotent — if upstream ever fixes v3 support properly,
re-running the script is a safe no-op.

## Requirements

- Arch-based distro with KDE Plasma
- `paru` or `yay`
- `python-materialyoucolor3` (pulled in automatically as a dependency)
