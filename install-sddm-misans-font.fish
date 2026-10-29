#!/usr/bin/env fish
# install-sddm-misans-font.fish - Dong bo SDDM (theme breeze) voi MiSans VF + scale 125%
#
# Vi sao can script rieng, khong dung lai fonts.conf cua user:
# SDDM chay truoc khi login, no khong doc ~/.local/share/fonts cua user,
# cung khong doc kdeglobals cua user. No chi doc phuong he thong va
# config cua chinh no. Vi vay phai:
#   1. Copy phuong MiSans tu ~/.local/share/fonts/MiSans sang
#      /usr/share/fonts/MiSans (he thong, SDDM/root thay duoc)
#   2. Copy ~/.config/fontconfig/fonts.conf sang /etc/fonts/local.conf
#      (he thong, de greeter an cung config VF-first + hintslight/none)
#   3. Ghi /etc/sddm.conf.d/99-font.conf voi [Theme] Font=MiSans VF
#   4. Ghi /etc/sddm.conf.d/99-hidpi.conf voi scale 125% cho greeter X11
#
# Scale 125% (da verify tren may user 2026-10-30, greeter X11):
#   - Chi set X ServerArguments=-nolisten tcp -dpi 120 thi KHONG du:
#     journal thay X chay dung -dpi 120 nhung greeter Qt6 tren X11
#     bo qua DPI cua X, nhin van nhu 100%.
#   - Cai keo UI len that la GreeterEnvironment:
#     QT_AUTO_SCREEN_SCALE_FACTOR=0,QT_SCALE_FACTOR=1.25,QT_FONT_DPI=96
#   - Sau khi them GreeterEnvironment, bo -dpi 120 di van giu 125%,
#     nen script nay KHONG dung -dpi 120 nua.
#   - 1.25 = scale Plasma cua user (125%). Neu doi scale Plasma thi
#     sua lai QT_SCALE_FACTOR trong script cho khop.
#
# Yeu cau truoc khi chay:
#   - Da chay install-misans.sh voi MiSans.zip, de phuong nam o
#     ~/.local/share/fonts/MiSans va fonts.conf nam o
#     ~/.config/fontconfig/fonts.conf
#   - Theme SDDM hien tai la breeze (da xac nhan tren may user)
#   - Greeter SDDM dang chay X11 (DisplayServer=x11 trong
#     /usr/lib/sddm/sddm.conf.d/default.conf, da xac nhan tren may user)
#
# Script KHONG restart SDDM tu dong, vi restart se dang xuat session
# hien tai. Xem truoc bang lenh o cuoi output, ung roi moi logout/reboot.
# Luu y: --test-mode chay trong session hien tai nen KHONG phan anh
# scale cua greeter that; muon kiem scale that phai logout/reboot.
#
# Cach dung (fish):
#   fish install-sddm-misans-font.fish
#   # hoac, sau khi chmod +x:
#   ./install-sddm-misans-font.fish
#
# Luu y: cac lenh sudo se hoi mat khau nhu binh thuong.

echo "== SDDM sync (breeze) -> MiSans VF + scale 125% =="

# 0. Kiem tra cong cu can thiet
for cmd in fc-list fc-cache sudo tee printf
    if not command -q $cmd
        echo "ERROR: thieu lenh $cmd" >&2
        exit 1
    end
end

set source_dir $HOME/.local/share/fonts/MiSans
set user_fonts_conf $HOME/.config/fontconfig/fonts.conf

# 1. Kiem tra phuong per-user da co chua
if not test -d $source_dir
    echo "ERROR: khong thay $source_dir" >&2
    echo "Hay chay install-misans.sh voi MiSans.zip truoc." >&2
    exit 1
end

set ttf_files (find $source_dir -maxdepth 1 -type f -iname '*.ttf' 2>/dev/null)
set otf_files (find $source_dir -maxdepth 1 -type f -iname '*.otf' 2>/dev/null)
set font_files $ttf_files $otf_files
if test (count $font_files) -eq 0
    echo "ERROR: $source_dir khong co file .ttf/.otf nao." >&2
    echo "Hay chay install-misans.sh voi MiSans.zip truoc." >&2
    exit 1
end
echo "Tim thay "(count $font_files)" file phuong o $source_dir"

if not test -f $user_fonts_conf
    echo "ERROR: khong thay $user_fonts_conf" >&2
    echo "Hay chay install-misans.sh truoc de tao fonts.conf." >&2
    exit 1
end

# 2. Theme hien tai (chi in ra de kiem tra, khong dung de dung script)
echo ""
echo "== Theme SDDM hien tai =="
grep -r "^Current" /etc/sddm.conf /etc/sddm.conf.d/ 2>/dev/null
if test $status -ne 0
    echo "(khong tim thay Current, gia dinh la breeze)"
end

# 3. Copy phuong sang he thong
echo ""
echo "== 1. Copy phuong sang /usr/share/fonts/MiSans =="
sudo mkdir -p /usr/share/fonts/MiSans
if test $status -ne 0
    echo "ERROR: khong tao duoc /usr/share/fonts/MiSans" >&2
    exit 1
end
sudo cp $font_files /usr/share/fonts/MiSans/
if test $status -ne 0
    echo "ERROR: copy phuong that bai" >&2
    exit 1
end
ls /usr/share/fonts/MiSans/

# 4. Copy fonts.conf sang he thong, backup neu da co
echo ""
echo "== 2. Copy fonts.conf sang /etc/fonts/local.conf =="
if test -f /etc/fonts/local.conf
    set backup "/etc/fonts/local.conf.bak."(date +%Y%m%d-%H%M%S)
    sudo cp /etc/fonts/local.conf $backup
    if test $status -ne 0
        echo "ERROR: backup /etc/fonts/local.conf that bai" >&2
        exit 1
    end
    echo "Da backup /etc/fonts/local.conf cu sang: $backup"
end
sudo cp $user_fonts_conf /etc/fonts/local.conf
if test $status -ne 0
    echo "ERROR: copy fonts.conf sang /etc/fonts/local.conf that bai" >&2
    exit 1
end
echo "Da ghi /etc/fonts/local.conf tu $user_fonts_conf"

# 5. Rebuild cache + verify VF thay duoc o muc he thong
echo ""
echo "== 3. Rebuild font cache + verify =="
sudo fc-cache -fv > /dev/null
if test $status -ne 0
    echo "ERROR: fc-cache that bai" >&2
    exit 1
end
echo "Cache rebuilt."
set vf_list (fc-list | grep -i 'MiSans VF')
if test (count $vf_list) -eq 0
    echo "WARNING: fc-list khong thay 'MiSans VF' sau khi copy." >&2
    echo "Kiem tra lai file zip: co phai MiSans.zip (ban VF) khong, hay la ban static-only?" >&2
else
    echo "MiSans VF thay duoc o muc he thong:"
    for line in $vf_list
        echo "  $line"
    end
end

# 6. Ghi config SDDM: [Theme] Font=MiSans VF
# Dung file rieng 99-font.conf, xep sau kde_settings.conf, de KDE
# co ghi lai kde_settings.conf thi file nay van thang.
echo ""
echo "== 4. Ghi /etc/sddm.conf.d/99-font.conf =="
sudo mkdir -p /etc/sddm.conf.d
if test $status -ne 0
    echo "ERROR: khong tao duoc /etc/sddm.conf.d" >&2
    exit 1
end
printf '[Theme]\nFont=MiSans VF\n' | sudo tee /etc/sddm.conf.d/99-font.conf > /dev/null
if test $status -ne 0
    echo "ERROR: ghi /etc/sddm.conf.d/99-font.conf that bai" >&2
    exit 1
end
echo "Da ghi:"
cat /etc/sddm.conf.d/99-font.conf

# 7. Ghi config scale 125% cho greeter X11
# Dung file rieng 99-hidpi.conf, xep sau kde_settings.conf va default.conf.
# KHONG dung -dpi 120: da verify tren may user la DPI mot minh khong
# keo duoc greeter Qt6, va sau khi co GreeterEnvironment thi bo -dpi
# di van giu 125%. ServerArguments giu dung gia tri mac dinh.
echo ""
echo "== 5. Ghi /etc/sddm.conf.d/99-hidpi.conf (scale 125%, greeter X11) =="
printf '[General]\nGreeterEnvironment=QT_AUTO_SCREEN_SCALE_FACTOR=0,QT_SCALE_FACTOR=1.25,QT_FONT_DPI=96\n\n[X11]\nServerArguments=-nolisten tcp\nEnableHiDPI=true\n' | sudo tee /etc/sddm.conf.d/99-hidpi.conf > /dev/null
if test $status -ne 0
    echo "ERROR: ghi /etc/sddm.conf.d/99-hidpi.conf that bai" >&2
    exit 1
end
echo "Da ghi:"
cat /etc/sddm.conf.d/99-hidpi.conf

echo ""
echo "Done. Script KHONG restart SDDM (restart se dang xuat session hien tai)."
echo "Xem truoc phuong greeter ma khong can logout (chay bang user thuong, khong sudo):"
echo "  sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/breeze"
echo "Luu y: --test-mode KHONG phan anh scale greeter that, vi no chay"
echo "trong session hien tai. Muon kiem scale 125% that phai logout/reboot."
echo "Luu y: dong bo phuong o day la dong bo family (MiSans VF), co chu greeter"
echo "lay theo theme, khong lay theo 11pt cua KDE."
