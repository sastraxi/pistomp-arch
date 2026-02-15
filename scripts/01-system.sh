#!/bin/bash
set -euo pipefail

echo "==> 01-system: System packages and networking"

# ---------- core packages ----------

pacman -S --noconfirm --needed \
    base-devel \
    git \
    networkmanager \
    avahi nss-mdns \
    openssh \
    rsync \
    htop \
    nano \
    python python-pip \
    libgpiod \
    i2c-tools \
    dnsmasq \
    hostapd \
    iw \
    parted \
    dosfstools \
    cloud-guest-utils \
    wget curl \
    ttf-dejavu \
    raspberrypi-utils

# ---------- enable services (via symlinks for chroot) ----------

WANTS="/etc/systemd/system/multi-user.target.wants"
mkdir -p "${WANTS}"

ln -sf /usr/lib/systemd/system/NetworkManager.service "${WANTS}/"
ln -sf /usr/lib/systemd/system/sshd.service "${WANTS}/"
ln -sf /usr/lib/systemd/system/avahi-daemon.service "${WANTS}/"

# ---------- hardware access (GPIO/SPI/I2C via udev) ----------

# Grant gpio group access to hardware peripherals (gpio group created in 00-base.sh)
# Also provide a /dev/gpiochip4 symlink on Pi 5 to satisfy gpiozero 2.0.1 which
# hardcodes chip 4 for Pi 5 (but Arch/Kernel 6.12+ maps it to chip 0).
cat > /etc/udev/rules.d/99-pistomp-hw.rules <<'EOF'
SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"
SUBSYSTEM=="gpio", KERNEL=="gpiochip*", DRIVERS=="pinctrl-rp1", SYMLINK+="gpiochip4"
SUBSYSTEM=="spidev", KERNEL=="spidev*", GROUP="gpio", MODE="0660"
SUBSYSTEM=="i2c-dev", KERNEL=="i2c-[0-9]*", GROUP="gpio", MODE="0660"
SUBSYSTEM=="rp1-pio", GROUP="gpio", MODE="0660"
EOF

# Rename WiFi interface to wlan0 for pi-stomp compatibility
# (Arch uses predictable names like wld0, but pi-stomp hardcodes wlan0)
cat > /etc/udev/rules.d/70-wifi-name.rules <<'EOF'
SUBSYSTEM=="net", ACTION=="add", ENV{DEVTYPE}=="wlan", NAME="wlan0"
EOF

# ---------- SSH config ----------

# Allow password auth (for initial setup)
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# ---------- mDNS (avahi) ----------

# Enable mDNS resolution via nsswitch
sed -i 's/^hosts:.*/hosts: myhostname mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files dns/' /etc/nsswitch.conf

# ---------- NetworkManager ----------

cat > /etc/NetworkManager/NetworkManager.conf <<EOF
[main]
plugins=keyfile
dns=dnsmasq

[keyfile]
unmanaged-devices=none
EOF

# ---------- bash aliases ----------

install -m 644 /root/pistomp-arch/files/bash_aliases "/home/${FIRST_USER}/.bash_aliases"
chown "${FIRST_USER}:${FIRST_USER}" "/home/${FIRST_USER}/.bash_aliases"

# Source .bash_aliases from .bashrc if not already
if ! grep -q bash_aliases "/home/${FIRST_USER}/.bashrc" 2>/dev/null; then
    cat >> "/home/${FIRST_USER}/.bashrc" <<'BASHRC'

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi
BASHRC
fi

echo "==> 01-system: Done"
