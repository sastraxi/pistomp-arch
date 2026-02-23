#!/bin/bash
# Runs once on first boot via firstboot.service
set -e

# Mount root as RW during the first boot process
mount -o remount,rw /

CONF="/boot/pistomp.conf"
LCD="/usr/bin/lcd-splash"
SPLASH="/usr/share/pistomp/splash.rgb565"
lcd() { "$LCD" "$SPLASH" "$1" 2>/dev/null || true; }

# ---------- apply pistomp.conf ----------

lcd "First boot setup..."

if [[ -f "${CONF}" ]]; then
    source "${CONF}"

    # WiFi — create the connection profile so NM connects automatically
    lcd "Configuring WiFi..."
    iw reg set "${WIFI_COUNTRY:-US}" 2>/dev/null || true
    if [[ -n "${WIFI_SSID:-}" ]]; then
        nmcli connection delete "preconfigured" 2>/dev/null || true
        nmcli connection add type wifi ifname wlan0 con-name "preconfigured" \
            ssid "${WIFI_SSID}" \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${WIFI_PASSWORD}" \
            connection.autoconnect yes || true
    fi

    # Hostname
    if [[ -n "${HOSTNAME:-}" && "${HOSTNAME}" != "pistomp" ]]; then
        hostnamectl set-hostname "${HOSTNAME}"
        sed -i "s/pistomp/${HOSTNAME}/g" /etc/hosts
    fi

    # User password
    if [[ -n "${USER_PASSWORD:-}" ]]; then
        echo "pistomp:${USER_PASSWORD}" | chpasswd
    fi

    # Timezone
    if [[ -n "${TIMEZONE:-}" ]]; then
        ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
        timedatectl set-ntp true
    fi

    # SSH authorized key
    if [[ -n "${SSH_AUTHORIZED_KEY:-}" ]]; then
        mkdir -p /home/pistomp/.ssh
        grep -qxF "${SSH_AUTHORIZED_KEY}" /home/pistomp/.ssh/authorized_keys 2>/dev/null \
            || echo "${SSH_AUTHORIZED_KEY}" >> /home/pistomp/.ssh/authorized_keys
        chmod 700 /home/pistomp/.ssh
        chmod 600 /home/pistomp/.ssh/authorized_keys
        chown -R pistomp:pistomp /home/pistomp/.ssh
    fi
fi

# ---------- expand DATA partition to fill SD card ----------

# Partition 1: Boot (FAT32)
# Partition 2: Root (ext4, Fixed size)
# Partition 3: Data (ext4, Fill remaining space)
lcd "Expanding filesystem..."
if command -v growpart &>/dev/null; then
    ROOT_DEV="$(findmnt -n -o SOURCE /)"
    DISK="/dev/$(lsblk -no PKNAME "${ROOT_DEV}")"
    DATA_PART="${DISK}p3"
    
    # Expand partition 3 (the data partition)
    growpart "${DISK}" 3 || true
    # Resize the filesystem on the data partition
    resize2fs "${DATA_PART}" || true
fi

# ---------- hardware setup ----------

lcd "Configuring audio..."
# Copy audio card settings (IQAudio DAC+)
if [[ -f /home/pistomp/pi-stomp/setup/audio/iqaudiocodec.state ]]; then
    cp /home/pistomp/pi-stomp/setup/audio/iqaudiocodec.state /var/lib/alsa/asound.state
fi

# JACK audio configuration
mkdir -p /etc/default
cat > /etc/default/jack <<EOF
# JACK audio settings (configured from /boot/pistomp.conf)
JACK_SAMPLE_RATE="${JACK_SAMPLE_RATE:-48000}"
JACK_PERIOD="${JACK_PERIOD:-256}"
EOF

# Fix ownership
chown -R pistomp:pistomp /home/pistomp/

# Set pi-stomp version (2.0 for Pi3, 3.0 for others)
if grep -q 'Pi 3' /proc/cpuinfo 2>/dev/null; then
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/modify_version.sh 2.0
else
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/modify_version.sh 3.0
fi

# Pi 5 EEPROM update
if grep -q 'Pi 5' /proc/cpuinfo 2>/dev/null; then
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/pi5_eeprom_update.sh || true
fi

# Disable unnecessary services
systemctl disable --now bluetooth.service 2>/dev/null || true

# ---------- done ----------

mv /boot/firstboot.sh /boot/firstboot.done
systemctl disable firstboot.service

# Remount root as RO just in case reboot takes a moment
sync
mount -o remount,ro /

reboot
