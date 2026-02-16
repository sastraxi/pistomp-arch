#!/bin/bash
# Enable WiFi hotspot using NetworkManager
set -e

SSID="pistomp"
PASSWORD="pistompwifi"
IFACE="wlan0"

# Create hotspot connection if it doesn't exist
if ! nmcli connection show "${SSID}-hotspot" &>/dev/null; then
    nmcli connection add type wifi ifname "${IFACE}" con-name "${SSID}-hotspot" \
        autoconnect no ssid "${SSID}" mode ap \
        -- wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${PASSWORD}" \
        ipv4.method shared
else
    # Ensure it's configured correctly if it exists
    nmcli connection modify "${SSID}-hotspot" \
        802-11-wireless.mode ap \
        802-11-wireless-security.key-mgmt wpa-psk \
        802-11-wireless-security.psk "${PASSWORD}" \
        ipv4.method shared
fi

nmcli connection up "${SSID}-hotspot"

# Restart mod-ui so it rebinds WebSocket connections to the new network
# (see https://github.com/TreeFallSound/pi-stomp/issues/108)
systemctl restart mod-ui.service
