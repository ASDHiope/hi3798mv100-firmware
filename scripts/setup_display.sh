#!/bin/bash
echo "=== Hi3798MV100 Full Setup ==="

KVER=$(uname -r)
KO=/lib/modules/${KVER}/kernel/drivers/hisilicon
SRC=.

echo "[1/7] Loading driver modules..."
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

insmod $KO/ehci-platform.ko 2>/dev/null && echo "  ✅ ehci-platform" || true
insmod $KO/ohci-platform.ko 2>/dev/null && echo "  ✅ ohci-platform" || true

echo "  /proc/fb: $(cat /proc/fb 2>/dev/null)"

echo "[2/7] Installing Mali GPU libraries..."
MALI_LIB_DIR="/usr/lib/mali"
MALI_FOUND=0

if [ -d "${SRC}/lib" ]; then
    echo "  Searching for Mali GPU libraries in ${SRC}/lib..."
    for f in ${SRC}/lib/libMali.so* ${SRC}/lib/libmali.so*; do
        if [ -f "$f" ]; then
            echo "  Found: $f"
            mkdir -p "$MALI_LIB_DIR"
            cp "$f" "$MALI_LIB_DIR/" 2>/dev/null || true
            MALI_FOUND=1
        fi
    done
fi

if [ -f "${SRC}/lib/libMali.so.fbdev.r7p0" ]; then
    echo "  Installing Mali-450 r7p0 fbdev backend..."
    mkdir -p "$MALI_LIB_DIR"
    cp "${SRC}/lib/libMali.so.fbdev.r7p0" "$MALI_LIB_DIR/libMali.so"
    MALI_FOUND=1
elif [ -f "${SRC}/lib/libMali.so.x11.r7p0" ]; then
    echo "  Installing Mali-450 r7p0 x11 backend..."
    mkdir -p "$MALI_LIB_DIR"
    cp "${SRC}/lib/libMali.so.x11.r7p0" "$MALI_LIB_DIR/libMali.so"
    MALI_FOUND=1
fi

if [ $MALI_FOUND -eq 1 ] && [ -f "$MALI_LIB_DIR/libMali.so" ]; then
    echo "  ✅ libMali.so installed to $MALI_LIB_DIR"
    file "$MALI_LIB_DIR/libMali.so"

    cd "$MALI_LIB_DIR"
    ln -sf libMali.so libEGL.so.1.4
    ln -sf libEGL.so.1.4 libEGL.so.1
    ln -sf libEGL.so.1 libEGL.so
    ln -sf libMali.so libGLESv1_CM.so.1.1
    ln -sf libGLESv1_CM.so.1.1 libGLESv1_CM.so.1
    ln -sf libGLESv1_CM.so.1 libGLESv1_CM.so
    ln -sf libMali.so libGLESv2.so.2.0
    ln -sf libGLESv2.so.2.0 libGLESv2.so.2
    ln -sf libGLESv2.so.2 libGLESv2.so
    cd /

    echo "$MALI_LIB_DIR" > /etc/ld.so.conf.d/mali.conf
    ldconfig

    echo "  Mali library links created and ldconfig updated"
else
    echo "  ⏭️ No Mali GPU libraries found - will use fbdev software rendering"
    echo "  To enable GPU acceleration later, download Mali-450 user-space driver"
    echo "  from ARM: https://developer.arm.com/downloads/-/mali-utgard-user-space-drivers"
fi

echo "[3/7] Masking NFS services..."
systemctl mask proc-fs-nfsd.mount 2>/dev/null || true
systemctl mask nfs-server.service 2>/dev/null || true
systemctl mask nfs-idmapd.service 2>/dev/null || true
systemctl mask nfs-mountd.service 2>/dev/null || true

echo "[4/7] Removing Samba and Transmission..."
export DEBIAN_FRONTEND=noninteractive
for pkg in samba samba-common samba-common-bin samba-dsdb-modules samba-libs smbclient transmission-daemon transmission-cli transmission-common; do
    apt-get remove --purge -y "$pkg" 2>/dev/null || true
done
apt-get autoremove --purge -y 2>/dev/null || true

echo "[5/7] Installing X11 and Kodi..."
apt-get update -qq 2>/dev/null || true
for pkg in xserver-xorg-core xserver-xorg-video-fbdev xserver-xorg-input-evdev xinit x11-utils x11-xserver-utils; do
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: $pkg install failed"
done
for pkg in kodi kodi-bin kodi-data; do
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: $pkg install failed"
done
apt-get install -y --no-install-recommends bluez bluez-firmware pulseaudio-module-bluetooth 2>/dev/null || true
apt-get clean

echo "[6/7] Configuring X11, Kodi, and auto-start..."
mkdir -p /etc/X11

if [ -f "$MALI_LIB_DIR/libMali.so" ] && [ -e /dev/mali ]; then
    echo "  Configuring X11 with Mali GPU driver..."
    cat > /etc/X11/xorg.conf << 'XORGEOF'
Section "Device"
    Identifier  "Mali-450"
    Driver      "mali"
    Option      "fbdev"            "/dev/fb0"
    Option      "DRI2"             "true"
    Option      "SwapBuffersWait"  "true"
EndSection

Section "Screen"
    Identifier  "Default Screen"
    Device      "Mali-450"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
    EndSubSection
EndSection
XORGEOF
else
    echo "  Configuring X11 with fbdev driver (no GPU acceleration)..."
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
fi

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

echo "[7/7] Creating driver auto-load script..."
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
        load_module ehci-platform.ko 2>/dev/null || true
        load_module ohci-platform.ko 2>/dev/null || true
        echo "Drivers loaded. fb0: $([ -e /dev/fb0 ] && echo OK || echo MISSING)"
        ;;
    stop)
        for m in ohci_platform ehci_platform mali hi_tde hi_fb hi_hdmi hi_vou hi_pq hi_pdm hi_common hi_mmz hi_media; do
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
echo "  GPU device: $([ -e /dev/mali ] && echo '/dev/mali OK' || echo 'unavailable')"
echo "  GPU library: $([ -f /usr/lib/mali/libMali.so ] && echo 'libMali.so OK' || echo 'not installed (fbdev only)')"
echo "  X11 driver: $([ -f /usr/lib/mali/libMali.so ] && [ -e /dev/mali ] && echo 'mali (GPU)' || echo 'fbdev (software)')"
echo "  Kodi: $(systemctl is-enabled kodi.service 2>/dev/null)"
echo "  USB: $([ -d /sys/bus/usb/drivers/usb ] && echo 'OK' || echo 'not loaded')"
echo ""
if [ ! -f /usr/lib/mali/libMali.so ]; then
    echo "  ⚠️  GPU acceleration NOT available - libMali.so missing"
    echo "  To enable GPU acceleration:"
    echo "  1. Download Mali-450 user-space driver from ARM:"
    echo "     https://developer.arm.com/downloads/-/mali-utgard-user-space-drivers"
    echo "  2. Extract and install libMali.so:"
    echo "     mkdir -p /usr/lib/mali"
    echo "     cp libMali.so /usr/lib/mali/"
    echo "     cd /usr/lib/mali && ln -sf libMali.so libEGL.so.1.4 && ln -sf libEGL.so.1.4 libEGL.so.1"
    echo "     ln -sf libMali.so libGLESv2.so.2.0 && ln -sf libGLESv2.so.2.0 libGLESv2.so.2"
    echo "     echo '/usr/lib/mali' > /etc/ld.so.conf.d/mali.conf && ldconfig"
    echo "  3. Update /etc/X11/xorg.conf to use Driver 'mali'"
    echo "  4. Restart X and Kodi"
fi
echo ""
echo "  Next: reboot to test auto-start"
