#!/bin/bash
set -euo pipefail

echo "==> 02-system: System packages and networking"

# ---------- core packages ----------

pacman -S --noconfirm --needed \
    base-devel \
    git \
    networkmanager \
    avahi nss-mdns \
    openssh \
    rsync \
    htop \
    nano less \
    python python-pip \
    libgpiod \
    i2c-tools \
    dnsmasq \
    hostapd \
    iw \
    wireless-regdb \
    parted \
    dosfstools \
    cloud-guest-utils \
    which \
    wget curl 7zip bzip2 unzip \
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
SUBSYSTEM=="spidev", KERNEL=="spidev*", GROUP="gpio", MODE="0660", TAG+="systemd"
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

mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-powersave.conf <<EOF
[connection]
wifi.powersave = 2
EOF

# WiFi MAC behavior: on an appliance, availability beats MAC randomization
# privacy. Some routers track device identity across scan→associate and get
# confused when NM flips from a randomized scan MAC back to the hardware MAC,
# so disable scan-time randomization. Also default every new WiFi profile to
# the hardware MAC rather than a per-network stable random MAC, which keeps
# router ACLs, captive portals, and parental controls happy.
cat > /etc/NetworkManager/conf.d/wifi-mac.conf <<EOF
[device]
wifi.scan-rand-mac-address=no

[connection]
802-11-wireless.cloned-mac-address=preserve
EOF

# Wired connection: DHCP on a LAN, link-local (169.254.x) only as a fallback
# when no DHCP server answers (direct cable). link-local=4 is fallback, not
# parallel — a parallel link-local would leak an extra 169.254 A record into
# avahi on a LAN and poison pistomp.local resolution. dhcp-timeout shortens
# the wait before the direct-cable fallback kicks in. No fixed IP: netJACK2
# finds the Pi by multicast and pistomp.local resolves over link-local mDNS.
install -d -m 700 /etc/NetworkManager/system-connections
cat > /etc/NetworkManager/system-connections/wired-end0.nmconnection <<EOF
[connection]
id=wired-end0
type=ethernet
interface-name=end0
autoconnect=true

[ipv4]
method=auto
link-local=4
route-metric=100
dhcp-timeout=15

[ipv6]
method=link-local
EOF
chmod 600 /etc/NetworkManager/system-connections/wired-end0.nmconnection

# Multi-homed host (end0 + wlan0 can be up on the same subnet): loosen the
# reverse-path filter so asymmetric paths aren't dropped, and use strong-host
# ARP so each NIC only answers/announces for its own address (no ARP flux).
cat > /etc/sysctl.d/99-multihome.conf <<EOF
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.default.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.default.arp_announce = 2
EOF

# Source-based policy routing so end0 and wlan0 are each reachable for inbound
# connections when both share a subnet (otherwise the lower-metric NIC steals
# the route and the other's IP goes dark). See the dispatcher for details.
install -Dm 755 /root/pistomp-arch/files/nm-dispatcher-multihome \
    /etc/NetworkManager/dispatcher.d/90-multihome

# Enable the dispatcher service. It is D-Bus activated via the alias
# dbus-org.freedesktop.nm-dispatcher.service; without that symlink NM's
# activation fails with "unknown unit" and dispatcher scripts never run.
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service \
    /etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service

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

# ---------- journald ----------

# Cap persistent journal size
install -Dm 644 /root/pistomp-arch/files/journald-pistomp.conf /etc/systemd/journald.conf.d/pistomp.conf

# ---------- helper scripts ----------

# Shell-agnostic helper scripts
for helper in ps-restart ps-stop ps-run ps-journal mod-restart mod-ui-journal mod-host-journal; do
    install -Dm 755 "/root/pistomp-arch/files/${helper}" "/usr/local/bin/${helper}"
done

echo "==> 02-system: Done"
