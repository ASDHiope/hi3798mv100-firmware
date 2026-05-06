#!/bin/bash
echo "=== Hi3798MV100 Display Setup ==="

KVER=$(uname -r)
KO=/lib/modules/${KVER}/kernel/drivers/hisilicon
SRC=.

echo "[1/3] Installing SDK libraries..."
mkdir -p /opt/hisilicon/lib
cp ${SRC}/lib/*.so* /opt/hisilicon/lib/ 2>/dev/null || true
cp ${SRC}/lib/*.a /opt/hisilicon/lib/ 2>/dev/null || true
grep -q "/opt/hisilicon/lib" /etc/ld.so.conf 2>/dev/null || echo "/opt/hisilicon/lib" >> /etc/ld.so.conf
ldconfig

echo "[2/3] Loading driver modules..."
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
echo "  ⏭️  mali (skipped - causes kernel crash, not needed for display)"

echo "[3/3] Checking display..."
echo "  /proc/fb: $(cat /proc/fb 2>/dev/null)"
echo "  fb0 modes: $(cat /sys/class/graphics/fb0/modes 2>/dev/null)"
echo "  /dev/fb0: $(ls /dev/fb0 2>/dev/null)"

echo ""
echo "=== Done! Display should be working. ==="
