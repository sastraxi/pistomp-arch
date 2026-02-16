#!/bin/bash
set -euo pipefail

echo "==> 03-audio: Audio stack"

# ---------- audio packages ----------

pacman -S --noconfirm --needed \
    jack2 \
    jack-example-tools \
    rtirq \
    lilv python-lilv \
    serd sord sratom lv2 \
    alsa-utils alsa-lib \
    libsamplerate \
    libsndfile \
    fftw \
    liblo

# ---------- realtime audio config ----------

# Add users to audio group (pistomp already added in 00-base)
usermod -aG audio jack 2>/dev/null || true

# Set realtime priority and memlock limits for audio group
mkdir -p /etc/security/limits.d
cat > /etc/security/limits.d/99-audio.conf <<EOF
@audio   -  rtprio     95
@audio   -  memlock    unlimited
@audio   -  nice       -19
EOF

# Grant audio group access to CPU DMA latency control
cat > /etc/udev/rules.d/99-cpu-dma-latency.rules <<EOF
KERNEL=="cpu_dma_latency", GROUP="audio", MODE="0660"
EOF

# ---------- JACK config ----------

install -m 755 /root/pistomp-arch/files/jackdrc /etc/jackdrc
chown jack:jack /etc/jackdrc

# ---------- ALSA config ----------

install -m 644 /root/pistomp-arch/files/alsa-base.conf /etc/modprobe.d/alsa-base.conf

# ---------- sysctl tuning ----------

mkdir -p /etc/sysctl.d
install -m 644 /root/pistomp-arch/files/sysctl.d/90-audio.conf /etc/sysctl.d/90-audio.conf

# ---------- rtirq service ----------

# Enable rtirq for RT kernel (no-op on non-RT kernels)
ln -sf /usr/lib/systemd/system/rtirq.service /etc/systemd/system/multi-user.target.wants/rtirq.service

echo "==> 03-audio: Done"
