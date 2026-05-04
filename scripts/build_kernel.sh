#!/bin/bash
set -e

echo "============================================"
echo "  Hi3798MV100 Kernel Build Script (CI)"
echo "============================================"

WORKDIR="${1:-$PWD/HiSTBLinuxV100R005C00SPC060}"
SDK_REPO="${SDK_REPO:-https://gitee.com/lh736/HiSTBLinuxV100R005C00SPC060.git}"
SDK_REPO_FALLBACK="https://github.com/wdznb/EC6108V9C_HiSTBLinuxV100R005C00SPC060.git"
CROSS_COMPILE="arm-linux-gnueabihf-"
DTS_SOURCE="${DTS_SOURCE:-dts/hi3798mv100.dts}"

echo "[1/6] Installing build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential gcc-arm-linux-gnueabihf \
    binutils-arm-linux-gnueabihf cpp-arm-linux-gnueabihf \
    make gettext bison flex bc zlib1g-dev libncurses5-dev \
    lzma u-boot-tools device-tree-compiler git cpio \
    python3 python3-pyelftools libssl-dev wget

echo ""
echo "[2/6] Cloning HiSTBLinux SDK..."
if [ -d "$WORKDIR" ]; then
    echo "  SDK directory exists, skipping clone"
else
    git clone --depth 1 "$SDK_REPO" "$WORKDIR" || {
        echo "  Gitee clone failed, trying GitHub mirror..."
        git clone --depth 1 "$SDK_REPO_FALLBACK" "$WORKDIR"
    }
fi

echo ""
echo "[3/6] Fixing SDK missing files..."
KERNEL_VERSION="4.4.35"
SDK_KERNEL="${WORKDIR}/source/kernel/linux-4.4.y"

if [ ! -d "${SDK_KERNEL}/scripts/basic" ] || [ ! -d "${SDK_KERNEL}/scripts/kconfig" ]; then
    echo "  Downloading Linux ${KERNEL_VERSION} for missing scripts..."
    cd /tmp
    wget -q "https://mirrors.edge.kernel.org/pub/linux/kernel/v4.x/linux-${KERNEL_VERSION}.tar.gz"
    tar xzf "linux-${KERNEL_VERSION}.tar.gz"
    [ ! -d "${SDK_KERNEL}/scripts/basic" ] && cp -r "linux-${KERNEL_VERSION}/scripts/basic/" "${SDK_KERNEL}/scripts/"
    [ ! -d "${SDK_KERNEL}/scripts/kconfig" ] && cp -r "linux-${KERNEL_VERSION}/scripts/kconfig/" "${SDK_KERNEL}/scripts/"
    cd -
fi

echo ""
echo "[4/6] Copying custom DTS..."
if [ -f "$DTS_SOURCE" ]; then
    DTS_DIR="${SDK_KERNEL}/arch/arm/boot/dts"
    cp "$DTS_SOURCE" "${DTS_DIR}/"
    if ! grep -q "hi3798mv100.dts" "${DTS_DIR}/Makefile" 2>/dev/null; then
        echo "dtb-\$(CONFIG_ARCH_HI3798MV100) += hi3798mv100.dtb" >> "${DTS_DIR}/Makefile"
    fi
    echo "  Custom DTS installed"
else
    echo "  No custom DTS found, using SDK default"
fi

echo ""
echo "[5/6] Configuring SDK..."
cd "$WORKDIR"
if [ ! -f "cfg.mak" ]; then
    cp configs/hi3798mv100/hi3798mdmo1g_hi3798mv100_cfg.mak cfg.mak
    echo "  Configured for hi3798mdmo1g (1GB RAM)"
fi

echo ""
echo "[6/6] Building kernel..."
source env.sh
make linux -j$(nproc)

echo ""
echo "Build complete!"
echo "Output:"
find out/ -name "hi_kernel*" -type f 2>/dev/null | while read f; do
    echo "  $f ($(du -h "$f" | cut -f1))"
done
