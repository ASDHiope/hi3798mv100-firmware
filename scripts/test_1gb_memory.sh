#!/bin/bash
echo "=== Hi3798MV100 1GB Memory Test ==="
echo ""
echo "[1] Current memory info:"
cat /proc/meminfo | head -3
echo ""

echo "[2] Kernel command line:"
cat /proc/cmdline
echo ""

echo "[3] Testing high memory (0x20000000+) using /dev/mem:"
if [ -e /dev/mem ]; then
    echo "  Reading from 0x20000000 (512MB boundary)..."
    HEX=$(dd if=/dev/mem bs=4 count=1 skip=$((0x20000000/4)) 2>/dev/null | od -An -tx4 | tr -d ' ')
    if [ -n "$HEX" ]; then
        echo "  ✅ SUCCESS: Read value 0x$HEX from 0x20000000"
        echo "  High memory is ACCESSIBLE!"
    else
        echo "  ❌ FAIL: Cannot read from 0x20000000"
    fi
    
    echo ""
    echo "  Reading from 0x3FFFFFFF (1GB boundary)..."
    HEX=$(dd if=/dev/mem bs=4 count=1 skip=$((0x3FFFFFFF/4)) 2>/dev/null | od -An -tx4 | tr -d ' ')
    if [ -n "$HEX" ]; then
        echo "  ✅ SUCCESS: Read value 0x$HEX from 0x3FFFFFFF"
    else
        echo "  ❌ FAIL: Cannot read from 0x3FFFFFFF"
    fi
else
    echo "  /dev/mem not available"
fi

echo ""
echo "[4] Alternative test using hexdump:"
if command -v hexdump &> /dev/null; then
    echo "  Testing 0x20000000..."
    hexdump -C -n 16 -s $((0x20000000)) /dev/mem 2>/dev/null && echo "  ✅ Accessible" || echo "  ❌ Not accessible"
else
    echo "  hexdump not installed"
fi

echo ""
echo "============================================"
echo "  Test Complete!"
echo "============================================"
echo ""
echo "  If high memory (0x20000000+) is accessible:"
echo "  → DDR hardware is 1GB, just need to change bootargs"
echo "  → In U-Boot: setenv bootargs ... mem=1G mmz=ddr,0,0,60M ..."
echo ""
echo "  If high memory is NOT accessible:"
echo "  → DDR only initialized 512MB in fastboot"
echo "  → Need to rebuild fastboot with 1GB DDR reg file"
echo "  → Or flash bootargs_1g.bin from CI artifact"
