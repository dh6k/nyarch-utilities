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

`gnome-terminal` → `konsole` / `kitty` compatibility shim (+ auto-accept).

Nyarch Updater (flatpak `moe.nyarchlinux.updater`) hardcodes `gnome-terminal`
when spawning update commands via `flatpak-spawn --host`:

```
gnome-terminal -- bash -c "<updateCmd> ; echo Done - Press enter to exit; read _"
```

If you migrated GNOME → KDE and removed `gnome-terminal`, every update fails
with a generic "An error occurred during the update process".

This script installs `/usr/local/bin/gnome-terminal`, a shim that translates
the call to the terminal you pick and rewrites known update commands to
auto-accept prompts:

| Command | Rewritten to |
|---|---|
| `paru\|yay\|pikaur\|trizen -Sua` | append `--noconfirm` |
| `pacman -Syu` | append `--noconfirm` |
| `flatpak update` | append `-y` |

Anything else passes through untouched.

### Usage

```bash
chmod +x install-gnome-terminal-shim.sh
./install-gnome-terminal-shim.sh                       # konsole + auto-accept (default, unchanged)
./install-gnome-terminal-shim.sh --terminal kitty     # kitty + auto-accept
./install-gnome-terminal-shim.sh --kitty --no-auto-accept  # kitty, plain pass-through
./install-gnome-terminal-shim.sh --dry-run --terminal kitty  # preview the shim, change nothing
./install-gnome-terminal-shim.sh --uninstall          # remove the shim
```

Options: `--terminal <kitty|konsole>` (also `--kitty` / `--konsole` shortcuts),
`--no-auto-accept` / `--auto-accept`, `--dry-run`, `--uninstall`, `-h` / `--help`.

### Notes

- kitty and konsole take the command differently, and the shim handles that:
  konsole needs `konsole -e <cmd>`, kitty takes the program directly
  (`kitty <cmd>`, no `-e` — `kitty [options] [program-to-run ...]`).
  Using `-e` with kitty would break the call.
- `--noconfirm` on AUR helpers skips the PKGBUILD diff review — the main AUR
  safety net. Your machine, your call.
- The sudo password is still prompted as usual; this only auto-accepts Y/n prompts.
- `--uninstall` only removes the file if it contains the shim marker, so it
  refuses to delete a real `gnome-terminal` if you reinstalled one later.
- Tip: Nyarch Updater's *system* update command doesn't need the shim — it's a
  GSettings key (`system-update-command`) editable right in the app's Settings UI.
  Set it to `sudo pacman -Syu --noconfirm` directly.
- Kitty variant verified on the VM only with stub terminals (argv translation
  + `--noconfirm`/`-y` rewrite pass for both kitty and konsole); not yet run
  against the real Nyarch Updater on a Nyarch machine.

## sync-pywal-kitty.sh

Sync pywal16 colors to kitty, in three steps:

1. `wal -i <wallpaper> -n` generates the palette into
   `~/.cache/wal/colors-kitty.conf` (`-n` = skip setting the wallpaper,
   Plasma owns it on Nyarch)
2. `~/.config/kitty/kitty.conf` gains, as its last line,
   `include ~/.cache/wal/colors-kitty.conf` — so new kitty windows open
   with the new colors
3. Running kitty windows get the colors live via
   `kitty @ set-colors --all --configured ~/.cache/wal/colors-kitty.conf`

"pywal" here is pywal16 (`python-pywal16` from the AUR, binary still `wal`);
the original `python-pywal` is dead and gone from the repos.

### Usage

```bash
chmod +x sync-pywal-kitty.sh
./sync-pywal-kitty.sh ~/Pictures/wallpaper.jpg
./sync-pywal-kitty.sh ~/Pictures/wallpaper.jpg --backend colorthief --light
./sync-pywal-kitty.sh ~/Pictures/wallpaper.jpg --opacity 0.85
./sync-pywal-kitty.sh --restore   # after reboot/login, re-apply the last scheme
./sync-pywal-kitty.sh --check     # report wal/kitty/include state, change nothing
./sync-pywal-kitty.sh --dry-run ~/Pictures/wallpaper.jpg
```

Options: `--backend <name>`, `--light`, `--saturate <0.0-1.0>`,
`--opacity <0.0-1.0>`, `--set-wallpaper` (let wal set the wallpaper too —
off by default), `--no-reload`, `--install-deps` (install `python-pywal16`
via paru/yay if `wal` is missing), `--enable-remote-control`, `--restore`,
`--check`, `--dry-run`, `-h` / `--help`.

### Notes

- Live reload only reaches kitty when the script runs **inside a kitty
  window**, when `KITTY_LISTEN_ON` is set, or when a listen socket exists.
  Otherwise running windows keep the old colors until Ctrl+Shift+F5
  (reload config) or a restart — new windows are fine either way, and the
  script says so instead of failing.
- Transparency is not part of the pywal palette: `wal` never emits it for
  kitty (its `-a` flag only works in URxvt). `--opacity <0.0-1.0>` manages
  it as a kitty setting instead — it sets `background_opacity` in
  `kitty.conf` (replacing the old value, never duplicating it) and enables
  `dynamic_background_opacity yes` so running windows can take the new
  value live via `kitty @ set-background-opacity --all <v>`. That live
  call only works if `dynamic_background_opacity` was already enabled
  when the running kitty started; otherwise the value still applies on
  the next Ctrl+Shift+F5 / new window. Without `--opacity` the script
  leaves any existing opacity alone.
- `--enable-remote-control` appends `allow_remote_control socket-only` +
  `listen_on unix:/tmp/kitty` to `kitty.conf`, so later runs from Konsole,
  a hook, or autostart can live-reload kitty too. It needs a kitty restart
  (`listen_on` is not reloadable), and it is opt-in on purpose: any local
  process that can reach the socket can then control kitty.
- The include is appended last on purpose: color settings above it are
  overridden by pywal, and the script never comments out your own colors.
  `kitty.conf` is backed up (timestamped `.bak.*`) before any edit, and
  re-running is idempotent — no duplicate lines.
- This is a different palette from the Material You stack
  (`material-you-setup.sh` / adwmu does GTK): pywal's 16 colors go to
  kitty only, adwmu keeps doing GTK. To auto-sync on wallpaper change,
  call this script with the new wallpaper from wherever the wallpaper
  changes (e.g. one line in the adwmu wallpaper hook — note that file is
  regenerated by `material-you-setup.sh`, so the line would need
  re-adding after re-running setup).
- Verified on the VM only, with stub `wal`/`kitty` binaries in a fake
  `$HOME` (generate, include idempotent, `--restore`, `--check`,
  `--dry-run` changing nothing, remote-control lines, missing-wallpaper
  and missing-`wal` errors all pass); not yet run with real pywal16 /
  kitty on a Nyarch machine.

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

## install-sddm-misans-font.fish

Sync the SDDM greeter (breeze theme, X11) to MiSans VF and to
125% scale, matching the KDE UI font and Plasma scale set by
`install-misans.sh`.

SDDM runs before login, so it does not read `~/.local/share/fonts`
or the user's `kdeglobals`. It only reads system-wide fonts and its
own config. This script therefore:

1. Copies MiSans fonts from `~/.local/share/fonts/MiSans` to
   `/usr/share/fonts/MiSans` (system-wide, so SDDM/root can see them)
2. Copies `~/.config/fontconfig/fonts.conf` to
   `/etc/fonts/local.conf` (system-wide rendering + VF-first prefer,
   backing up an existing file with a timestamp)
3. Rebuilds the font cache and verifies `MiSans VF` is visible
   system-wide with `fc-list`
4. Writes `/etc/sddm.conf.d/99-font.conf` with
   `[Theme] Font=MiSans VF` (a separate drop-in, sorted after
   `kde_settings.conf`, so KDE rewriting that file does not
   silently drop the font setting)
5. Writes `/etc/sddm.conf.d/99-hidpi.conf` with 125% scale for the
   X11 greeter:
   `[General] GreeterEnvironment=QT_AUTO_SCREEN_SCALE_FACTOR=0,QT_SCALE_FACTOR=1.25,QT_FONT_DPI=96`
   plus `[X11] ServerArguments=-nolisten tcp` and `EnableHiDPI=true`.
   Verified on the author's machine (2026-10-30): X `ServerArguments`
   with `-dpi 120` alone did NOT scale the Qt6 greeter (X still ran
   with `-dpi 120`, the greeter still looked 100%); the Qt scale
   factor above is what actually scaled it to 125%, and removing
   `-dpi 120` afterwards kept 125%, so this script does not use
   `-dpi 120` at all. Change `QT_SCALE_FACTOR` if the Plasma scale
   changes from 125%.

Requires `install-misans.sh` to have been run first with
`MiSans.zip`, so the per-user fonts and `fonts.conf` exist.

### Usage (fish)

```fish
fish install-sddm-misans-font.fish
# or, after chmod +x:
./install-sddm-misans-font.fish
```

The script does NOT restart SDDM (that would log out the current
session). Preview first, without logging out:

```bash
sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/breeze
```

Then logout or reboot to see the real greeter. Note: this syncs
the font family (MiSans VF), not the size — greeter font size
comes from the theme, not from KDE's 11pt UI font. Also note:
`--test-mode` runs inside the current session, so it does NOT
reflect the greeter's real scale; only a logout/reboot to the
real greeter verifies the 125% scale.

## install-doh.sh

System-wide DNS over HTTPS (DoH) for every app, not just the browser.

`systemd-resolved` does NOT support DoH natively (only DoT), so this
script wires it through `dnscrypt-proxy`:

```
apps -> systemd-resolved (127.0.0.53) -> dnscrypt-proxy (127.0.0.1:53)
     -> upstream DoH over https://<your-host>/dns-query (port 443)
```

### What it does

1. Installs `dnscrypt-proxy` via pacman
2. Turns the DoH URL you give into a DNS stamp (`sdns://...`) for
   dnscrypt-proxy's `[static]` section. The stamp generator is pure
   bash + `base64` (no python), and was verified against the published
   Cloudflare / Quad9 stamps. The stamp carries an empty `addr` on
   purpose: baking one IP at install time freezes it, and a stale /
   hijacked answer would break DoH afterwards. dnscrypt-proxy resolves
   the hostname at runtime through `bootstrap_resolvers`
   (8.8.8.8:53, 1.1.1.1:53, bootstrap only -- real queries still
   go over DoH). dnscrypt-proxy 2.1 renamed the old
   `fallback_resolver` key to `bootstrap_resolvers`; the old name
   is rejected with `[FATAL] Unsupported key` on 2.1.20
3. Writes `/etc/dnscrypt-proxy/dnscrypt-proxy.toml` (backing up the
   old one with a timestamp) with `listen_addresses = 127.0.0.1:53`,
   `doh_servers = true`, `require_dnssec = true`, and validates it
   with `dnscrypt-proxy -check` before starting anything
4. Writes `/etc/systemd/resolved.conf.d/dnscrypt-proxy.conf` with
   `DNS=127.0.0.1`, an intentionally empty `FallbackDNS` (fail closed
   instead of leaking plain DNS if the proxy is down), and
   `Domains=~.` so every domain routes through the proxy even when
   NetworkManager pushes per-link DNS
5. Starts `dnscrypt-proxy.service` (socket activation off -- the
   service binds 127.0.0.1:53 itself), restarts `systemd-resolved`,
   and verifies with `resolvectl query archlinux.org`. On a failed
   verification it restores the backups automatically

### Usage

```bash
chmod +x install-doh.sh
./install-doh.sh https://dns.cloudflare.com/dns-query
./install-doh.sh https://dns.nextdns.io/<your-id>   # NextDNS, no /dns-query suffix
./install-doh.sh cloudflare|quad9|google|adguard   # preset
./install-doh.sh                                    # prompt interactively
./install-doh.sh --dry-run <url-or-preset>          # print the generated config, change nothing
./install-doh.sh --check                            # verify the current setup
./install-doh.sh --uninstall                        # remove the drop-in, stop the proxy, restore DNS
```

### Notes

- DoH only hides the DNS query contents. It does NOT hide the
  destination IP / SNI of your connections; for that you need a VPN
  or Tor, not DoH.
- The stamp claims DNSSEC only (`props=1`). NoLog / NoFilter are
  not claimed for an arbitrary URL, since the provider's
  logging/filtering policy is unknown.
- This script does NOT touch Firefox / Helium DoH settings -- those
  are per-browser and independent. System DoH already covers the
  browser unless the browser is set to its own DoH resolver.
- `dnscrypt-proxy` is NOT tested on this VM (it is Arch-only tooling);
  run `--dry-run` first, then test on the real Nyarch machine with
  `./install-doh.sh --check` and `journalctl -u dnscrypt-proxy`
  (look for `OK (DoH)`).

## fix-zalo-aur.fish

Fix `zalo-for-linux-bin` failing to build with a 404 from GitHub.

### Root cause

Upstream (`VN-Linux-Family/zalo-for-linux`) replaces the release asset
under the same tag without a new release: the commit hash embedded in
the AppImage filename changes (e.g. `3c3b891` -> `d4452e1`), so the
`_commithash` pinned in the AUR PKGBUILD points at a URL that no
longer exists. This has happened repeatedly (first reported 2026-07-26
for 26.7.10, again 2026-11-09 for 26.11.10).

### What it does

1. Clones / updates the AUR repo into `~/build/zalo-for-linux-bin`
   (or `--dir <path>`)
2. Reads `pkgver` from the PKGBUILD and asks the GitHub API for that
   tag's current `ZaDark` x86_64 asset name — no hardcoded hash
3. Parses the new commit hash from the filename, updates
   `_commithash` in the PKGBUILD, and runs `updpkgsums` to regenerate
   the sha256 (downloads the ~155 MB AppImage)
4. Builds and installs with `makepkg -si` (skipped with `--no-build`)

Re-running it fixes the next replacement too, for as long as upstream
keeps replacing assets under the same tag.

### Usage (fish)

```fish
fish fix-zalo-aur.fish
fish fix-zalo-aur.fish --no-build   # only fix the PKGBUILD, don't install
fish fix-zalo-aur.fish --dir ~/build/zalo-for-linux-bin
```

Bash version, same logic, for machines without fish:
`fix-zalo-aur.sh` (`bash fix-zalo-aur.sh`, same `--no-build` /
`--dir` flags). Do NOT run the `.fish` file with bash — fish syntax
(`set -l`, `switch`, `or begin`) is not bash.

### Verified

- 2026-11-09 01:54 +07: tag `26.11.10` -> hash `3680a0e`,
  sha256 x86_64 `1c5d02c22c83ea6d9684857da8683bc4154de911f1337e5ac0d06c874a4f23b9`
- 2026-11-09 01:47 +07: same tag was `d4452e1`,
  sha256 `35c6e37adfdb96546cd0e003d644950945e1d880425c13cb09f8f23e42244d30`
  — superseded within ~7 minutes. That is why the scripts fetch the
  hash live instead of hardcoding it; any hash/sha256 written here
  is a snapshot only.
- The fix is local only: the AUR PKGBUILD still needs its maintainer
  to bump `_commithash` + `pkgrel`, or upstream to stop replacing
  assets under the same tag. Flag the AUR package out-of-date if it
  404s again.

## set-fastfetch-logo.fish

Point fastfetch's logo at an image without losing the image later.

### Root cause

Pointing `logo.source` straight at `~/Downloads` or `/tmp` works
until the next cleanup / reboot, and then fastfetch loses its logo.
An image kept inside a git checkout is no safer: another checkout,
`git clean`, or a new machine drops it just as easily.

### What it does

1. Copies the image you give it to one fixed, rarely-cleaned place:
   `~/.local/share/fastfetch/<original filename>`
   (XDG data dir — survives config edits, cache cleanups, and
   wallpaper changes)
2. Sets `"logo": { "source": ... }` in
   `~/.config/fastfetch/config.jsonc` to that copied file, editing
   only the `source` value and keeping the rest of the file —
   comments and formatting included (the edit is done with python3,
   which is only used as a JSONC-aware text editor here)

Safety:

- The old destination image and the old config are both backed up
  as `.bak.<timestamp>` before being overwritten
- Re-running with the same image is a no-op (no extra backups)
- `--dry-run` prints what would happen and touches nothing
- After editing, the config is re-validated as JSONC; on failure the
  backup is restored and the script exits with an error
- `--restore` puts the config back from its newest backup
- It never creates a fresh `config.jsonc` from scratch: a file with
  only a logo would silently replace fastfetch's default modules.
  If there is no config yet, run `fastfetch --gen-config` first
- It deliberately does not touch `logo.type` — if the image does not
  show, check whether the terminal supports kitty/sixel first

### Usage (fish)

```fish
fish set-fastfetch-logo.fish ~/Downloads/duyako-avatar-4-flat-transparent.png
fish set-fastfetch-logo.fish ~/Pictures/logo.png --name duyako.png
fish set-fastfetch-logo.fish ~/Pictures/logo.png --dry-run
fish set-fastfetch-logo.fish --restore
```

Then run `fastfetch` to check the logo shows up.

### Verified

- 2026-11-10 (VM, simulated `config.jsonc` only — not yet run on a
  real Nyarch machine): existing `source` replaced, `logo` without
  `source` gained one, config without `logo` gained a `logo` block,
  re-run is a no-op, `--dry-run` writes nothing, overwriting a
  different destination image backs it up, `--restore` restores the
  config, missing config / non-image file / `logo` as a string all
  exit with an error instead of mangling the config.
