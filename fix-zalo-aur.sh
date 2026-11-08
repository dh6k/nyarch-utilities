#!/usr/bin/env bash
# fix-zalo-aur.sh — fix 404 khi upstream thay asset Zalo dưới cùng 1 tag
# Bản bash, tương đương fix-zalo-aur.fish, cho máy không có fish.
#
# Bệnh: VN-Linux-Family/zalo-for-linux replace file release mà không đổi tag,
# tên file đổi hash commit (vd 3c3b891 -> d4452e1) nên PKGBUILD trên AUR 404.
# Script này không hardcode hash: nó hỏi GitHub API lấy tên asset mới nhất
# của đúng tag trong PKGBUILD, sửa _commithash, chạy updpkgsums rồi build.
#
# Đã verify 2026-11-09 01:54 +07 (snapshot, upstream thay liên tục):
#   tag 26.11.10 -> 3680a0e, sha256 x86_64 =
#   1c5d02c22c83ea6d9684857da8683bc4154de911f1337e5ac0d06c874a4f23b9
#   (07 phút trước, 01:47, vẫn là d4452e1 / 35c6e37a…44d30 — đã bị thay.
#   Đừng hardcode hash, script tự dò lại lúc chạy.)
#
# Cách dùng (bash, trên Arch/Nyarch):
#   bash fix-zalo-aur.sh
#   bash fix-zalo-aur.sh --no-build   # chỉ sửa PKGBUILD, chưa cài
#   bash fix-zalo-aur.sh --dir ~/build/zalo-for-linux-bin
#   ./fix-zalo-aur.sh                 # nhờ shebang, cần chmod +x trước
#
# Chạy lại được bất cứ lúc nào upstream thay hash lần nữa.

set -euo pipefail

no_build=0
workdir="$HOME/build/zalo-for-linux-bin"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)
            no_build=1
            shift
            ;;
        --dir)
            workdir="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: bash fix-zalo-aur.sh [--no-build] [--dir <path>]"
            exit 0
            ;;
        *)
            echo "Tham số không rõ: $1" >&2
            exit 1
            ;;
    esac
done

# 0. Kiểm tra tool
for cmd in git curl python3 makepkg updpkgsums; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Thiếu tool: $cmd" >&2
        exit 1
    fi
done
if ! command -v paru >/dev/null 2>&1 && [[ ! -d "$workdir/.git" ]]; then
    echo "Thiếu paru (chỉ cần khi chưa có sẵn thư mục AUR). Cài paru trước, hoặc git clone tay." >&2
    exit 1
fi

# 1. Lấy / cập nhật PKGBUILD từ AUR
if [[ -d "$workdir/.git" ]]; then
    echo "==> Cập nhật AUR repo ở $workdir"
    cd "$workdir"
    git pull --ff-only || echo "git pull fail, giữ PKGBUILD hiện tại và tiếp tục" >&2
else
    echo "==> Clone AUR zalo-for-linux-bin vào $workdir"
    mkdir -p "$(dirname "$workdir")"
    git clone https://aur.archlinux.org/zalo-for-linux-bin.git "$workdir"
    cd "$workdir"
fi

[[ -f PKGBUILD ]] || { echo "Không thấy PKGBUILD trong $workdir" >&2; exit 1; }

pkgver="$(grep '^pkgver=' PKGBUILD | cut -d= -f2)"
zadarkver="$(grep '^_zadarkver=' PKGBUILD | cut -d= -f2)"
cur_hash="$(grep '^_commithash=' PKGBUILD | cut -d= -f2)"
echo "==> PKGBUILD hiện tại: pkgver=$pkgver ZaDark=$zadarkver _commithash=$cur_hash"

# 2. Hỏi GitHub API lấy tên asset x86_64 mới nhất của đúng tag đó
api_url="https://api.github.com/repos/VN-Linux-Family/zalo-for-linux/releases/tags/$pkgver"
tmp_json="$(mktemp)"
trap 'rm -f "$tmp_json"' EXIT
curl -fsSL "$api_url" -o "$tmp_json"

asset_name="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for a in d.get("assets", []):
    n = a.get("name", "")
    if "ZaDark" in n and n.endswith("-x86_64.AppImage"):
        print(n)
        break
' "$tmp_json")"

[[ -n "$asset_name" ]] || { echo "Không tìm thấy asset ZaDark x86_64 trong release $pkgver" >&2; exit 1; }
echo "==> Asset upstream hiện tại: $asset_name"

# 3. Lấy hash commit từ tên file: Zalo-<ver>+ZaDark-<ver>-<hash>-x86_64.AppImage
if [[ "$asset_name" =~ -([0-9a-f]{7,40})-x86_64\.AppImage$ ]]; then
    new_hash="${BASH_REMATCH[1]}"
else
    echo "Không parse được hash từ tên asset: $asset_name" >&2
    exit 1
fi
echo "==> Hash mới: $new_hash"

# 4. Sửa PKGBUILD + regenerate checksum (updpkgsums tự tải file ~155MB)
if [[ "$new_hash" == "$cur_hash" ]]; then
    echo "==> _commithash đã đúng, không cần sửa. Kiểm tra checksum/build tiếp."
else
    echo "==> Sửa _commithash: $cur_hash -> $new_hash"
    sed -i "s/^_commithash=.*/_commithash=$new_hash/" PKGBUILD
    echo "==> Chạy updpkgsums (tải lại AppImage để tính sha256 mới)..."
    updpkgsums || { echo "updpkgsums fail — có thể upstream vừa thay hash lần nữa, chạy lại script." >&2; exit 1; }
fi

echo "==> PKGBUILD sau fix:"
grep -E '^pkgver=|^_zadarkver=|^_commithash=|^sha256sums_x86_64=' PKGBUILD

# 5. Build + cài
if [[ "$no_build" -eq 1 ]]; then
    echo "==> Xong (chưa build). Chạy tay: cd $workdir && makepkg -si"
    exit 0
fi

echo "==> Build + cài: makepkg -si"
makepkg -si || { echo "makepkg fail. Nếu lỗi vẫn là 404, upstream lại thay hash — chạy lại script này." >&2; exit 1; }

echo "==> OK: zalo-for-linux-bin $pkgver đã build/cài xong."
