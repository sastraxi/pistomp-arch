#!/bin/bash
# toggle-ro.sh - Helper to switch root filesystem between RO and RW modes

set -e

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

MODE=$1

case $MODE in
    rw)
        echo "Switching root to READ-WRITE mode..."
        mount -o remount,rw /
        echo "Root is now RW. Remember to switch back to RO when finished!"
        ;;
    ro)
        echo "Switching root to READ-ONLY mode..."
        sync
        mount -o remount,ro /
        echo "Root is now RO."
        ;;
    *)
        echo "Usage: $0 [rw|ro]"
        exit 1
        ;;
esac
