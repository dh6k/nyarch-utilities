#!/usr/bin/env fish
# fix-zalo-aur.fish — fix 404 khi upstream thay asset Zalo dưới cùng 1 tag
#
# Bệnh: VN-Linux-Family/zalo-for-linux replace file release mà không đổi tag,
# tên file đổi hash commit (vd 3c3b891 -> d4452e1) nên PKGBUILD trên AUR 404.
# Script này không hardcode hash: nó hỏi GitHub API lấy tên asset mới nhất
# của đúng tag trong PKGBUILD, sửa _commithash, chạy updpkgsums rồi build.
#
# Đã verify 2026-11-09 01:47 +07:
#   tag 26.11.10 -> d4452e1, sha256 x86_64 =
#   35c6e37adfdb96546cd0e003d644950945e1d880425c13cb09f8f23e42244d30
#
# Cách dùng (fish, trên Nyarch):
#   fish ~/workspace/your_files/fix-zalo-aur.fish
#   fish ~/workspace/your_files/fix-zalo-aur.fish --no-build   # chỉ sửa PKGBUILD, chưa cài
#   fish ~/workspace/your_files/fix-zalo-aur.fish --dir ~/build/zalo-for-linux-bin
#
# Chạy lại được bất cứ lúc nào upstream thay hash lần nữa.

set -l no_build 0
set -l workdir "$HOME/build/zalo-for-linux-bin"

for arg in $argv
    switch $arg
        case --no-build
            set no_build 1
        case --dir
            # --dir <path> xử lý ở vòng sau, giữ đơn giản: dùng $argv[2]
            set workdir $argv[2]
        case --help -h
            echo "Usage: fish fix-zalo-aur.fish [--no-build] [--dir <path>]"
            exit 0
        case '*'
            # bỏ qua --dir value đã xử lý ở trên
            if test "$arg" = "$workdir"
                continue
            end
    end
end

# 0. Kiểm tra tool
for cmd in git curl python3 makepkg updpkgsums
    if not command -q $cmd
        echo "Thiếu tool: $cmd" >&2
        exit 1
    end
end
if not command -q paru; and not test -d "$workdir/.git"
    echo "Thiếu paru (chỉ cần khi chưa có sẵn thư mục AUR). Cài paru trước, hoặc git clone tay." >&2
    exit 1
end

# 1. Lấy / cập nhật PKGBUILD từ AUR
if test -d "$workdir/.git"
    echo "==> Cập nhật AUR repo ở $workdir"
    cd $workdir; or exit 1
    git pull --ff-only; or begin
        echo "git pull fail, giữ PKGBUILD hiện tại và tiếp tục" >&2
    end
else
    echo "==> Clone AUR zalo-for-linux-bin vào $workdir"
    mkdir -p (dirname $workdir); or exit 1
    git clone https://aur.archlinux.org/zalo-for-linux-bin.git $workdir; or exit 1
    cd $workdir; or exit 1
end

test -f PKGBUILD; or begin
    echo "Không thấy PKGBUILD trong $workdir" >&2
    exit 1
end

set -l pkgver (grep '^pkgver=' PKGBUILD | cut -d= -f2)
set -l zadarkver (grep '^_zadarkver=' PKGBUILD | cut -d= -f2)
set -l cur_hash (grep '^_commithash=' PKGBUILD | cut -d= -f2)
echo "==> PKGBUILD hiện tại: pkgver=$pkgver ZaDark=$_zadarkver _commithash=$cur_hash"

# 2. Hỏi GitHub API lấy tên asset x86_64 mới nhất của đúng tag đó
set -l api_url "https://api.github.com/repos/VN-Linux-Family/zalo-for-linux/releases/tags/$pkgver"
set -l tmp_json (mktemp)
curl -fsSL $api_url -o $tmp_json; or begin
    echo "Không gọi được GitHub API: $api_url" >&2
    rm -f $tmp_json
    exit 1
end

set -l asset_name (python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for a in d.get("assets", []):
    n = a.get("name", "")
    if "ZaDark" in n and n.endswith("-x86_64.AppImage"):
        print(n)
        break
' $tmp_json)
rm -f $tmp_json

if test -z "$asset_name"
    echo "Không tìm thấy asset ZaDark x86_64 trong release $pkgver" >&2
    exit 1
end
echo "==> Asset upstream hiện tại: $asset_name"

# 3. Lấy hash commit từ tên file: Zalo-<ver>+ZaDark-<ver>-<hash>-x86_64.AppImage
set -l new_hash (python3 -c '
import re, sys
m = re.search(r"-([0-9a-f]{7,40})-x86_64\.AppImage$", sys.argv[1])
print(m.group(1) if m else "")
' $asset_name)

if test -z "$new_hash"
    echo "Không parse được hash từ tên asset: $asset_name" >&2
    exit 1
end
echo "==> Hash mới: $new_hash"

# 4. Sửa PKGBUILD + regenerate checksum (updpkgsums tự tải file ~155MB)
if test "$new_hash" = "$cur_hash"
    echo "==> _commithash đã đúng, không cần sửa. Kiểm tra checksum/build tiếp."
else
    echo "==> Sửa _commithash: $cur_hash -> $new_hash"
    sed -i "s/^_commithash=.*/_commithash=$new_hash/" PKGBUILD; or exit 1
    echo "==> Chạy updpkgsums (tải lại AppImage để tính sha256 mới)..."
    updpkgsums; or begin
        echo "updpkgsums fail — có thể upstream vừa thay hash lần nữa, chạy lại script." >&2
        exit 1
    end
end

echo "==> PKGBUILD sau fix:"
grep -E '^pkgver=|^_zadarkver=|^_commithash=|^sha256sums_x86_64=' PKGBUILD

# 5. Build + cài
if test $no_build -eq 1
    echo "==> Xong (chưa build). Chạy tay: cd $workdir && makepkg -si"
    exit 0
end

echo "==> Build + cài: makepkg -si"
makepkg -si; or begin
    echo "makepkg fail. Nếu lỗi vẫn là 404, upstream lại thay hash — chạy lại script này." >&2
    exit 1
end

echo "==> OK: zalo-for-linux-bin $pkgver đã build/cài xong."
