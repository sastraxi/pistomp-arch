#!/bin/bash
set -euo pipefail

echo "==> 02-audio: Audio stack"

# ---------- audio packages ----------

pacman -S --noconfirm --needed \
    jack2 \
    jack-example-tools \
    lilv python-lilv \
    serd sord sratom lv2 \
    alsa-utils alsa-lib \
    libsamplerate \
    libsndfile \
    fftw \
    fluidsynth \
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

# ---------- JACK config ----------

install -m 755 /root/pistomp-arch/files/jackdrc /etc/jackdrc
chown jack:jack /etc/jackdrc

# ---------- ALSA config ----------

install -m 644 /root/pistomp-arch/files/alsa-base.conf /etc/modprobe.d/alsa-base.conf

echo "==> 02-audio: Done"
