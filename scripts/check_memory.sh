#!/bin/bash
echo "=== Hi3798MV100 Memory Diagnostic ==="

echo "[1] Current memory info:"
cat /proc/meminfo | head -5

echo ""
echo "[2] Kernel command line:"
cat /proc/cmdline

echo ""
echo "[3] Kernel memory detection:"
dmesg | grep -i "Memory:" 2>/dev/null || echo "Not found in dmesg"

echo ""
echo "[4] Physical memory map:"
dmesg | grep -i "lowmem\|vmalloc\|pkmap\|modules" 2>/dev/null || echo "Not found"

echo ""
echo "[5] CMA reserved:"
dmesg | grep -i "cma:" 2>/dev/null || echo "Not found"

echo ""
echo "[6] MMZ info:"
cat /proc/media-mem 2>/dev/null || echo "/proc/media-mem not available"
cat /proc/umap/vb 2>/dev/null || echo "/proc/umap/vb not available"

echo ""
echo "[7] DDR register file (from U-Boot):"
dmesg | grep -i "Reg Name\|DDR Size\|Reg Version" 2>/dev/null || echo "Not found in dmesg"

echo ""
echo "[8] Testing high memory access (0x20000000+):"
if [ -e /dev/mem ]; then
    echo "  /dev/mem exists, testing read..."
    dd if=/dev/mem bs=4 count=1 skip=$((0x20000000/4)) 2>/dev/null | hexdump -C | head -1 && echo "  ✅ High memory accessible!" || echo "  ❌ High memory NOT accessible"
else
    echo "  /dev/mem not available, trying alternative..."
    devmem 0x20000000 2>/dev/null && echo "  ✅ High memory accessible!" || echo "  ❌ High memory NOT accessible (or devmem not installed)"
fi

echo ""
echo "[9] eMMC partitions:"
ls -la /dev/mmcblk0p* 2>/dev/null || echo "No eMMC partitions found"

echo ""
echo "[10] Bootargs partition content:"
dd if=/dev/mmcblk0p2 bs=512 count=2048 2>/dev/null | strings | head -5

echo ""
echo "[11] Baseparam partition content:"
dd if=/dev/mmcblk0p3 bs=512 count=2048 2>/dev/null | strings | grep -i "mem=\|mmz=" | head -5

echo ""
echo "============================================"
echo "  Diagnostic Complete!"
echo "============================================"
echo ""
echo "  If DDR Size is 512MB but hardware has 1GB:"
echo "  1. Try in U-Boot: setenv bootargs ... mem=1G mmz=ddr,0,0,60M ..."
echo "  2. If mem=1G causes crash, need to rebuild fastboot with 1GB DDR reg"
echo "  3. If high memory test passes, mem=1G should work"
