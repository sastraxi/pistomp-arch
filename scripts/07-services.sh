#!/bin/bash
set -euo pipefail

echo "==> 07-services: Service files and boot scripts"

FILES="/root/pistomp-arch/files"

# ---------- service files ----------

echo "==> Installing service files..."

SYSTEMD_DIR="/usr/lib/systemd/system"
WANTS="/etc/systemd/system/multi-user.target.wants"
mkdir -p "${WANTS}"

for svc in jack mod-host mod-ui browsepy mod-amidithru mod-ala-pi-stomp firstboot pistomp-lcd-splash lcd-reboot lcd-shutdown; do
    install -v -m 644 "${FILES}/${svc}.service" "${SYSTEMD_DIR}/"
done

# Services enabled by default
for svc in jack mod-host mod-ui browsepy mod-amidithru mod-ala-pi-stomp firstboot; do
    ln -sf "${SYSTEMD_DIR}/${svc}.service" "${WANTS}/"
done

# Early services
SYSINIT_WANTS="/etc/systemd/system/sysinit.target.wants"
mkdir -p "${SYSINIT_WANTS}"
ln -sf "${SYSTEMD_DIR}/pistomp-lcd-splash.service" "${SYSINIT_WANTS}/"

# Reboot splash
REBOOT_WANTS="/etc/systemd/system/reboot.target.wants"
mkdir -p "${REBOOT_WANTS}"
ln -sf "${SYSTEMD_DIR}/lcd-reboot.service" "${REBOOT_WANTS}/"

# Shutdown splash
POWEROFF_WANTS="/etc/systemd/system/poweroff.target.wants"
mkdir -p "${POWEROFF_WANTS}"
ln -sf "${SYSTEMD_DIR}/lcd-shutdown.service" "${POWEROFF_WANTS}/"

# Services installed but NOT enabled by default
for svc in ttymidi mod-midi-merger mod-midi-merger-broadcaster wifi-hotspot mod-touchosc2midi; do
    if [[ -f "${FILES}/${svc}.service" ]]; then
        install -v -m 644 "${FILES}/${svc}.service" "${SYSTEMD_DIR}/"
    fi
done

# Verify service files are in place
echo "==> Verifying service files in ${SYSTEMD_DIR}:"
ls -la "${SYSTEMD_DIR}"/{jack,mod-host,mod-ui,browsepy,mod-amidithru,mod-ala-pi-stomp,firstboot}.service

# ---------- firstboot script ----------

install -m 755 "${FILES}/firstboot.sh" /boot/firstboot.sh
install -m 644 "${FILES}/pistomp.conf" /boot/pistomp.conf

# ---------- helper scripts ----------

install -m 755 "${FILES}/wait-for-mod-host.sh" /usr/local/bin/wait-for-mod-host.sh
mkdir -p /usr/share/pistomp
# Convert splash PNG to raw RGB565-BE at build time (153600 bytes, skips libpng at runtime)
pacman -S --needed --noconfirm ffmpeg
ffmpeg -y -i "${FILES}/splash.png" -vf "scale=320:240:force_original_aspect_ratio=decrease,pad=320:240:-1:-1:color=black" -sws_dither ed -f rawvideo -pix_fmt rgb565be /usr/share/pistomp/splash.rgb565

# ---------- touchosc2midi start script ----------

mkdir -p /usr/mod/scripts
install -m 755 "${FILES}/start_touchosc2midi.sh" /usr/mod/scripts/

# ---------- wifi hotspot and wifi check scripts ----------

mkdir -p /usr/lib/pistomp-wifi
for f in enable_wifi_hotspot.sh disable_wifi_hotspot.sh wifi-check.sh; do
    if [[ -f "${FILES}/${f}" ]]; then
        install -m 755 "${FILES}/${f}" /usr/lib/pistomp-wifi/
    fi
done

# wifi-check: falls back to hotspot if WiFi is not connected at boot
install -v -m 644 "${FILES}/wifi-check.service" "${SYSTEMD_DIR}/"
ln -sf "${SYSTEMD_DIR}/wifi-check.service" "${WANTS}/"

# ---------- MOTD (pistomp logo) ----------

echo "==> Installing MOTD..."
{
    echo ""
    bash "${FILES}/display-pistomp-logo"
    echo "  Build date:    $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "  Kernel:        $(pacman -Q linux-rpi 2>/dev/null || pacman -Q linux-rpi-rt 2>/dev/null || echo 'unknown')"
    echo ""
    echo "  Tweaks and additional instruments available in ~/extras"
    echo ""
} > /etc/motd

echo "==> 07-services: Done"
