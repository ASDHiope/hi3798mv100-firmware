#!/bin/bash
set -e

FIRMWARE_DIR="${1:?Usage: $0 <firmware_output_dir>}"

if [ ! -d "$FIRMWARE_DIR" ]; then
    echo "ERROR: Directory not found: $FIRMWARE_DIR"
    exit 1
fi

echo "============================================"
echo "  Hi3798MV100 Firmware Packaging Script"
echo "============================================"
echo ""

KERNEL="${FIRMWARE_DIR}/hi_kernel_new.bin"
ROOTFS="${FIRMWARE_DIR}/backup-32.raw"

if [ ! -f "$KERNEL" ]; then
    echo "Warning: Kernel image not found, skipping kernel packaging"
fi

if [ ! -f "$ROOTFS" ]; then
    echo "Warning: Rootfs image not found, skipping rootfs packaging"
fi

echo "[1/3] Compressing rootfs image..."
if [ -f "$ROOTFS" ]; then
    e2fsck -fy "$ROOTFS" || true
    resize2fs -M "$ROOTFS" 2>/dev/null || true
    gzip -k -f "$ROOTFS"
    echo "  Compressed: $(du -h ${ROOTFS}.gz | cut -f1)"
fi

echo ""
echo "[2/3] Creating sparse image from rootfs..."
if [ -f "$ROOTFS" ]; then
    if command -v img2simg &>/dev/null; then
        img2simg "$ROOTFS" "${FIRMWARE_DIR}/www_ecoo_top_new.ext4" 2>/dev/null || {
            echo "  img2simg failed, using raw ext4"
            cp "$ROOTFS" "${FIRMWARE_DIR}/www_ecoo_top_new.ext4"
        }
    else
        echo "  img2simg not available, using raw ext4"
        cp "$ROOTFS" "${FIRMWARE_DIR}/www_ecoo_top_new.ext4"
    fi
fi

echo ""
echo "[3/3] Creating flash package..."
cat > "${FIRMWARE_DIR}/flash_instructions.txt" << 'EOF'
Hi3798MV100 Custom Firmware Flash Guide
========================================

Partition Table:
  mmcblk0p1: boot       (1MB)   - fastboot.bin
  mmcblk0p2: bootargs   (1MB)   - bootargs.bin
  mmcblk0p3: baseparam  (4MB)   - baseparam.img
  mmcblk0p4: pqparam    (4MB)   - pq_param.bin
  mmcblk0p5: logo       (4MB)   - logo.img
  mmcblk0p6: kernel     (20MB)  - hi_kernel.bin
  mmcblk0p7: busybox    (64MB)  - recoverybox32.ext4
  mmcblk0p8: backup     (512MB) - www_ecoo_top.ext4
  mmcblk0p9: ubuntu     (rest)  - rootfs (actual root)

Flash via U-Boot TFTP:
  1. Set up TFTP server with firmware files
  2. Enter U-Boot console (press Ctrl+C during boot)
  3. Run:
     setenv serverip <TFTP_SERVER_IP>
     setenv ipaddr <DEVICE_IP>
     tftp 0x02000000 hi_kernel_new.bin
     mmc write 0x02000000 0x800 0xA000
     reset

Flash via Linux (on device):
  dd if=hi_kernel_new.bin of=/dev/mmcblk0p6
  dd if=bootargs_1g.bin of=/dev/mmcblk0p2
  reboot

Flash rootfs (on device):
  dd if=backup-32.raw of=/dev/mmcblk0p9
  resize2fs /dev/mmcblk0p9
  reboot

OR use the backup partition method:
  dd if=www_ecoo_top_new.ext4 of=/dev/mmcblk0p8
  (then use recovery to restore)

Important:
  - Always backup original firmware before flashing!
  - Kernel load address: 0x02000000
  - Boot args: mem=1G mmz=ddr,0,0,60M console=ttyAMA0,115200
  - Root: /dev/mmcblk0p9 ext4
EOF

echo ""
echo "============================================"
echo "  Packaging complete!"
echo "============================================"
echo ""
echo "Output files:"
ls -lh "$FIRMWARE_DIR/"
