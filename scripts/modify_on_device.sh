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

echo "[0/9] Fixing APT cache..."
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -qq 2>/dev/null; then
    echo "  APT update failed, cleaning cache..."
    rm -rf /var/lib/apt/lists/*
    apt-get update -qq || {
        echo "  Still failing, trying to fix sources..."
        apt-get update --allow-releaseinfo-change 2>/dev/null || true
    }
fi
echo ""

echo "[1/9] Blacklisting HiSilicon modules and masking NFS services..."
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
blacklist hi_vdec
blacklist hi_venc
blacklist hi_vfmw
blacklist hi_omxvdec
blacklist hi_vi
blacklist hi_demux
blacklist hi_aiao
blacklist hi_adec
blacklist hi_aenc
blacklist hi_adsp
blacklist hi_cipher
blacklist hi_otp
blacklist hi_gpio
blacklist hi_gpio_i2c
blacklist hi_i2c
blacklist hi_ir
blacklist hi_pmoc
blacklist hi_pdm
blacklist hi_png
blacklist hi_jpeg
blacklist hi_jpge
blacklist hi_keyled
blacklist hi_mce
blacklist hi_dbe
blacklist hi_advca
blacklist ddr
blacklist mali
BLKEOF
echo "  Blacklisted all HiSilicon modules (prevent udev auto-loading)"

systemctl mask proc-fs-nfsd.mount 2>/dev/null || true
systemctl mask nfs-server.service 2>/dev/null || true
systemctl mask nfs-idmapd.service 2>/dev/null || true
systemctl mask nfs-mountd.service 2>/dev/null || true
systemctl mask nfs-blkmap.service 2>/dev/null || true
echo "  Masked NFS services (kernel has no NFSD support)"
echo ""

echo "[2/9] Installing HiSilicon kernel modules..."
KVER=$(uname -r)
KO_SRC="${SCRIPT_DIR}/kmodules"
KO_DST="/lib/modules/${KVER}/kernel/drivers/hisilicon"

if [ -d "$KO_SRC" ] && ls "$KO_SRC"/hi_*.ko "$KO_SRC"/mali.ko 2>/dev/null >/dev/null; then
    echo "  Found KO modules in ${KO_SRC}"
    mkdir -p "$KO_DST"

    for ko in "$KO_SRC"/*.ko; do
        [ -f "$ko" ] || continue
        echo "  Installing $(basename $ko)..."
        cp "$ko" "$KO_DST/"
    done

    echo "  Running depmod..."
    depmod -a "$KVER"

    echo "  Creating driver load script..."
    cat > /etc/init.d/hi3798mv100-drivers << 'DRIVEREOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          hi3798mv100-drivers
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Load HiSilicon display drivers
# Description:       Load HiSilicon KO modules in correct order.
#                    Must NOT use modprobe - order is critical.
### END INIT INFO

KVER=$(uname -r)
KO_DIR="/lib/modules/${KVER}/kernel/drivers/hisilicon"
LOG_TAG="hi3798-drivers"

log_info()  { echo "[${LOG_TAG}] $*"; }
log_warn()  { echo "[${LOG_TAG}] WARNING: $*"; }
log_error() { echo "[${LOG_TAG}] ERROR: $*" >&2; }

load_module() {
    local modname="$1"
    local modparams="$2"
    local modpath="${KO_DIR}/${modname}"

    if [ ! -f "${modpath}" ]; then
        log_warn "${modname} not found, skipping"
        return 0
    fi

    if lsmod | grep -q "^${modname%.ko}[[:space:]]"; then
        log_info "${modname} already loaded"
        return 0
    fi

    log_info "Loading ${modname} ${modparams}..."
    if insmod "${modpath}" ${modparams} 2>/dev/null; then
        log_info "${modname} loaded OK"
        return 0
    else
        local rc=$?
        log_error "${modname} failed to load (exit code: ${rc})"
        dmesg | tail -5 | while read line; do
            log_error "  dmesg: ${line}"
        done
        return 1
    fi
}

case "$1" in
    start)
        log_info "Loading HiSilicon drivers in strict order..."
        log_info "Kernel: ${KVER}, KO dir: ${KO_DIR}"

        ERRORS=0

        load_module hi_media.ko  || ERRORS=$((ERRORS+1))
        load_module hi_mmz.ko    || ERRORS=$((ERRORS+1))
        load_module hi_common.ko || ERRORS=$((ERRORS+1))

        if [ ${ERRORS} -gt 0 ]; then
            log_error "Critical modules (hi_media/hi_mmz/hi_common) failed, aborting"
            exit 1
        fi

        load_module hi_pdm.ko    || log_warn "hi_pdm failed (non-critical, display params may be default)"
        load_module hi_pq.ko     || log_warn "hi_pq failed"
        load_module hi_vou.ko    || log_warn "hi_vou failed"
        load_module hi_hdmi.ko   || log_warn "hi_hdmi failed"
        load_module hi_fb.ko     || log_warn "hi_fb failed"
        load_module hi_tde.ko    || log_warn "hi_tde failed"
        load_module hi_vpss.ko   || log_warn "hi_vpss failed"
        load_module hi_sync.ko   || log_warn "hi_sync failed"
        log_info "mali.ko skipped (causes kernel crash on Hi3798MV100, not needed for display)"

        if command -v hi_display_init >/dev/null 2>&1; then
            log_info "Initializing display via MPP API..."
            hi_display_init 1080p60 2>/dev/null && log_info "Display initialized (1080p60)" || {
                log_warn "1080p60 failed, trying 720p60..."
                hi_display_init 720p60 2>/dev/null && log_info "Display initialized (720p60)" || log_error "Display init failed"
            }
        else
            log_warn "hi_display_init not found - display will remain unconfigured"
        fi

        log_info "Module loading complete. Errors: ${ERRORS}"

        if [ -e /dev/fb0 ]; then
            log_info "Framebuffer /dev/fb0 OK"
        else
            log_warn "/dev/fb0 not found - display may not work"
        fi

        if [ -e /dev/mali ]; then
            log_info "GPU /dev/mali OK"
        else
            log_warn "/dev/mali not found - GPU may not work"
        fi
        ;;
    stop)
        log_info "Unloading HiSilicon drivers..."
        for m in hi_sync hi_vpss hi_tde hi_fb hi_hdmi hi_vou hi_pq hi_pdm hi_common hi_mmz hi_media; do
            if lsmod | grep -q "^${m}[[:space:]]"; then
                rmmod "${m}" 2>/dev/null && log_info "Unloaded ${m}" || log_warn "Failed to unload ${m}"
            fi
        done
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    status)
        log_info "Loaded HiSilicon modules:"
        lsmod | grep -E "^(hi_|mali)" || log_info "  (none)"
        if [ -e /dev/fb0 ]; then
            log_info "/dev/fb0: present"
        else
            log_info "/dev/fb0: absent"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
DRIVEREOF
    chmod +x /etc/init.d/hi3798mv100-drivers
    update-rc.d hi3798mv100-drivers defaults 2>/dev/null || true

    echo "  Loading drivers now..."
    /etc/init.d/hi3798mv100-drivers start

else
    echo "  WARNING: No KO modules found in ${KO_SRC}"
    echo "  Please download kmodules/ from CI artifact and place in ${KO_SRC}/"
fi
echo ""

echo "[3/9] Stopping Samba services..."
systemctl stop smbd nmbd samba-ad-dc 2>/dev/null || true
killall -9 smbd nmbd 2>/dev/null || true
echo "  Samba services stopped"
echo ""

echo "[4/9] Removing Samba and Transmission..."

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
echo "[5/9] Installing X11 and GPU support..."
PACKAGES_X11="xserver-xorg-core xserver-xorg-video-fbdev xserver-xorg-input-evdev xinit x11-utils x11-xserver-utils"

for pkg in $PACKAGES_X11; do
    echo "  Installing $pkg..."
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: Could not install $pkg"
done

echo ""
echo "[6/9] Installing Kodi..."
PACKAGES_KODI="kodi kodi-bin kodi-data kodi-repository-kodi kodi-inputstream-adaptive kodi-pvr-iptvsimple"

for pkg in $PACKAGES_KODI; do
    echo "  Installing $pkg..."
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: Could not install $pkg"
done

echo ""
echo "[7/9] Installing Bluetooth support..."
PACKAGES_BT="bluez bluez-firmware python3-dbus libbluetooth3 pulseaudio-module-bluetooth"

for pkg in $PACKAGES_BT; do
    echo "  Installing $pkg..."
    apt-get install -y --no-install-recommends "$pkg" 2>/dev/null || echo "  Warning: Could not install $pkg"
done

apt-get clean

echo ""
echo "[8/9] Configuring GPU, Kodi, and Bluetooth..."
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
After=network.target NetworkManager.service hi3798mv100-drivers.service
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
echo "[9/9] Final cleanup..."
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
echo "  - Blacklisted: HiSilicon modules (prevent auto-load)"
echo "  - Masked: NFS services (no kernel NFSD support)"
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
echo "  2. HiSilicon drivers will auto-load via init script"
echo "  3. Kodi will auto-start after login"
echo "  4. For Bluetooth: plug USB adapter, then pair via bluetoothctl"
echo "  5. For IR: should work automatically (hix5hd2-ir built-in)"
echo ""
echo "Driver management:"
echo "  /etc/init.d/hi3798mv100-drivers start   - load drivers"
echo "  /etc/init.d/hi3798mv100-drivers stop    - unload drivers"
echo "  /etc/init.d/hi3798mv100-drivers status  - check driver status"
echo ""
echo "Log saved to: $LOG_FILE"
