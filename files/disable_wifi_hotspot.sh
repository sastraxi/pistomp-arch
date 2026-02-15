#!/bin/bash
# Disable WiFi hotspot
set -e

nmcli connection down "pistomp-hotspot" 2>/dev/null || true

# Restart mod-ui so it rebinds WebSocket connections to the new network
# (see https://github.com/TreeFallSound/pi-stomp/issues/108)
systemctl restart mod-ui.service
