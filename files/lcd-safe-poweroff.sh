#!/bin/bash
# Called by systemd-shutdown after all filesystems are unmounted/remounted-ro.
# At this point it is safe to cut power. Update the LCD to tell the user.
# Argument $1 is the action: poweroff, halt, reboot, kexec

case "$1" in
    poweroff|halt)
        /usr/bin/lcd-splash /usr/share/pistomp/splash.rgb565 "Safe to power off"
        ;;
esac
