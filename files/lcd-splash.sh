#!/bin/bash
# Update the piStomp LCD with a boot status message.
# Usage: lcd-splash.sh "Loading audio engine"
#
# Shows the splash image with an optional status message overlaid
# at the bottom of the screen. Fails silently so it never blocks boot.

SPLASH="/usr/share/pistomp/splash.png"
LCD_SHOW="/home/pistomp/pi-stomp/tools/lcd_show.py"
PYTHON="/opt/pistomp/venvs/pi-stomp/bin/python"

MESSAGE="${1:-}"

if [ ! -f "$LCD_SHOW" ] || [ ! -f "$SPLASH" ]; then
    exit 0
fi

ARGS=("$SPLASH")
if [ -n "$MESSAGE" ]; then
    ARGS+=("--message" "$MESSAGE")
fi

exec "$PYTHON" "$LCD_SHOW" "${ARGS[@]}" 2>/dev/null || true
