#!/bin/bash
#
# material-you-setup.sh — Cài đặt + vá + tự duy trì stack Material You trên KDE Plasma
#
#   ./material-you-setup.sh [--scheme dark|light]   cài đặt đầy đủ, CHẠY AS USER (không sudo)
#   sudo material-you-setup.sh --patch-only         chỉ vá lại 3 patch v3 (pacman hook gọi mode này)
#
# Full mode làm 4 việc:
#   1. Cài package: kde-material-you-colors, adwaita-material-you (AUR) + inotify-tools (repo)
#   2. Vá tương thích materialyoucolor v3 (3 chỗ, idempotent)
#   3. Dựng hook tự chạy lại adwmu khi đổi wallpaper (systemd user service)
#   4. Tự cài chính nó vào /usr/local/bin + pacman hook để tự vá lại sau mỗi lần update
#
set -u

SCHEME="dark"
MODE="full"

usage() {
    echo "Usage:"
    echo "  ./material-you-setup.sh [--scheme dark|light]   # full setup, chạy AS USER"
    echo "  sudo ./material-you-setup.sh --patch-only        # chỉ vá lại (cho pacman hook)"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --patch-only) MODE="patch"; shift ;;
        --scheme) SCHEME="${2:-dark}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1"; usage; exit 1 ;;
    esac
done

log() { echo "[material-you] $*"; }
die() { echo "[material-you] LỖI: $*" >&2; exit 1; }

SCRIPT_SRC="$(readlink -f "$0")"
INSTALLED_PATH="/usr/local/bin/material-you-setup.sh"

# ---------------------------------------------------------------- patches ---
patch_all() {
    local PYVER KDE_DIR ADW_MAIN f patched skipped ok pf
    PYVER="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")"
    KDE_DIR="/usr/lib/python${PYVER}/site-packages/kde_material_you_colors"
    ADW_MAIN="/usr/lib/adwaita-material-you/main.py"
    patched=0; skipped=0

    # Patch 1: extra_image_utils.py — v3 bỏ kwarg dislike_filter khỏi ScoreOptions
    f="$KDE_DIR/utils/extra_image_utils.py"
    if [ -f "$f" ]; then
        if grep -q "dislike_filter" "$f"; then
            sed -i '/dislike_filter/d' "$f" \
                && log "patched: extra_image_utils.py (xoa dislike_filter)" \
                && patched=$((patched + 1))
        else
            log "skip (da patch hoac upstream da fix): extra_image_utils.py"
            skipped=$((skipped + 1))
        fi
    else
        log "skip (khong thay kde-material-you-colors)"
        skipped=$((skipped + 1))
    fi

    # Patch 2: m3_scheme_utils.py — v3 palette.tone() trả ARGB int trực tiếp
    f="$KDE_DIR/utils/m3_scheme_utils.py"
    if [ -f "$f" ]; then
        if grep -Fq 'hexFromArgb(argb_from_rgba(palette.tone(x)))' "$f"; then
            sed -i 's|hexFromArgb(argb_from_rgba(palette\.tone(x)))|hexFromArgb(palette.tone(x))|' "$f" \
                && log "patched: m3_scheme_utils.py (palette.tone v3)" \
                && patched=$((patched + 1))
        else
            log "skip (da patch hoac upstream da fix): m3_scheme_utils.py"
            skipped=$((skipped + 1))
        fi
    fi

    # Patch 3: adwaita-material-you main.py — v3 props values là ARGB int (v2 là RGBA list)
    f="$ADW_MAIN"
    if [ -f "$f" ]; then
        if grep -Fq 'if isinstance(color, int)' "$f"; then
            log "skip (da patch): main.py (adwaita-material-you)"
            skipped=$((skipped + 1))
        elif grep -Fq 'generated[key] = ColorUtils.argb_from_argb_arr(color[0]' "$f"; then
            sed -i 's|generated\[key\] = ColorUtils.argb_from_argb_arr(color\[0\], color\[1\], color\[2\], color\[3\])|generated[key] = color if isinstance(color, int) else ColorUtils.argb_from_argb_arr(color[0], color[1], color[2], color[3])|' "$f" \
                && log "patched: main.py (isinstance guard)" \
                && patched=$((patched + 1))
        else
            log "WARN: khong nhan ra format main.py — kiem tra tay: $f"
        fi
    else
        log "skip (khong thay adwaita-material-you)"
        skipped=$((skipped + 1))
    fi

    # Verify: compile check + smoke test import
    ok=1
    for pf in "$KDE_DIR/utils/extra_image_utils.py" "$KDE_DIR/utils/m3_scheme_utils.py" "$ADW_MAIN"; do
        if [ -f "$pf" ]; then
            python -m py_compile "$pf" 2>/dev/null || { log "SYNTAX FAIL: $pf"; ok=0; }
        fi
    done
    if [ -d "$KDE_DIR" ]; then
        if python -c "from kde_material_you_colors.utils.extra_image_utils import SCORE_OPTIONS" 2>/dev/null; then
            log "smoke test OK: SCORE_OPTIONS import duoc"
        else
            log "smoke test FAIL: extra_image_utils import loi"; ok=0
        fi
    fi

    if [ "$ok" -eq 1 ]; then
        log "patch xong: patched=$patched skipped=$skipped — TAT CA OK"
    else
        log "patch xong: patched=$patched skipped=$skipped — CO LOI, kiem tra lai"
    fi
    return $((1 - ok))
}

# ---------------------------------------------------------------- install ---
install_packages() {
    local helper=""
    if command -v paru >/dev/null 2>&1; then
        helper="paru"
    elif command -v yay >/dev/null 2>&1; then
        helper="yay"
    else
        die "cần paru hoặc yay để cài AUR — cài một trong hai trước"
    fi
    log "cài package: kde-material-you-colors adwaita-material-you inotify-tools ($helper)"
    "$helper" -S --needed --noconfirm kde-material-you-colors adwaita-material-you inotify-tools \
        || die "cài package thất bại"
}

# ------------------------------------------------------- wallpaper hook ---
setup_wallpaper_hook() {
    local bindir="$HOME/.local/bin"
    local svc_dir="$HOME/.config/systemd/user"
    mkdir -p "$bindir" "$svc_dir"

    cat > "$bindir/adwmu-wallpaper-hook.sh" <<'HOOK_EOF'
#!/bin/bash
# Hook: tự chạy lại adwmu mỗi khi đổi wallpaper trên Plasma
# (tự sinh bởi material-you-setup.sh)
set -u
DIR="$HOME/.config"
FILE="plasma-org.kde.plasma.desktop-appletsrc"
CFG="$DIR/$FILE"
SCHEME="@@SCHEME@@"
last=""

get_wallpaper() {
    awk '
        /^\[Containments\]\[[0-9]+\]\[Wallpaper\]\[org\.kde\.image\]\[General\]$/ { t=1; next }
        /^\[/ { t=0 }
        t && /^Image=/ { sub(/^Image=/, ""); sub(/^file:\/\//, ""); print; exit }
    ' "$CFG" 2>/dev/null
}

apply() {
    local img
    img="$(get_wallpaper)"
    if [ -n "$img" ] && [ -f "$img" ] && [ "$img" != "$last" ]; then
        last="$img"
        echo "[hook] wallpaper -> $img"
        adwmu "$SCHEME" -w "$img" -a
    fi
}

apply
inotifywait -m -e close_write -e moved_to --format '%f' "$DIR" 2>/dev/null | while read -r f; do
    [ "$f" = "$FILE" ] || continue
    sleep 2
    apply
done
HOOK_EOF
    sed -i "s/@@SCHEME@@/$SCHEME/" "$bindir/adwmu-wallpaper-hook.sh"
    chmod +x "$bindir/adwmu-wallpaper-hook.sh"
    log "đã viết $bindir/adwmu-wallpaper-hook.sh (scheme=$SCHEME)"

    cat > "$svc_dir/adwmu-wallpaper-hook.service" <<'SVC_EOF'
[Unit]
Description=Re-apply adwaita-material-you on wallpaper change
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/adwmu-wallpaper-hook.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SVC_EOF

    # dọn file .desktop autostart cũ (giờ service đã tự apply lúc login)
    rm -f "$HOME/.config/autostart/adwaita-material-you.desktop"

    if systemctl --user daemon-reload && systemctl --user enable --now adwmu-wallpaper-hook.service; then
        log "hook service: enabled + running"
    else
        log "WARN: không enable được user service (đang ngoài desktop session?) — chạy tay sau:"
        log "  systemctl --user daemon-reload && systemctl --user enable --now adwmu-wallpaper-hook.service"
    fi
}

# ---------------------------------------------------------- pacman hook ---
setup_pacman_hook() {
    # tự cài chính mình vào /usr/local/bin để hook gọi được về sau
    if [ "$SCRIPT_SRC" != "$INSTALLED_PATH" ]; then
        sudo install -m 755 "$SCRIPT_SRC" "$INSTALLED_PATH" \
            && log "đã tự cài vào $INSTALLED_PATH"
    fi
    # dọn file của bản 2-file cũ (nếu từng cài)
    sudo rm -f /usr/local/bin/rematerialyou-patch.sh

    sudo mkdir -p /etc/pacman.d/hooks
    sudo tee /etc/pacman.d/hooks/materialyou-v3-compat.hook > /dev/null <<'HOOK2_EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = kde-material-you-colors
Target = adwaita-material-you
Target = python-materialyoucolor3

[Action]
Description = Re-apply materialyoucolor v3 compatibility patches for Material You tools
When = PostTransaction
Exec = /usr/local/bin/material-you-setup.sh --patch-only
HOOK2_EOF
    log "đã cài pacman hook /etc/pacman.d/hooks/materialyou-v3-compat.hook"
}

# ------------------------------------------------------------------ main ---
main() {
    if [ "$MODE" = "patch" ]; then
        [ "$(id -u)" -eq 0 ] || die "--patch-only cần chạy bằng root (sudo)"
        patch_all
        return $?
    fi

    [ "$(id -u)" -ne 0 ] || die "chạy AS USER (không sudo) — script tự sudo khi cần"

    log "=== Material You setup: scheme=$SCHEME ==="
    install_packages
    patch_all || die "vá patch thất bại, dừng lại"
    setup_wallpaper_hook
    setup_pacman_hook
    log "=== XONG ==="
    log "- kde-material-you-colors: chạy thử 'kde-material-you-colors' (thêm plasmoid widget nếu muốn điều khiển từ panel)"
    log "- adwmu: hook wallpaper đang chạy — đổi wallpaper thử rồi check:"
    log "    journalctl --user-unit=adwmu-wallpaper-hook.service -f"
    log "- từ giờ mỗi lần update 3 package trên, pacman hook tự vá lại — không cần nhớ gì"
}

main "$@"
