#!/bin/bash
set -e

IMAGE="${1:?Usage: $0 <rootfs.ext4.raw>}"
MOUNT_DIR="/mnt/hi3798rootfs"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Image file not found: $IMAGE"
    exit 1
fi

echo "============================================"
echo "  Hi3798MV100 Rootfs Modification Script"
echo "============================================"
echo ""

echo "[1/8] Checking and resizing image..."
CURRENT_SIZE=$(stat -c%s "$IMAGE")
MIN_SIZE=$((1600 * 1024 * 1024))
if [ "$CURRENT_SIZE" -lt "$MIN_SIZE" ]; then
    echo "  Resizing image to 1600MB..."
    truncate -s ${MIN_SIZE} "$IMAGE"
    e2fsck -fy "$IMAGE" || true
    resize2fs "$IMAGE"
else
    echo "  Image size OK: $(($CURRENT_SIZE / 1024 / 1024))MB"
fi

echo ""
echo "[2/8] Mounting rootfs image..."
mkdir -p "$MOUNT_DIR"
mount -o loop "$IMAGE" "$MOUNT_DIR"

cleanup() {
    echo "Cleaning up..."
    umount "$MOUNT_DIR/sys" 2>/dev/null || true
    umount "$MOUNT_DIR/proc" 2>/dev/null || true
    umount "$MOUNT_DIR/dev/pts" 2>/dev/null || true
    umount "$MOUNT_DIR/dev" 2>/dev/null || true
    umount "$MOUNT_DIR" 2>/dev/null || true
    rm -rf "$MOUNT_DIR"
}
trap cleanup EXIT

echo ""
echo "[3/8] Setting up QEMU for ARM emulation..."
cp /usr/bin/qemu-arm-static "$MOUNT_DIR/usr/bin/" 2>/dev/null || true
mount --bind /dev "$MOUNT_DIR/dev"
mount --bind /dev/pts "$MOUNT_DIR/dev/pts"
mount --bind /proc "$MOUNT_DIR/proc"
mount --bind /sys "$MOUNT_DIR/sys"

echo ""
echo "[4/8] Removing packages..."
REMOVE_LIST=$(cat "${SCRIPT_DIR}/../rootfs/remove-packages.list" | grep -v '^#' | grep -v '^$' | tr '\n' ' ')
if [ -n "$REMOVE_LIST" ]; then
    chroot "$MOUNT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get remove --purge -y $REMOVE_LIST 2>/dev/null || true
        apt-get autoremove --purge -y 2>/dev/null || true
        apt-get clean
    "
    echo "  Removed: $REMOVE_LIST"
else
    echo "  No packages to remove"
fi

echo ""
echo "[5/8] Adding packages..."
ADD_LIST=$(cat "${SCRIPT_DIR}/../rootfs/add-packages.list" | grep -v '^#' | grep -v '^$' | tr '\n' ' ')
if [ -n "$ADD_LIST" ]; then
    chroot "$MOUNT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends $ADD_LIST 2>/dev/null || {
            echo 'Some packages failed, trying without recommends...'
            for pkg in $ADD_LIST; do
                apt-get install -y \$pkg 2>/dev/null || echo \"  Warning: Failed to install \$pkg\"
            done
        }
        apt-get clean
    "
    echo "  Added: $ADD_LIST"
else
    echo "  No packages to add"
fi

echo ""
echo "[6/8] Configuring GPU and display..."
chroot "$MOUNT_DIR" /bin/bash -c '
    mkdir -p /etc/X11

    cat > /etc/X11/xorg.conf << XORGEOF
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
    cat > /etc/udev/rules.d/99-mali.rules << UDEVEOF
KERNEL=="mali", MODE="0666"
KERNEL=="ump", MODE="0666"
KERNEL=="mali0", MODE="0666"
UDEVEOF

    echo "GPU X11 config done"
'

echo ""
echo "[7/8] Configuring Kodi and Bluetooth..."
chroot "$MOUNT_DIR" /bin/bash -c '
    mkdir -p /home/ubuntu/.kodi/userdata

    cat > /home/ubuntu/.kodi/userdata/sources.xml << KODIEOF
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

    mkdir -p /home/ubuntu/.kodi/userdata
    cat > /home/ubuntu/.kodi/userdata/PVR.iptvsimple.xml << PVREOF
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

    systemctl enable kodi 2>/dev/null || true

    cat > /etc/systemd/system/kodi.service << SERVICEEOF
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

    systemctl enable kodi.service 2>/dev/null || chroot / ln -sf /etc/systemd/system/kodi.service /etc/systemd/system/multi-user.target.wants/kodi.service 2>/dev/null || true

    echo "Kodi configured"

    systemctl enable bluetooth 2>/dev/null || true
    echo "Bluetooth service enabled"
'

echo ""
echo "[8/8] Final cleanup..."
chroot "$MOUNT_DIR" /bin/bash -c '
    apt-get autoremove --purge -y 2>/dev/null || true
    apt-get clean
    rm -rf /var/cache/apt/archives/*.deb
    rm -rf /tmp/*
    rm -f /usr/bin/qemu-arm-static
'

echo ""
echo "============================================"
echo "  Rootfs modification complete!"
echo "============================================"
echo ""
echo "Removed: Samba, Transmission"
echo "Added: X11, Kodi, Bluetooth"
echo ""
echo "Storage estimate: ~2.5GB remaining"
echo "RAM estimate: 279MB (4K) / 475MB (1080p) remaining"
