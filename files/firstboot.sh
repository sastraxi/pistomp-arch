#!/bin/bash
# Runs once on first boot via firstboot.service
set -e

CONF="/boot/pistomp.conf"

# ---------- apply pistomp.conf ----------

if [[ -f "${CONF}" ]]; then
    source "${CONF}"

    # WiFi — create the connection profile so NM connects automatically
    if [[ -n "${WIFI_SSID:-}" ]]; then
        iw reg set "${WIFI_COUNTRY:-US}" 2>/dev/null || true
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
        echo "${SSH_AUTHORIZED_KEY}" >> /home/pistomp/.ssh/authorized_keys
        chmod 700 /home/pistomp/.ssh
        chmod 600 /home/pistomp/.ssh/authorized_keys
        chown -R pistomp:pistomp /home/pistomp/.ssh
    fi
fi

# ---------- expand root partition to fill SD card ----------

if command -v growpart &>/dev/null; then
    ROOT_DEV="$(findmnt -n -o SOURCE /)"
    DISK="/dev/$(lsblk -no PKNAME "${ROOT_DEV}")"
    PARTNUM="$(echo "${ROOT_DEV}" | grep -o '[0-9]*$')"
    growpart "${DISK}" "${PARTNUM}" || true
    resize2fs "${ROOT_DEV}" || true
fi

# ---------- hardware setup ----------

# Copy audio card settings (IQAudio DAC+)
if [[ -f /home/pistomp/pi-stomp/setup/audio/iqaudiocodec.state ]]; then
    cp /home/pistomp/pi-stomp/setup/audio/iqaudiocodec.state /var/lib/alsa/asound.state
fi

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
reboot
