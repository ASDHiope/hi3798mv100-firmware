#!/bin/bash
set -e

echo "============================================"
echo "  Hi3798MV100 On-Device Modification Script"
echo "  Run this script ON the device itself"
echo "============================================"
echo ""

if [ "$(uname -m)" != "armv7l" ] && [ "$(uname -m)" != "armhf" ]; then
    echo "ERROR: This script must be run on the ARM device"
    echo "Current arch: $(uname -m)"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root"
    echo "Usage: sudo bash $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/var/log/hi3798_modification.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "Start time: $(date)"
echo "Current disk usage:"
df -h /
echo ""

echo "[1/6] Removing Samba and Transmission..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

PACKAGES_TO_REMOVE="samba samba-common samba-common-bin samba-dsdb-modules samba-libs smbclient transmission-daemon transmission-cli transmission-common"

for pkg in $PACKAGES_TO_REMOVE; do
    if dpkg -l "$pkg" &>/dev/null; then
        echo "  Removing $pkg..."
        apt-get remove --purge -y "$pkg" 2>/dev/null || echo "  Warning: Could not remove $pkg"
    else
        echo "  $pkg not installed, skipping"
    fi
done

apt-get autoremove --purge -y 2>/dev/null || true
echo "  Samba and Transmission removed"

echo ""
echo "[2/6] Installing X11 and GPU support..."
PACKAGES_X11="xserver-xorg-core xserver-xorg-video-fbdev xserver-xorg-input-evdev xinit x11-utils x11-xserver-utils"

for pkg in $PACKAGES_X11; do
    echo "  Installing $pkg..."
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: Could not install $pkg"
done

echo ""
echo "[3/6] Installing Kodi..."
PACKAGES_KODI="kodi kodi-bin kodi-data kodi-repository-kodi kodi-inputstream-adaptive kodi-pvr-iptvsimple"

for pkg in $PACKAGES_KODI; do
    echo "  Installing $pkg..."
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: Could not install $pkg"
done

echo ""
echo "[4/6] Installing Bluetooth support..."
PACKAGES_BT="bluez bluez-firmware python3-dbus libbluetooth3 pulseaudio-module-bluetooth"

for pkg in $PACKAGES_BT; do
    echo "  Installing $pkg..."
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: Could not install $pkg"
done

apt-get clean

echo ""
echo "[5/6] Configuring GPU, Kodi, and Bluetooth..."
mkdir -p /etc/X11
cat > /etc/X11/xorg.conf << 'XORGEOF'
Section "Device"
    Identifier  "Mali-450"
    Driver      "mali"
    Option      "fbdev"            "/dev/fb0"
    Option      "DRI2"            "true"
    Option      "SwapBuffersWait" "true"
EndSection

Section "Screen"
    Identifier  "Default Screen"
    Device      "Mali-450"
EndSection
XORGEOF

mkdir -p /etc/udev/rules.d
cat > /etc/udev/rules.d/99-mali.rules << 'UDEVEOF'
KERNEL=="mali", MODE="0666"
KERNEL=="ump", MODE="0666"
KERNEL=="mali0", MODE="0666"
UDEVEOF

mkdir -p /home/ubuntu/.kodi/userdata
cat > /home/ubuntu/.kodi/userdata/sources.xml << 'KODIEOF'
<sources>
    <programs>
        <default pathversion="1"/>
    </programs>
    <video>
        <default pathversion="1"/>
        <source>
            <name>IPTV</name>
            <path pathversion="1">pvr://pvr.iptvsimple/</path>
            <allowsharing>true</allowsharing>
        </source>
    </video>
</sources>
KODIEOF

cat > /home/ubuntu/.kodi/userdata/PVR.iptvsimple.xml << 'PVREOF'
<settings version="2">
    <setting id="m3uPathType" default="true">0</setting>
    <setting id="m3uUrl">https://live.fanmingming.com/tv/m3u/v6.m3u</setting>
    <setting id="m3uCache" default="true">true</setting>
    <setting id="startNum" default="true">1</setting>
    <setting id="numberByOrder" default="true">false</setting>
    <setting id="m3uRefreshMode" default="true">0</setting>
    <setting id="m3uRefreshIntervalMins" default="true">60</setting>
    <setting id="m3uRefreshHour" default="true">4</setting>
</settings>
PVREOF

chown -R ubuntu:ubuntu /home/ubuntu/.kodi

cat > /etc/systemd/system/kodi.service << 'SERVICEEOF'
[Unit]
Description=Kodi Media Center
After=network.target NetworkManager.service
Wants=NetworkManager.service

[Service]
User=ubuntu
Group=ubuntu
PAMName=login
Type=simple
ExecStart=/usr/bin/kodi-standalone
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable kodi.service 2>/dev/null || true
systemctl enable bluetooth 2>/dev/null || true

echo ""
echo "[6/6] Final cleanup..."
apt-get autoremove --purge -y 2>/dev/null || true
apt-get clean
rm -rf /var/cache/apt/archives/*.deb
rm -rf /tmp/*

echo ""
echo "============================================"
echo "  On-device modification complete!"
echo "============================================"
echo ""
echo "Summary:"
echo "  - Removed: Samba, Transmission"
echo "  - Added: X11, Kodi (with IPTV), Bluetooth"
echo "  - GPU: Mali-450 X11 config"
echo "  - IR: Already built-in to kernel"
echo ""
echo "Disk usage after modification:"
df -h /
echo ""
echo "Next steps:"
echo "  1. reboot"
echo "  2. Kodi will auto-start after login"
echo "  3. For Bluetooth: plug USB adapter, then pair via bluetoothctl"
echo "  4. For IR: should work automatically (hix5hd2-ir built-in)"
echo ""
echo "Log saved to: $LOG_FILE"
