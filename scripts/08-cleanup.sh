#!/bin/bash
set -euo pipefail

echo "==> 08-cleanup: Cleaning up"

# ---------- remove build user ----------

userdel -r builduser 2>/dev/null || true
rm -f /etc/sudoers.d/builduser

# ---------- remove build dependencies ----------

echo "==> Removing build and orphaned dependencies..."
# Build tools
for pkg in base-devel bc kmod inetutils xmlto docbook-xsl ffmpeg swig; do
    pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
done
# tk/X11 chain — not needed on headless device
for pkg in tk tcl libxss libxft libxrender libxext libx11; do
    pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
done
# Kernel headers (only needed for compiling kernel modules)
pacman -Rns --noconfirm linux-rpi-rt-headers 2>/dev/null || true
pacman -Rns --noconfirm linux-rpi-headers 2>/dev/null || true
# Sweep remaining orphans
pacman -Rns $(pacman -Qqdt) --noconfirm 2>/dev/null || true

# ---------- clear package cache ----------

pacman -Scc --noconfirm

# ---------- install production pacman.conf ----------

install -m 644 /root/pistomp-arch/files/pacman-alarm.conf /etc/pacman.conf

# ---------- clear temporary files ----------

# Preserve cache/ (bind-mounted from host) — only delete project copies
rm -rf /root/pistomp-arch/files
rm -rf /root/pistomp-arch/pkgbuilds
rm -rf /root/pistomp-arch/patches
rm -rf /root/pistomp-arch/scripts
rm -rf /tmp/build-*
rm -rf /tmp/mod-ui
rm -rf /var/log/journal/*
rm -rf /var/cache/pacman/pkg/*

# ---------- remove docs, locales, and other unneeded files ----------

rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
# Keep en_US and C locales, remove all others
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en_US' ! -name 'C' -exec rm -rf {} +

# ---------- prune firmware blobs (keep only RPi WiFi/BT) ----------

echo "==> Pruning firmware blobs..."
if [[ -d /usr/lib/firmware ]]; then
    cd /usr/lib/firmware
    for dir in */; do
        dir="${dir%/}"
        case "$dir" in
            brcm|cypress) continue ;;
            *) rm -rf "$dir" ;;
        esac
    done
    # Remove non-RPi firmware files at top level (keep regulatory DB)
    find /usr/lib/firmware -maxdepth 1 -type f ! -name 'regulatory*' -delete
    cd /
fi

# ---------- prune kernel modules ----------

echo "==> Pruning unused kernel modules..."
KVER=$(ls /usr/lib/modules/ | head -1)
if [[ -n "$KVER" && -d "/usr/lib/modules/$KVER/kernel" ]]; then
    MOD_DIR="/usr/lib/modules/$KVER/kernel"
    # GPU drivers for non-RPi hardware
    rm -rf "$MOD_DIR/drivers/gpu/drm/"{amd,i915,nouveau,radeon,xe,vmwgfx}
    # Network hardware not on a Pi
    rm -rf "$MOD_DIR/drivers/infiniband"
    rm -rf "$MOD_DIR/drivers/isdn"
    # Staging drivers
    rm -rf "$MOD_DIR/drivers/staging"
    # PCI sound cards (Pi uses I2S/USB only)
    rm -rf "$MOD_DIR/sound/pci"
    # Rebuild module dependency index
    depmod -a "$KVER"
fi

# ---------- clear Python caches ----------

find /opt/pistomp -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find /home -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
rm -rf /root/.cache/uv

# ---------- remove qemu (will also be removed by build.sh) ----------

rm -f /usr/bin/qemu-aarch64-static

# ---------- remove uv python download cache ----------

rm -rf /opt/pistomp/python/downloads 2>/dev/null || true

# ---------- zero-fill free space for better compression ----------

echo "==> Zero-filling free space..."
dd if=/dev/zero of=/zero_fill bs=1M 2>/dev/null || true
rm -f /zero_fill
sync

echo "==> 08-cleanup: Done"
echo "==> Build complete!"
