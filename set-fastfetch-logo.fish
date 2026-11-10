#!/usr/bin/env fish
# set-fastfetch-logo.fish — đổi ảnh logo fastfetch mà không sợ mất ảnh gốc
#
# Bệnh: trỏ thẳng logo.source vào ~/Downloads hay /tmp thì hôm nào dọn
# Downloads / reboot là fastfetch mất logo. Ảnh nằm trong repo git cũng
# không an toàn hơn: checkout khác, git clean, đổi máy là mất.
#
# Script này làm 2 việc, theo thứ tự đó:
#   1. Copy ảnh anh chọn vào 1 chỗ cố định, ít bị dọn:
#      ~/.local/share/fastfetch/<tên file gốc>
#      (XDG_DATA_HOME, sống sót qua sửa config, dọn cache, đổi wallpaper)
#   2. Trỏ "logo": { "source": ... } trong
#      ~/.config/fastfetch/config.jsonc về đúng file đã copy đó.
#      Chỉ sửa mỗi giá trị source, giữ nguyên comment + format còn lại.
#
# An toàn:
#   - Không ghi đè lặng lẽ: ảnh đích cũ / config cũ đều backup .bak.<timestamp>
#   - Chạy lại với cùng 1 ảnh là no-op (không sinh thêm backup)
#   - --dry-run chỉ in ra sẽ làm gì, không chạm file nào
#   - Sửa config xong validate lại JSONC, hỏng thì hoàn lại backup và thoát lỗi
#   - Không tự tạo config.jsonc mới từ đầu: 1 file chỉ có logo sẽ lấn mất
#     toàn bộ module mặc định của fastfetch. Chưa có config thì chạy
#     `fastfetch --gen-config` trước rồi chạy lại script này.
#
# Cách dùng (fish, trên Nyarch):
#   fish set-fastfetch-logo.fish ~/Downloads/duyako-avatar-4-flat-transparent.png
#   fish set-fastfetch-logo.fish ~/Pictures/logo.png --name duyako.png
#   fish set-fastfetch-logo.fish ~/Pictures/logo.png --dry-run
#   fish set-fastfetch-logo.fish --restore   # hoàn lại config từ backup mới nhất
#
# Chưa verify trên máy thật (chỉ test với config.jsonc giả lập trên VM):
# chạy xong gõ `fastfetch` để xem ảnh có hiện không. Nếu ảnh không hiện,
# kiểm tra terminal có hỗ trợ kitty/sixel không, đừng sửa logo.type vội —
# script cố tình không đụng tới logo.type.

set -l src ""
set -l dest_name ""
set -l dest_dir "$HOME/.local/share/fastfetch"
set -l config_path "$HOME/.config/fastfetch/config.jsonc"
set -l dry_run 0
set -l restore 0

set -l i 1
while test $i -le (count $argv)
    set -l arg $argv[$i]
    switch $arg
        case --name
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "Thiếu giá trị cho --name" >&2
                exit 1
            end
            set dest_name $argv[$i]
        case --dest-dir
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "Thiếu giá trị cho --dest-dir" >&2
                exit 1
            end
            set dest_dir $argv[$i]
        case --config
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "Thiếu giá trị cho --config" >&2
                exit 1
            end
            set config_path $argv[$i]
        case --dry-run
            set dry_run 1
        case --restore
            set restore 1
        case --help -h
            echo "Usage: fish set-fastfetch-logo.fish <image> [--name <file>] [--dest-dir <dir>] [--config <path>] [--dry-run] [--restore]"
            echo "  <image>      ảnh PNG/JPG/WebP/... muốn làm logo fastfetch"
            echo "  --name       tên file đích (mặc định: giữ tên file gốc)"
            echo "  --dest-dir   chỗ chứa ảnh (mặc định: ~/.local/share/fastfetch)"
            echo "  --config     config fastfetch (mặc định: ~/.config/fastfetch/config.jsonc)"
            echo "  --dry-run    chỉ in ra sẽ làm gì, không chạm file nào"
            echo "  --restore    hoàn lại config từ file backup mới nhất"
            exit 0
        case '--*'
            echo "Flag không biết: $arg (xem --help)" >&2
            exit 1
        case '*'
            if test -n "$src"
                echo "Chỉ nhận 1 ảnh đầu vào, thừa: $arg" >&2
                exit 1
            end
            set src $arg
    end
    set i (math $i + 1)
end

# --restore: chỉ đụng config, không đụng ảnh
if test $restore -eq 1
    set -l latest (ls -t "$config_path".bak.* 2>/dev/null | head -n 1)
    if test -z "$latest"
        echo "Không tìm thấy backup nào cho $config_path" >&2
        exit 1
    end
    echo "==> Hoàn lại config từ $latest"
    if test $dry_run -eq 1
        echo "    (dry-run, chưa copy)"
        exit 0
    end
    cp -p "$latest" "$config_path"; or exit 1
    echo "==> OK: config đã về lại bản backup $latest"
    exit 0
end

if test -z "$src"
    echo "Thiếu ảnh đầu vào. Ví dụ:" >&2
    echo "  fish set-fastfetch-logo.fish ~/Downloads/duyako-avatar-4-flat-transparent.png" >&2
    exit 1
end

# 0. Kiểm tra tool + ảnh nguồn
if not command -q python3
    echo "Thiếu tool: python3 (dùng để sửa config.jsonc giữ nguyên comment)" >&2
    exit 1
end
if not test -f "$src"
    echo "Không thấy file ảnh: $src" >&2
    exit 1
end
if not string match -qi -r '\.(png|jpe?g|webp|gif|bmp)$' -- "$src"
    echo "Đuôi file không giống ảnh (png/jpg/webp/gif/bmp): $src" >&2
    exit 1
end
if command -q file
    set -l mime (file --mime-type -b -- "$src")
    if not string match -q 'image/*' -- "$mime"
        echo "file báo đây không phải ảnh ($mime): $src" >&2
        exit 1
    end
end
if not test -f "$config_path"
    echo "Không thấy config fastfetch: $config_path" >&2
    echo "Chạy `fastfetch --gen-config` để tạo config mặc định rồi chạy lại script này." >&2
    exit 1
end
if not command -q fastfetch
    echo "Cảnh báo: chưa thấy lệnh fastfetch trên máy, vẫn copy ảnh + sửa config." >&2
end

if test -z "$dest_name"
    set dest_name (basename -- "$src")
end
# Chống tên đích chứa / (đi lạc ra khỏi dest_dir)
if string match -q '*/*' -- "$dest_name"
    echo "--name không được chứa /: $dest_name" >&2
    exit 1
end
set -l dest_path "$dest_dir/$dest_name"
set -l ts (date "+%Y%m%d-%H%M%S")

if test $dry_run -eq 1
    echo "==> (dry-run) Copy: $src"
    echo "        -> $dest_path"
    echo "==> (dry-run) Sửa logo.source trong $config_path thành $dest_path"
    echo "    Backup cũ (nếu có thay đổi): $config_path.bak.$ts, $dest_path.bak.$ts"
    exit 0
end

# 1. Copy ảnh vào chỗ an toàn
mkdir -p "$dest_dir"; or exit 1
if test -f "$dest_path"
    if cmp -s -- "$src" "$dest_path"
        echo "==> Ảnh đích đã đúng nội dung, không cần copy lại: $dest_path"
    else
        set -l dest_bak "$dest_path.bak.$ts"
        echo "==> Ảnh đích cũ khác nội dung, backup: $dest_bak"
        cp -p -- "$dest_path" "$dest_bak"; or exit 1
        cp -p -- "$src" "$dest_path"; or exit 1
        echo "==> Đã copy ảnh mới đè lên: $dest_path"
    end
else
    cp -p -- "$src" "$dest_path"; or exit 1
    echo "==> Đã copy ảnh vào chỗ an toàn: $dest_path"
end

# 2. Trỏ logo.source trong config.jsonc về ảnh đích.
#    Chỉ sửa mỗi giá trị source, giữ nguyên comment + format còn lại.
#    Đọc config hiện tại trước để biết có cần sửa không.
set -l cur_source (python3 -c '
import json
import sys
def tokens(s):
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            while i < n and s[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            i += 2
            while i + 1 < n and not (s[i] == "*" and s[i + 1] == "/"):
                i += 1
            i += 2
            continue
        if c == "\"":
            d = json.JSONDecoder()
            v, e = d.raw_decode(s[i:])
            out.append(("str", v, i, i + e))
            i += e
            continue
        out.append((c, c, i, i + 1))
        i += 1
    return out
t = tokens(open(sys.argv[1], encoding="utf-8").read())
for k in range(len(t) - 2):
    if t[k][0] == "str" and t[k][1] == "logo" and t[k + 1][0] == ":" and t[k + 2][0] == "{":
        depth = 0
        for j in range(k + 2, len(t)):
            if t[j][0] == "{":
                depth += 1
            elif t[j][0] == "}":
                depth -= 1
                if depth == 0:
                    break
            if t[j][0] == "str" and t[j][1] == "source" and j + 2 < len(t) and t[j + 1][0] == ":" and t[j + 2][0] == "str":
                print(t[j + 2][1])
                break
        break
' "$config_path")

if test "$cur_source" = "$dest_path"
    echo "==> logo.source đã trỏ đúng $dest_path, không cần sửa config."
    echo "==> Xong. Gõ `fastfetch` để kiểm tra."
    exit 0
end

set -l cfg_bak "$config_path.bak.$ts"
echo "==> Backup config cũ: $cfg_bak"
cp -p -- "$config_path" "$cfg_bak"; or exit 1

python3 -c '
import json
import re
import sys
config_path = sys.argv[1]
dest = sys.argv[2]
text = open(config_path, encoding="utf-8").read()
def tokens(s):
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            while i < n and s[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            i += 2
            while i + 1 < n and not (s[i] == "*" and s[i + 1] == "/"):
                i += 1
            i += 2
            continue
        if c == "\"":
            d = json.JSONDecoder()
            v, e = d.raw_decode(s[i:])
            out.append(("str", v, i, i + e))
            i += e
            continue
        out.append((c, c, i, i + 1))
        i += 1
    return out
def strip_comments(s):
    out = []
    i = 0
    n = len(s)
    in_str = False
    esc = False
    while i < n:
        c = s[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == chr(92):
                esc = True
            elif c == "\"":
                in_str = False
            i += 1
            continue
        if c == "\"":
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            while i < n and s[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            i += 2
            while i + 1 < n and not (s[i] == "*" and s[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)
t = tokens(text)
new_text = None
root_open = None
for k in range(len(t)):
    if t[k][0] == "{":
        root_open = k
        break
if root_open is None:
    print("config không có object JSON ở gốc", file=sys.stderr)
    sys.exit(3)
logo_open = None
for k in range(len(t) - 2):
    if t[k][0] == "str" and t[k][1] == "logo" and t[k + 1][0] == ":":
        if t[k + 2][0] != "{":
            print("logo trong config không phải object, không dám sửa tự động", file=sys.stderr)
            sys.exit(2)
        logo_open = k + 2
        break
val = json.dumps(dest, ensure_ascii=False)
if logo_open is not None:
    depth = 0
    logo_close = None
    for j in range(logo_open, len(t)):
        if t[j][0] == "{":
            depth += 1
        elif t[j][0] == "}":
            depth -= 1
            if depth == 0:
                logo_close = j
                break
    if logo_close is None:
        print("không tìm thấy dấu đóng của logo", file=sys.stderr)
        sys.exit(3)
    replaced = False
    for j in range(logo_open + 1, logo_close - 1):
        if t[j][0] == "str" and t[j][1] == "source" and t[j + 1][0] == ":" and t[j + 2][0] == "str":
            new_text = text[:t[j + 2][2]] + val + text[t[j + 2][3]:]
            replaced = True
            break
    if not replaced:
        after_brace = t[logo_open][3]
        if t[logo_open + 1][0] == "}":
            new_text = text[:after_brace] + "\n    \"source\": " + val + "\n  " + text[after_brace:]
        else:
            new_text = text[:after_brace] + "\n    \"source\": " + val + "," + text[after_brace:]
else:
    after_brace = t[root_open][3]
    if t[root_open + 1][0] == "}":
        new_text = text[:after_brace] + "\n  \"logo\": {\n    \"source\": " + val + "\n  }\n" + text[after_brace:]
    else:
        new_text = text[:after_brace] + "\n  \"logo\": {\n    \"source\": " + val + "\n  }," + text[after_brace:]
clean = re.sub(r",\s*([}\]])", r"\1", strip_comments(new_text))
try:
    json.loads(clean)
except Exception as e:
    print("config sau khi sửa không parse được, không ghi file", file=sys.stderr)
    print(e, file=sys.stderr)
    sys.exit(3)
open(config_path, "w", encoding="utf-8").write(new_text)
' "$config_path" "$dest_path"; or begin
    echo "Sửa config lỗi, hoàn lại backup: $cfg_bak" >&2
    cp -p -- "$cfg_bak" "$config_path"
    exit 1
end

echo "==> Đã trỏ logo.source về $dest_path"
echo "==> Ảnh: $dest_path"
echo "==> Config: $config_path (backup: $cfg_bak)"
echo "==> Xong. Gõ `fastfetch` để kiểm tra."
