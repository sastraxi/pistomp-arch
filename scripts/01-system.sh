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
    authbind \
    python python-pip \
    libgpiod \
    i2c-tools \
    dnsmasq \
    hostapd \
    iw \
    parted \
    dosfstools \
    vim \
    wget curl

# ---------- enable services (via symlinks for chroot) ----------

WANTS="/etc/systemd/system/multi-user.target.wants"
mkdir -p "${WANTS}"

ln -sf /usr/lib/systemd/system/NetworkManager.service "${WANTS}/"
ln -sf /usr/lib/systemd/system/sshd.service "${WANTS}/"
ln -sf /usr/lib/systemd/system/avahi-daemon.service "${WANTS}/"

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

# ---------- authbind (allow mod-ui on port 80) ----------

touch /etc/authbind/byport/80
chmod 500 /etc/authbind/byport/80
chown "${FIRST_USER}:${FIRST_USER}" /etc/authbind/byport/80

# ---------- bash aliases ----------

install -m 644 /tmp/pistomp-arch/files/bash_aliases "/home/${FIRST_USER}/.bash_aliases"
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
