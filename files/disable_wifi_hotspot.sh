#!/bin/bash
# Disable WiFi hotspot
set -e

nmcli connection down "pistomp-hotspot" 2>/dev/null || true
