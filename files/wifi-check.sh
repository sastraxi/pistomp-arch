#!/bin/bash
# Check WiFi connectivity and fall back to hotspot if disconnected.
# Runs once at boot via wifi-check.service.

LOG="/var/log/wifi.log"
TIMESTAMP=$(date '+%F_%H:%M:%S')

if nmcli -t -f TYPE,STATE device | grep -q '^wifi:connected'; then
    echo "${TIMESTAMP} Wifi is connected." >> "$LOG"
else
    systemctl start wifi-hotspot.service
    echo "${TIMESTAMP} Wifi not connected. Starting hotspot." >> "$LOG"
fi
