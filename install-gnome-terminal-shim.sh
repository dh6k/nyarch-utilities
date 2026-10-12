#!/bin/bash
#
# install-gnome-terminal-shim.sh — shim gnome-terminal -> konsole (+ auto-accept)
#
# Nyarch Updater (flatpak moe.nyarchlinux.updater) hardcodes `gnome-terminal`
# when spawning update commands via `flatpak-spawn --host`:
#     gnome-terminal -- bash -c "<updateCmd> ; echo Done - Press enter to exit; read _"
# After migrating GNOME -> KDE, gnome-terminal is gone and every update fails
# with a generic "An error occurred during the update process".
#
# This installs /usr/local/bin/gnome-terminal, a shim that:
#   1. drops gnome-terminal's `--` separator (konsole would treat it as the program name)
#   2. execs `konsole -e` with the remaining args
#   3. rewrites known update commands to auto-accept prompts:
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

read -r -d '' SHIM <<'SHIM_EOF' || true
#!/usr/bin/env bash
# gnome-terminal -> konsole compatibility shim (Nyarch Updater hardcodes gnome-terminal)
# Auto-accept edition: injects --noconfirm / -y into known update commands.
args=()
for a in "$@"; do
    [[ "$a" == "--" ]] && continue  # konsole would treat `--` as the program name
    args+=("$a")
done
# Nyarch Updater always invokes: gnome-terminal -- bash -c "<script>"
if [[ "${args[0]}" == "bash" && "${args[1]}" == "-c" && -n "${args[2]:-}" ]]; then
    args[2]="$(sed -e "s/\(paru\|yay\|pikaur\|trizen\) -Sua/\1 -Sua --noconfirm/g" \
                   -e "s/pacman -Syu\b/pacman -Syu --noconfirm/g" \
                   -e "s/flatpak update\b/flatpak update -y/g" \
                   <<<"${args[2]}")"
fi
exec konsole -e "${args[@]}"
SHIM_EOF

if ! command -v konsole >/dev/null 2>&1; then
    echo "warning: konsole not found in PATH — the shim will fail at runtime." >&2
fi

printf '%s\n' "$SHIM" | sudo tee "$SHIM_PATH" >/dev/null
sudo chmod 755 "$SHIM_PATH"
echo "installed: $SHIM_PATH"
