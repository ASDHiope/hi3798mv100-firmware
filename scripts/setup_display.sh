#!/bin/bash
echo "=== Hi3798MV100 Full Setup ==="

KVER=$(uname -r)
KO=/lib/modules/${KVER}/kernel/drivers/hisilicon
SRC=.

echo "[1/6] Loading driver modules..."
rmmod mali hi_tde hi_fb hi_hdmi hi_vou hi_pq hi_pdm hi_common hi_mmz hi_media 2>/dev/null
insmod $KO/hi_media.ko  && echo "  ✅ hi_media"  || echo "  ❌ hi_media"
insmod $KO/hi_mmz.ko    && echo "  ✅ hi_mmz"    || echo "  ❌ hi_mmz"
insmod $KO/hi_common.ko && echo "  ✅ hi_common" || echo "  ❌ hi_common"
insmod $KO/hi_pdm.ko    && echo "  ✅ hi_pdm"    || echo "  ❌ hi_pdm"
insmod $KO/hi_pq.ko     && echo "  ✅ hi_pq"     || echo "  ❌ hi_pq"
insmod $KO/hi_hdmi.ko   && echo "  ✅ hi_hdmi"   || echo "  ❌ hi_hdmi"
insmod $KO/hi_vou.ko    && echo "  ✅ hi_vou"    || echo "  ❌ hi_vou"
insmod $KO/hi_fb.ko     && echo "  ✅ hi_fb"     || echo "  ❌ hi_fb"
insmod $KO/hi_tde.ko    && echo "  ✅ hi_tde"    || echo "  ❌ hi_tde"

insmod $KO/mali.ko 2>/dev/null && echo "  ✅ mali" || echo "  ⏭️ mali skipped (GPU accel unavailable)"

echo "  /proc/fb: $(cat /proc/fb 2>/dev/null)"

echo "[2/6] Masking NFS services..."
systemctl mask proc-fs-nfsd.mount 2>/dev/null || true
systemctl mask nfs-server.service 2>/dev/null || true
systemctl mask nfs-idmapd.service 2>/dev/null || true
systemctl mask nfs-mountd.service 2>/dev/null || true

echo "[3/6] Removing Samba and Transmission..."
export DEBIAN_FRONTEND=noninteractive
for pkg in samba samba-common samba-common-bin samba-dsdb-modules samba-libs smbclient transmission-daemon transmission-cli transmission-common; do
    apt-get remove --purge -y "$pkg" 2>/dev/null || true
done
apt-get autoremove --purge -y 2>/dev/null || true

echo "[4/6] Installing X11 and Kodi..."
apt-get update -qq 2>/dev/null || true
for pkg in xserver-xorg-core xserver-xorg-video-fbdev xserver-xorg-input-evdev xinit x11-utils x11-xserver-utils; do
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: $pkg install failed"
done
for pkg in kodi kodi-bin kodi-data; do
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: $pkg install failed"
done
apt-get install -y --no-install-recommends bluez bluez-firmware pulseaudio-module-bluetooth 2>/dev/null || true
apt-get clean

echo "[5/6] Configuring X11, Kodi, and auto-start..."
mkdir -p /etc/X11
cat > /etc/X11/xorg.conf << 'XORGEOF'
Section "Device"
    Identifier  "HiSilicon FB"
    Driver      "fbdev"
    Option      "fbdev" "/dev/fb0"
EndSection

Section "Screen"
    Identifier  "Default Screen"
    Device      "HiSilicon FB"
EndSection
XORGEOF

mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/99-mali.rules << 'UDEVEOF'
KERNEL=="mali", MODE="0666"
KERNEL=="ump", MODE="0666"
KERNEL=="mali0", MODE="0666"
UDEVEOF

cat > /etc/systemd/system/kodi.service << 'SERVICEEOF'
[Unit]
Description=Kodi Media Center
After=network.target hi3798mv100-drivers.service
Wants=NetworkManager.service

[Service]
User=root
Group=root
Type=simple
ExecStartPre=/bin/sleep 3
ExecStart=/usr/bin/kodi-standalone
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable kodi.service 2>/dev/null || true

echo "[6/6] Creating driver auto-load script..."
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/hisilicon-blacklist.conf << 'BLKEOF'
blacklist hi_mmz
blacklist hi_media
blacklist hi_common
blacklist hi_vou
blacklist hi_hdmi
blacklist hi_fb
blacklist hi_tde
blacklist hi_vpss
blacklist hi_pq
blacklist hi_sync
blacklist hi_pdm
blacklist mali
BLKEOF

cat > /etc/init.d/hi3798mv100-drivers << 'DRIVEREOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          hi3798mv100-drivers
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Load HiSilicon display drivers
### END INIT INFO

KVER=$(uname -r)
KO_DIR="/lib/modules/${KVER}/kernel/drivers/hisilicon"

load_module() {
    [ -f "${KO_DIR}/$1" ] || return 0
    lsmod | grep -q "^${1%.ko}[[:space:]]" && return 0
    insmod "${KO_DIR}/$1" $2
}

case "$1" in
    start)
        echo "Loading HiSilicon drivers..."
        load_module hi_media.ko  || return 1
        load_module hi_mmz.ko    || return 1
        load_module hi_common.ko || return 1
        load_module hi_pdm.ko
        load_module hi_pq.ko
        load_module hi_hdmi.ko
        load_module hi_vou.ko
        load_module hi_fb.ko
        load_module hi_tde.ko
        load_module mali.ko 2>/dev/null || true
        echo "Drivers loaded. fb0: $([ -e /dev/fb0 ] && echo OK || echo MISSING)"
        ;;
    stop)
        for m in mali hi_tde hi_fb hi_hdmi hi_vou hi_pq hi_pdm hi_common hi_mmz hi_media; do
            lsmod | grep -q "^${m}[[:space:]]" && rmmod "${m}" 2>/dev/null
        done
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        ;;
esac
DRIVEREOF
chmod +x /etc/init.d/hi3798mv100-drivers
update-rc.d hi3798mv100-drivers defaults 2>/dev/null || true

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  Display: $(cat /proc/fb 2>/dev/null)"
echo "  GPU: $([ -e /dev/mali ] && echo 'mali OK' || echo 'mali unavailable (fbdev only)')"
echo "  Kodi: $ (systemctl is-enabled kodi.service 2>/dev/null)"
echo ""
echo "  Next: reboot to test auto-start"
echo "  If mali.ko crashes, fix U-Boot bootargs:"
echo "    setenv bootargs ... mem=1G mmz=ddr,0,0,60M ..."
