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
echo "  (All-in-one fix v2 - comprehensive)"
echo "============================================"
echo ""

echo "[1/14] Checking and resizing image..."
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
echo "[2/14] Mounting rootfs image..."
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
echo "[3/14] Setting up QEMU for ARM emulation..."
cp /usr/bin/qemu-arm-static "$MOUNT_DIR/usr/bin/" 2>/dev/null || true
mount --bind /dev "$MOUNT_DIR/dev"
mount --bind /dev/pts "$MOUNT_DIR/dev/pts"
mount --bind /proc "$MOUNT_DIR/proc"
mount --bind /sys "$MOUNT_DIR/sys"

echo ""
echo "[4/14] NUKING ALL swap services and files..."
chroot "$MOUNT_DIR" /bin/bash -c '
    echo "  Finding ALL swap-related systemd units..."
    find /etc/systemd /usr/lib/systemd /lib/systemd -name "*swap*" -o -name "*swapfile*" 2>/dev/null | while read f; do
        echo "    FOUND: $f"
    done

    echo "  Masking ALL possible swap service names..."
    for svc in create-swapfile.service swap-create.service swapfile.service \
               create-swapfile.service swapfile.swap dev-swapfile.swap \
               systemd-swap.service swap.target; do
        ln -sf /dev/null /etc/systemd/system/$svc 2>/dev/null && echo "    Masked: $svc" || true
    done

    echo "  Removing ALL swap unit files from systemd dirs..."
    find /etc/systemd /usr/lib/systemd /lib/systemd -name "*swap*" -type f -delete 2>/dev/null || true
    find /etc/systemd /usr/lib/systemd /lib/systemd -name "*swap*" -type l -delete 2>/dev/null || true

    echo "  Removing ALL swap symlinks from target dirs..."
    find /etc/systemd/system -name "*.wants" -type d -exec sh -c "rm -f {}/*swap* {}/*swapfile*" \; 2>/dev/null || true
    find /etc/systemd/system -name "*.requires" -type d -exec sh -c "rm -f {}/*swap* {}/*swapfile*" \; 2>/dev/null || true

    echo "  Cleaning fstab..."
    sed -i "/swap/d" /etc/fstab
    sed -i "/swapfile/d" /etc/fstab

    echo "  Removing swap file..."
    rm -f /swapfile

    echo "  Disabling swap in kernel modules..."
    echo "install swap /bin/true" > /etc/modprobe.d/noswap.conf 2>/dev/null || true

    echo "  ALL swap services NUKE complete"
'

echo ""
echo "[5/14] Removing packages..."
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
echo "[6/14] Adding packages..."
ADD_LIST=$(cat "${SCRIPT_DIR}/../rootfs/add-packages.list" | grep -v '^#' | grep -v '^$' | tr '\n' ' ')
if [ -n "$ADD_LIST" ]; then
    chroot "$MOUNT_DIR" /bin/bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y --no-install-recommends $ADD_LIST 2>/dev/null || {
            echo 'Some packages failed, trying individually...'
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
echo "[7/14] Fixing DNS and network..."
chroot "$MOUNT_DIR" /bin/bash -c '
    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf << DNSEOF
nameserver 223.5.5.5
nameserver 119.29.29.29
DNSEOF
    chattr +i /etc/resolv.conf 2>/dev/null || true

    grep -q huaweicloud /etc/hosts || echo "120.226.22.165 repo.huaweicloud.com" >> /etc/hosts

    cat > /etc/network/interfaces.d/eth0 << NETEOF
auto eth0
iface eth0 inet dhcp
    dns-nameservers 223.5.5.5 119.29.29.29
NETEOF
    echo "  DNS and network configured"
'

echo ""
echo "[8/14] Fixing apt seccomp sandbox..."
chroot "$MOUNT_DIR" /bin/bash -c '
    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/99no-seccomp << APTEOF
APT::Sandbox::Seccomp "false";
APT::Sandbox::User "root";
APTEOF
    echo "  Apt seccomp sandbox disabled"
'

echo ""
echo "[9/14] Installing display driver loading service..."
chroot "$MOUNT_DIR" /bin/bash -c '
    KO_PATH="/lib/modules/4.4.35_ecoo_81082668/kernel/drivers/hisilicon"

    mkdir -p /opt/hisilicon/bin
    mkdir -p /opt/hisilicon/lib

    cat > /opt/hisilicon/bin/load_drivers.sh << DREOF
#!/bin/sh
KO=/lib/modules/4.4.35_ecoo_81082668/kernel/drivers/hisilicon
[ -d /lib/modules/4.9.37+hi3798mv100 ] && KO=/lib/modules/4.9.37+hi3798mv100/kernel/drivers/hisi
[ -d /lib/modules/4.4.35_ecoo_81082668/kernel/drivers/hisilicon ] && KO=/lib/modules/4.4.35_ecoo_81082668/kernel/drivers/hisilicon

echo "Loading display drivers from \$KO ..."
for mod in hi_media hi_mmz hi_common hi_pdm hi_pq hi_hdmi hi_vou hi_fb hi_tde; do
    EXTRA=""
    [ "\$mod" = "hi_mmz" ] && EXTRA=" mmz=ddr,0,0,60M"
    [ "\$mod" = "hi_fb" ] && EXTRA=" video=hifb:vram0_size:1620"
    if [ -f "\$KO/\${mod}.ko" ]; then
        insmod \$KO/\${mod}.ko\$EXTRA 2>/dev/null && echo "  \$mod OK" || echo "  \$mod FAIL"
    else
        echo "  \$mod not found"
    fi
done

if [ -f "\$KO/mali.ko" ]; then
    insmod \$KO/mali.ko 2>/dev/null && echo "  mali OK" || echo "  mali FAIL"
fi

echo "Loading USB drivers..."
USB_KO=/lib/modules/\$(uname -r)/kernel/drivers/usb/host
for usb_mod in ehci-platform ohci-platform xhci-plat-hcd; do
    if [ -f "\$USB_KO/\${usb_mod}.ko" ]; then
        insmod \$USB_KO/\${usb_mod}.ko 2>/dev/null && echo "  \$usb_mod OK" || echo "  \$usb_mod FAIL"
    fi
done

sleep 2

echo "Initializing framebuffer to 1080P..."
python3 /opt/hisilicon/bin/fb_init.py 2>/dev/null || echo "  fb_init failed"

echo "All drivers loaded."
DREOF
    chmod +x /opt/hisilicon/bin/load_drivers.sh

    cat > /etc/systemd/system/hisi-display.service << SVCEOF
[Unit]
Description=Load Hi3798MV100 Display Drivers
After=local-fs.target
Before=graphical.target kodi.service

[Service]
Type=oneshot
ExecStart=/opt/hisilicon/bin/load_drivers.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

    ln -sf /etc/systemd/system/hisi-display.service /etc/systemd/system/multi-user.target.wants/hisi-display.service 2>/dev/null || true

    echo "  Display driver service installed"
'

echo ""
echo "[10/14] Installing framebuffer init script..."
chroot "$MOUNT_DIR" /bin/bash -c '
    cat > /opt/hisilicon/bin/fb_init.py << PYEOF
import struct, fcntl, os, sys

FBIOGET_VSCREENINFO = 0x4600
FBIOPUT_VSCREENINFO = 0x4601

try:
    fb = os.open("/dev/fb0", os.O_RDWR)
except OSError as e:
    print("Cannot open /dev/fb0: %s" % e)
    sys.exit(0)

try:
    var_info = bytearray(160)
    fcntl.ioctl(fb, FBIOGET_VSCREENINFO, var_info)
    xres = struct.unpack_from("I", var_info, 0)[0]
    yres = struct.unpack_from("I", var_info, 4)[0]
    bpp = struct.unpack_from("I", var_info, 24)[0]
    print("Current fb0: %dx%d %dbpp" % (xres, yres, bpp))

    if xres == 0 or yres == 0:
        struct.pack_into("I", var_info, 0, 1920)
        struct.pack_into("I", var_info, 4, 1080)
        struct.pack_into("I", var_info, 8, 1920)
        struct.pack_into("I", var_info, 24, 32)
        ret = fcntl.ioctl(fb, FBIOPUT_VSCREENINFO, var_info)
        print("FBIOPUT_VSCREENINFO ret=%d" % ret)

        var_info2 = bytearray(160)
        fcntl.ioctl(fb, FBIOGET_VSCREENINFO, var_info2)
        xres2 = struct.unpack_from("I", var_info2, 0)[0]
        yres2 = struct.unpack_from("I", var_info2, 4)[0]
        bpp2 = struct.unpack_from("I", var_info2, 24)[0]
        print("After init: %dx%d %dbpp" % (xres2, yres2, bpp2))
    else:
        print("Framebuffer already configured")
except Exception as e:
    print("fb_init error: %s" % e)
finally:
    os.close(fb)
PYEOF
    chmod +x /opt/hisilicon/bin/fb_init.py
    echo "  Framebuffer init script installed"
'

echo ""
echo "[11/14] Configuring GPU, X11, Kodi and Bluetooth..."
chroot "$MOUNT_DIR" /bin/bash -c '
    mkdir -p /etc/X11

    cat > /etc/X11/xorg.conf << XORGEOF
Section "Device"
    Identifier  "HiSilicon FBDev"
    Driver      "fbdev"
    Option      "fbdev"            "/dev/fb0"
EndSection

Section "Screen"
    Identifier  "Default Screen"
    Device      "HiSilicon FBDev"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080" "1280x720"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier  "Default Layout"
    Screen      "Default Screen"
EndSection
XORGEOF

    mkdir -p /etc/udev/rules.d
    cat > /etc/udev/rules.d/99-mali.rules << UDEVEOF
KERNEL=="mali", MODE="0666"
KERNEL=="ump", MODE="0666"
KERNEL=="mali0", MODE="0666"
UDEVEOF

    cat > /etc/udev/rules.d/99-fbdev.rules << UDEVEOF2
KERNEL=="fb0", MODE="0666"
KERNEL=="fb1", MODE="0666"
UDEVEOF2

    cat > /etc/udev/rules.d/99-usb.rules << UDEVEOF3
SUBSYSTEM=="usb", MODE="0666"
KERNEL=="hidraw*", MODE="0666"
KERNEL=="usbdev*", MODE="0666"
ACTION=="add", SUBSYSTEM=="usb", RUN+="/bin/chmod 0666 %S%p"
UDEVEOF3

    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/hi3798-usb-blacklist.conf << BLEOF
blacklist hiusbotg
blacklist hiudc
BLEOF

    echo "  USB blacklist and udev rules configured"

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

    cat > /etc/systemd/system/kodi.service << SERVICEEOF
[Unit]
Description=Kodi Media Center
After=hisi-display.service network.target
Wants=hisi-display.service

[Service]
User=ubuntu
Group=ubuntu
PAMName=login
Type=simple
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/kodi-standalone
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

    ln -sf /etc/systemd/system/kodi.service /etc/systemd/system/multi-user.target.wants/kodi.service 2>/dev/null || true

    systemctl enable bluetooth 2>/dev/null || true

    echo "  X11, Kodi, Bluetooth configured"
'

echo ""
echo "[12/14] Creating emergency swap-killer service..."
chroot "$MOUNT_DIR" /bin/bash -c '
    cat > /opt/hisilicon/bin/kill_swap.sh << KSEOF
#!/bin/sh
echo "=== Emergency Swap Killer ==="
swapoff -a 2>/dev/null || true
rm -f /swapfile 2>/dev/null || true

for svc in create-swapfile.service swap-create.service swapfile.service \
           create_swapfile.service swapfile.swap dev-swapfile.swap \
           systemd-swap.service; do
    ln -sf /dev/null /etc/systemd/system/$svc 2>/dev/null
done

find /etc/systemd /usr/lib/systemd /lib/systemd -name "*swap*" -type f -delete 2>/dev/null || true
find /etc/systemd /usr/lib/systemd /lib/systemd -name "*swap*" -type l -delete 2>/dev/null || true
find /etc/systemd/system -name "*.wants" -type d -exec sh -c "rm -f {}/*swap* {}/*swapfile*" \; 2>/dev/null || true
find /etc/systemd/system -name "*.requires" -type d -exec sh -c "rm -f {}/*swap* {}/*swapfile*" \; 2>/dev/null || true

sed -i "/swap/d" /etc/fstab
sed -i "/swapfile/d" /etc/fstab

echo "Swap killed."
KSEOF
    chmod +x /opt/hisilicon/bin/kill_swap.sh

    cat > /etc/systemd/system/kill-swap.service << KSSEOF
[Unit]
Description=Kill All Swap Services
DefaultDependencies=no
Before=local-fs.target
Before=swap.target
Before=create-swapfile.service
Before=swap-create.service
Before=swapfile.service
Conflicts=swap.target
Conflicts=create-swapfile.service
Conflicts=swap-create.service
Conflicts=swapfile.service

[Service]
Type=oneshot
ExecStart=/opt/hisilicon/bin/kill_swap.sh
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
KSSEOF

    ln -sf /etc/systemd/system/kill-swap.service /etc/systemd/system/sysinit.target.wants/kill-swap.service 2>/dev/null || true

    echo "  Emergency swap-killer service installed"
'

echo ""
echo "[13/14] Writing 1GB bootargs to image and final cleanup..."
chroot "$MOUNT_DIR" /bin/bash -c '
    apt-get autoremove --purge -y 2>/dev/null || true
    apt-get clean
    rm -rf /var/cache/apt/archives/*.deb
    rm -rf /tmp/*
    rm -f /usr/bin/qemu-arm-static

    cat > /opt/hisilicon/bin/write_bootargs.sh << BAEOF
#!/bin/sh
echo "Writing 1GB bootargs to eMMC bootargs partition..."
dd if=/dev/zero of=/dev/mmcblk0p2 bs=1M count=1 2>/dev/null
printf "model=mv100 console=ttyAMA0,115200 root=/dev/mmcblk0p9 rootfstype=ext4 rootwait rootflags=noload mem=1G mmz=ddr,0,0,60M vmalloc=500M systemd.mask=create-swapfile.service systemd.mask=swap-create.service systemd.mask=swapfile.service blkdevparts=mmcblk0:1M(boot),1M(bootargs),4M(baseparam),4M(pqparam),4M(logo),20M(kernel),64M(busybox),512M(backup),-(ubuntu)" | dd of=/dev/mmcblk0p2 bs=1 conv=notrunc 2>/dev/null
echo "Bootargs written. Rebooting..."
sync
reboot
BAEOF
    chmod +x /opt/hisilicon/bin/write_bootargs.sh
'

echo ""
echo "[14/14] Final verification - checking no swap services remain..."
chroot "$MOUNT_DIR" /bin/bash -c '
    echo "  Checking for remaining swap units..."
    FOUND=$(find /etc/systemd /usr/lib/systemd /lib/systemd -name "*swap*" 2>/dev/null | grep -v "/dev/null" | grep -v "kill-swap" | grep -v "noswap" || true)
    if [ -n "$FOUND" ]; then
        echo "  WARNING: Found swap units still present:"
        echo "$FOUND"
        echo "  Removing them..."
        echo "$FOUND" | while read f; do
            rm -f "$f" 2>/dev/null || true
        done
    else
        echo "  OK: No swap units found"
    fi

    echo "  Checking fstab for swap entries..."
    if grep -q swap /etc/fstab 2>/dev/null; then
        echo "  WARNING: fstab still has swap entries!"
        sed -i "/swap/d" /etc/fstab
    else
        echo "  OK: No swap entries in fstab"
    fi

    echo "  Checking for /swapfile..."
    if [ -f /swapfile ]; then
        echo "  WARNING: /swapfile still exists!"
        rm -f /swapfile
    else
        echo "  OK: No /swapfile"
    fi
'

echo ""
echo "============================================"
echo "  Rootfs modification complete!"
echo "============================================"
echo ""
echo "Fixes applied:"
echo "  1. ALL swap services NUKED (masked + deleted)"
echo "  2. Emergency swap-killer service (runs before everything)"
echo "  3. DNS configured (223.5.5.5 + 119.29.29.29)"
echo "  4. Network DHCP auto-config"
echo "  5. Apt seccomp sandbox DISABLED"
echo "  6. Display driver auto-load service"
echo "  7. Framebuffer init to 1080P"
echo "  8. X11 fbdev driver configured"
echo "  9. Kodi auto-start with display dependency"
echo "  10. Bluetooth enabled"
echo "  11. USB OTG blacklisted, host drivers loaded"
echo "  12. Bootargs with multi-service mask"
echo ""
echo "Removed: Samba, Transmission"
echo "Added: X11, Kodi, Bluetooth"
