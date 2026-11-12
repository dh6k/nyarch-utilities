#!/bin/bash
#
# install-gnome-terminal-shim.sh — shim gnome-terminal -> konsole/kitty (+ auto-accept)
#
# Nyarch Updater (flatpak moe.nyarchlinux.updater) hardcodes `gnome-terminal`
# when spawning update commands via `flatpak-spawn --host`:
#     gnome-terminal -- bash -c "<updateCmd> ; echo Done - Press enter to exit; read _"
# After migrating GNOME -> KDE, gnome-terminal is gone and every update fails
# with a generic "An error occurred during the update process".
#
# This installs /usr/local/bin/gnome-terminal, a shim that:
#   1. drops gnome-terminal's `--` separator (the target terminal would
#      treat it as the program name)
#   2. execs the chosen terminal with the remaining args:
#        konsole:  konsole -e <args...>   (konsole needs -e)
#        kitty:    kitty <args...>        (kitty takes the program directly, no -e)
#   3. unless --no-auto-accept is given, rewrites known update commands
#      to auto-accept prompts:
#        paru|yay|pikaur|trizen -Sua  ->  append --noconfirm
#        pacman -Syu                  ->  append --noconfirm
#        flatpak update               ->  append -y
#
# Idempotent: re-running just overwrites the same file.
# Needs sudo (writes to /usr/local/bin).
#
# Note: --noconfirm on AUR helpers skips the PKGBUILD diff review — the main
# AUR safety net. sudo password is still prompted as usual.
#
set -u

SHIM_PATH="/usr/local/bin/gnome-terminal"
TERMINAL="konsole"
AUTO_ACCEPT=1
DRY_RUN=0
UNINSTALL=0

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --terminal <kitty|konsole>  Terminal the shim execs (default: konsole)
  --kitty                     Shortcut for --terminal kitty
  --konsole                   Shortcut for --terminal konsole
  --no-auto-accept            Plain pass-through shim, no --noconfirm/-y rewrite
  --auto-accept               Rewrite known update commands (default)
  --dry-run                   Print the shim that would be installed, change nothing
  --uninstall                 Remove the shim (only if it is ours, see below)
  -h, --help                  Show this help

Examples:
  $0                                  # konsole + auto-accept (unchanged default)
  $0 --terminal kitty                 # kitty + auto-accept
  $0 --kitty --no-auto-accept         # kitty, plain pass-through
  $0 --dry-run --terminal kitty       # preview the kitty shim without installing
  $0 --uninstall                      # remove /usr/local/bin/gnome-terminal

Uninstall safety: --uninstall only removes the file if it contains our
shim marker. If you reinstalled the real gnome-terminal afterwards,
it refuses to delete it.
EOF
}

# Print the shim that would be installed, honouring $TERMINAL / $AUTO_ACCEPT.
# Built with printf '%s\n' line by line so the shim's own $/quotes survive
# untouched; only the exec line varies by terminal.
build_shim() {
    local exec_line
    if [[ "$TERMINAL" == "kitty" ]]; then
        # kitty syntax is `kitty [options] [program ...]` — no -e flag.
        exec_line='exec kitty "${args[@]}"'
    else
        exec_line='exec konsole -e "${args[@]}"'
    fi

    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "# gnome-terminal -> $TERMINAL compatibility shim (Nyarch Updater hardcodes gnome-terminal)"
    if [[ "$AUTO_ACCEPT" == "1" ]]; then
        printf '%s\n' '# Auto-accept edition: injects --noconfirm / -y into known update commands.'
    else
        printf '%s\n' '# Plain pass-through edition: no command rewriting (installed with --no-auto-accept).'
    fi
    printf '%s\n' 'args=()'
    printf '%s\n' 'for a in "$@"; do'
    printf '%s\n' "    [[ \"\$a\" == \"--\" ]] && continue  # target terminal would treat \`--\` as the program name"
    printf '%s\n' '    args+=("$a")'
    printf '%s\n' 'done'
    if [[ "$AUTO_ACCEPT" == "1" ]]; then
        printf '%s\n' '# Nyarch Updater always invokes: gnome-terminal -- bash -c "<script>"'
        printf '%s\n' 'if [[ "${args[0]}" == "bash" && "${args[1]}" == "-c" && -n "${args[2]:-}" ]]; then'
        printf '%s\n' '    args[2]="$(sed -e "s/\(paru\|yay\|pikaur\|trizen\) -Sua/\1 -Sua --noconfirm/g" \'
        printf '%s\n' '                   -e "s/pacman -Syu\b/pacman -Syu --noconfirm/g" \'
        printf '%s\n' '                   -e "s/flatpak update\b/flatpak update -y/g" \'
        printf '%s\n' '                   <<<"${args[2]}")"'
        printf '%s\n' 'fi'
    fi
    printf '%s\n' "$exec_line"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --terminal)
            [[ $# -ge 2 ]] || { echo "error: --terminal needs a value (kitty|konsole)" >&2; exit 2; }
            TERMINAL="$2"; shift 2 ;;
        --terminal=*)
            TERMINAL="${1#--terminal=}"; shift ;;
        --kitty)   TERMINAL="kitty";   shift ;;
        --konsole) TERMINAL="konsole"; shift ;;
        --no-auto-accept) AUTO_ACCEPT=0; shift ;;
        --auto-accept)    AUTO_ACCEPT=1; shift ;;
        --dry-run)  DRY_RUN=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 2 ;;
    esac
done

if [[ "$TERMINAL" != "kitty" && "$TERMINAL" != "konsole" ]]; then
    echo "error: --terminal must be kitty or konsole, got: $TERMINAL" >&2
    exit 2
fi

if [[ "$UNINSTALL" == "1" ]]; then
    if [[ ! -e "$SHIM_PATH" ]]; then
        echo "nothing to uninstall: $SHIM_PATH does not exist."
        exit 0
    fi
    if ! grep -q "compatibility shim (Nyarch Updater" "$SHIM_PATH" 2>/dev/null; then
        echo "error: $SHIM_PATH does not look like our shim — refusing to remove it." >&2
        echo "It may be the real gnome-terminal. Remove it manually if you really mean to." >&2
        exit 1
    fi
    sudo rm "$SHIM_PATH"
    echo "uninstalled: $SHIM_PATH"
    exit 0
fi

if ! command -v "$TERMINAL" >/dev/null 2>&1; then
    echo "warning: $TERMINAL not found in PATH — the shim will fail at runtime." >&2
fi

if [[ "$DRY_RUN" == "1" ]]; then
    build_shim
    exit 0
fi

build_shim | sudo tee "$SHIM_PATH" >/dev/null
sudo chmod 755 "$SHIM_PATH"
echo "installed: $SHIM_PATH (terminal=$TERMINAL, auto-accept=$([ "$AUTO_ACCEPT" == "1" ] && echo on || echo off))"
