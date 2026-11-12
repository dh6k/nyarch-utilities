#!/bin/bash
#
# sync-pywal-kitty.sh — sync pywal16 colors to kitty
#
# Mechanism (3 pieces, each does one job):
#   1. `wal` generates the palette from a wallpaper into
#      ~/.cache/wal/colors-kitty.conf (pywal16 wiki: kitty reads its colors
#      from that file). Run with `-n` by default: Plasma owns the wallpaper,
#      wal must not try to set it with feh/nitrogen.
#   2. kitty.conf gains one line, appended LAST so it wins over any color
#      settings above it:
#        include ~/.cache/wal/colors-kitty.conf
#      New kitty windows pick the colors up from the include.
#   3. Running kitty windows get the new colors live via remote control:
#        kitty @ set-colors --all --configured ~/.cache/wal/colors-kitty.conf
#      That only reaches kitty when the script runs inside a kitty window
#      (messages go to the controlling terminal), when KITTY_LISTEN_ON is
#      set, or when a listen socket exists (see --enable-remote-control).
#      If none of those applies, running windows keep the old colors until
#      Ctrl+Shift+F5 (reload config) or a restart — new windows are fine.
#
# pywal here means pywal16 (eylles/pywal16), the maintained fork. The
# original dylanaraps/pywal is archived; on Arch the package is
# `python-pywal16` (AUR), binary still `wal`. The old `python-pywal` is
# gone from the repos.
#
# No sudo needed. Run as your user.
#
set -u

KITTY_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
WAL_CACHE="$HOME/.cache/wal"
COLORS_KITTY="$WAL_CACHE/colors-kitty.conf"
INCLUDE_LINE='include ~/.cache/wal/colors-kitty.conf'
SOCKET="/tmp/kitty"

WALLPAPER=""
BACKEND=""
LIGHT=0
SATURATE=""
SET_WALLPAPER=0
NO_RELOAD=0
DRY_RUN=0
CHECK=0
RESTORE=0
INSTALL_DEPS=0
ENABLE_RC=0

log()  { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 [WALLPAPER] [OPTIONS]
       $0 --restore
       $0 --check

WALLPAPER is an image file (or a directory — wal picks one at random).
With no wallpaper, restores the last cached scheme (same as --restore).

Options:
  --backend <name>        Pass --backend to wal (list with: wal --backend)
  --light                 Light colorscheme (wal -l)
  --saturate <0.0-1.0>    Pass --saturate to wal
  --set-wallpaper         Let wal set the wallpaper too (default: -n, skip it;
                          Plasma owns the wallpaper on Nyarch)
  --no-reload             Skip the live kitty @ set-colors reload attempt
  --enable-remote-control Append allow_remote_control socket-only +
                          listen_on unix:/tmp/kitty to kitty.conf, so later
                          runs from outside kitty (Konsole, hook, autostart)
                          can live-reload it. Needs a kitty restart to take
                          effect. Opt-in: any local process that can reach
                          the socket can then control kitty.
  --install-deps          Install python-pywal16 via paru/yay if wal is missing
  --restore               Re-apply the last cached scheme (wal -R)
  --check                 Report wal/kitty/include state, change nothing
  --dry-run               Print what would run, change nothing
  -h, --help              Show this help

Examples:
  $0 ~/Pictures/wallpaper.jpg
  $0 ~/Pictures/wallpaper.jpg --backend colorthief --light
  $0 --restore        # after reboot / login, re-apply last scheme
  $0 --check
EOF
}

detect_helper() {
    if command -v paru >/dev/null 2>&1; then echo paru;
    elif command -v yay >/dev/null 2>&1; then echo yay;
    else echo ""; fi
}

ensure_wal() {
    if command -v wal >/dev/null 2>&1; then return 0; fi
    if [[ "$INSTALL_DEPS" == "1" ]]; then
        local helper
        helper="$(detect_helper)"
        [[ -n "$helper" ]] || die "no paru/yay found — install python-pywal16 from the AUR manually: https://aur.archlinux.org/packages/python-pywal16"
        log "installing python-pywal16 via $helper..."
        "$helper" -S --needed --noconfirm python-pywal16 || die "failed to install python-pywal16"
        command -v wal >/dev/null 2>&1 || die "wal still not found after install"
        return 0
    fi
    die "wal not found. Install pywal16 first: paru/yay -S python-pywal16 (AUR), or re-run with --install-deps"
}

# Append a line to kitty.conf if not already there (exact match, ignoring
# surrounding whitespace). Backs the file up first, only when modifying.
# $2 is an optional trailing note for the comment above the appended line.
ensure_kitty_conf_line() {
    local line="$1"
    local note="${2:-}"
    mkdir -p "$(dirname "$KITTY_CONF")"
    if [[ ! -f "$KITTY_CONF" ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
            log "[dry-run] would create $KITTY_CONF with: $line"
            return 0
        fi
        printf '%s\n' "# created by sync-pywal-kitty.sh" "$line" > "$KITTY_CONF"
        log "created $KITTY_CONF"
        return 0
    fi
    if grep -qxF "$line" "$KITTY_CONF" 2>/dev/null; then
        return 0
    fi
    # Same line with different leading whitespace — treat as present, don't duplicate.
    if grep -qF "$line" "$KITTY_CONF" 2>/dev/null; then
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log "[dry-run] would append to $KITTY_CONF: $line"
        return 0
    fi
    local bak="$KITTY_CONF.bak.$(date +%Y%m%d-%H%M%S-%N)"
    cp "$KITTY_CONF" "$bak"
    if [[ -n "$note" ]]; then
        printf '%s\n' "" "# added by sync-pywal-kitty.sh — $note" "$line" >> "$KITTY_CONF"
    else
        printf '%s\n' "" "# added by sync-pywal-kitty.sh" "$line" >> "$KITTY_CONF"
    fi
    log "appended to $KITTY_CONF (backup: $bak)"
}

# Try to push the new colors into running kitty windows. Returns 0 on
# success, 1 when no live instance was reachable (not an error: new
# windows still get the colors via the include).
reload_kitty() {
    command -v kitty >/dev/null 2>&1 || { warn "kitty not found — skipping live reload (new windows still get colors via the include)."; return 1; }
    if kitty @ set-colors --all --configured "$COLORS_KITTY" 2>/dev/null; then
        log "live-reloaded all kitty windows (kitty @ set-colors --all --configured)"
        return 0
    fi
    if [[ -S "$SOCKET" ]] && kitty @ --to "unix:$SOCKET" set-colors --all --configured "$COLORS_KITTY" 2>/dev/null; then
        log "live-reloaded all kitty windows via unix:$SOCKET"
        return 0
    fi
    return 1
}

do_check() {
    log "wal: $(command -v wal || echo 'NOT FOUND (paru/yay -S python-pywal16)')"
    log "kitty: $(command -v kitty || echo 'NOT FOUND')"
    if [[ -f "$COLORS_KITTY" ]]; then
        log "colors: $COLORS_KITTY exists"
        grep -E '^(foreground|background|color0|color1) ' "$COLORS_KITTY" | head -4 | sed 's/^/  /'
    else
        log "colors: $COLORS_KITTY missing — run with a wallpaper first"
    fi
    if [[ -f "$KITTY_CONF" ]]; then
        if grep -qxF "$INCLUDE_LINE" "$KITTY_CONF" 2>/dev/null; then
            log "include: present in $KITTY_CONF"
        else
            log "include: MISSING from $KITTY_CONF (will be appended on next sync)"
        fi
        grep -q '^allow_remote_control' "$KITTY_CONF" 2>/dev/null && grep '^allow_remote_control' "$KITTY_CONF" | sed 's/^/  remote-control: /'
        grep -q '^listen_on' "$KITTY_CONF" 2>/dev/null && grep '^listen_on' "$KITTY_CONF" | sed 's/^/  listen_on: /'
    else
        log "kitty.conf: missing (will be created on next sync)"
    fi
    if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
        log "reload: running inside kitty (KITTY_WINDOW_ID=$KITTY_WINDOW_ID) — live reload should work"
    elif [[ -n "${KITTY_LISTEN_ON:-}" ]]; then
        log "reload: KITTY_LISTEN_ON=$KITTY_LISTEN_ON — live reload should work"
    elif [[ -S "$SOCKET" ]]; then
        log "reload: socket $SOCKET exists — live reload should work"
    else
        log "reload: no live kitty reachable from here — run inside kitty, or --enable-remote-control + restart kitty"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backend)
            [[ $# -ge 2 ]] || die "--backend needs a value"
            BACKEND="$2"; shift 2 ;;
        --backend=*) BACKEND="${1#--backend=}"; shift ;;
        --light) LIGHT=1; shift ;;
        --saturate)
            [[ $# -ge 2 ]] || die "--saturate needs a value"
            SATURATE="$2"; shift 2 ;;
        --saturate=*) SATURATE="${1#--saturate=}"; shift ;;
        --set-wallpaper) SET_WALLPAPER=1; shift ;;
        --no-reload) NO_RELOAD=1; shift ;;
        --enable-remote-control) ENABLE_RC=1; shift ;;
        --install-deps) INSTALL_DEPS=1; shift ;;
        --restore) RESTORE=1; shift ;;
        --check) CHECK=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*)
            die "unknown option: $1 (see --help)" ;;
        *)
            [[ -z "$WALLPAPER" ]] || die "only one wallpaper argument allowed, got: $WALLPAPER and $1"
            WALLPAPER="$1"; shift ;;
    esac
done

if [[ "$CHECK" == "1" ]]; then
    do_check
    exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
    [[ -n "$WALLPAPER" || "$RESTORE" == "1" ]] || log "[dry-run] no wallpaper given: would run wal -R (restore last scheme)"
    [[ -n "$WALLPAPER" ]] && log "[dry-run] would run: wal -i $WALLPAPER -n"
    [[ "$RESTORE" == "1" ]] && log "[dry-run] would run: wal -R"
    log "[dry-run] would ensure $KITTY_CONF contains: $INCLUDE_LINE"
    [[ "$ENABLE_RC" == "1" ]] && log "[dry-run] would ensure $KITTY_CONF contains: allow_remote_control socket-only + listen_on unix:/tmp/kitty"
    [[ "$NO_RELOAD" == "0" ]] && log "[dry-run] would try: kitty @ set-colors --all --configured $COLORS_KITTY"
    exit 0
fi

ensure_wal

if [[ "$ENABLE_RC" == "1" ]]; then
    ensure_kitty_conf_line "allow_remote_control socket-only"
    ensure_kitty_conf_line "listen_on unix:/tmp/kitty"
    log "remote control enabled in kitty.conf — restart kitty for listen_on to take effect (it is not reloadable)"
fi

if [[ -n "$WALLPAPER" ]]; then
    [[ -e "$WALLPAPER" ]] || die "wallpaper not found: $WALLPAPER"
    [[ "$RESTORE" == "1" ]] && warn "both a wallpaper and --restore were given — the wallpaper wins"
    wal_args=(-i "$WALLPAPER")
    [[ "$SET_WALLPAPER" == "0" ]] && wal_args+=(-n)
    [[ -n "$BACKEND" ]] && wal_args+=(--backend "$BACKEND")
    [[ "$LIGHT" == "1" ]] && wal_args+=(-l)
    [[ -n "$SATURATE" ]] && wal_args+=(--saturate "$SATURATE")
    log "generating palette: wal ${wal_args[*]}"
    wal "${wal_args[@]}" || die "wal failed"
elif [[ "$RESTORE" == "1" ]] || [[ -z "$WALLPAPER" ]]; then
    [[ -f "$WAL_CACHE/colors.json" ]] || die "nothing to restore: $WAL_CACHE/colors.json missing — run with a wallpaper first"
    log "restoring last scheme: wal -R"
    wal -R || die "wal -R failed"
fi

[[ -f "$COLORS_KITTY" ]] || die "wal ran but $COLORS_KITTY was not created — check that this is pywal16 (python-pywal16), not another wal"

ensure_kitty_conf_line "$INCLUDE_LINE" "keep last so it wins over colors above"

if [[ "$NO_RELOAD" == "0" ]]; then
    if ! reload_kitty; then
        warn "no live kitty reachable — running windows keep old colors until Ctrl+Shift+F5 or restart; new windows get the new colors via the include."
        warn "to make outside-kitty reloads work, run with --enable-remote-control once, then restart kitty."
    fi
fi

if [[ -f "$WAL_CACHE/colors.json" ]]; then
    log "done. background=$(grep -o '"background": *"#[0-9a-fA-F]*"' "$WAL_CACHE/colors.json" | head -1 | grep -o '#[0-9a-fA-F]*') foreground=$(grep -o '"foreground": *"#[0-9a-fA-F]*"' "$WAL_CACHE/colors.json" | head -1 | grep -o '#[0-9a-fA-F]*')"
else
    log "done."
fi
