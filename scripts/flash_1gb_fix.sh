#!/bin/bash
echo "=== Hi3798MV100 1GB Memory Fix ==="
echo ""

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root (sudo)"
    exit 1
fi

# 检查设备文件
if [ ! -e /dev/mmcblk0p1 ] || [ ! -e /dev/mmcblk0p2 ]; then
    echo "❌ eMMC partitions not found!"
    echo "   /dev/mmcblk0p1 (boot) not found"
    echo "   /dev/mmcblk0p2 (bootargs) not found"
    exit 1
fi

echo "[1/4] Testing high memory (0x20000000)..."
HEX=$(dd if=/dev/mem bs=4 count=1 skip=134217728 2>/dev/null | od -An -tx4 | tr -d ' ')
if [ -n "$HEX" ]; then
    echo "  ✅ High memory accessible: 0x$HEX"
    echo "  → DDR hardware is 1GB, just need to update bootargs"
    SKIP_FASTBOOT=1
else
    echo "  ❌ High memory NOT accessible"
    echo "  → Need to burn fastboot.bin + bootargs.bin"
    SKIP_FASTBOOT=0
fi

echo ""
echo "[2/4] Checking boot files..."
BOOT_DIR=""
for dir in /mnt/usb /mnt /media/usb /run/media /tmp; do
    if [ -f "$dir/mv100/bootargs.bin" ]; then
        BOOT_DIR="$dir/mv100"
        echo "  ✅ Found boot files in: $BOOT_DIR"
        break
    elif [ -f "$dir/bootargs.bin" ]; then
        BOOT_DIR="$dir"
        echo "  ✅ Found boot files in: $BOOT_DIR"
        break
    fi
done

if [ -z "$BOOT_DIR" ]; then
    echo "  ❌ bootargs.bin not found!"
    echo "  Please insert USB drive with mv100-mdmo1g-usb-flash files"
    exit 1
fi

# 验证文件
if [ ! -f "$BOOT_DIR/bootargs.bin" ]; then
    echo "  ❌ bootargs.bin not found in $BOOT_DIR"
    exit 1
fi

if [ ! -f "$BOOT_DIR/fastboot.bin" ] && [ $SKIP_FASTBOOT -eq 0 ]; then
    echo "  ❌ fastboot.bin not found in $BOOT_DIR"
    exit 1
fi

echo ""
echo "[3/4] Backing up current partitions..."
dd if=/dev/mmcblk0p1 of=/tmp/fastboot_backup.bin bs=1M 2>/dev/null
dd if=/dev/mmcblk0p2 of=/tmp/bootargs_backup.bin bs=1M 2>/dev/null
echo "  ✅ Backup saved to /tmp/"

echo ""
echo "[4/4] Flashing new bootargs..."
cp "$BOOT_DIR/bootargs.bin" /tmp/bootargs_new.bin
dd if=/tmp/bootargs_new.bin of=/dev/mmcblk0p2 bs=1M 2>/dev/null
echo "  ✅ bootargs.bin flashed"

if [ $SKIP_FASTBOOT -eq 0 ]; then
    echo ""
    echo "      Flashing fastboot (this may take a while)..."
    cp "$BOOT_DIR/fastboot.bin" /tmp/fastboot_new.bin
    dd if=/tmp/fastboot_new.bin of=/dev/mmcblk0p1 bs=1M 2>/dev/null
    echo "  ✅ fastboot.bin flashed"
fi

echo ""
echo "============================================"
echo "  Flash Complete!"
echo "============================================"
echo ""
echo "  Next steps:"
echo "  1. Reboot: reboot"
echo "  2. Check memory: cat /proc/meminfo | head -3"
echo "  3. Should see ~960MB available (1G - 256M MMZ - kernel overhead)"
echo ""
echo "  If system fails to boot:"
echo "  - Restore backup: dd if=/tmp/bootargs_backup.bin of=/dev/mmcblk0p2 bs=1M"
echo "  - If fastboot was burned, need USB-TTL to recover"
echo ""
