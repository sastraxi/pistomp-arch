#!/bin/bash
set -euo pipefail

echo "==> 01-rt-kernel: Check for RT kernel"

CACHE_DIR="/root/pistomp-arch/cache"
RT_PKG_PATTERN="linux-rpi-rt-*.pkg.tar.*"

# Check if RT kernel packages are cached
if compgen -G "${CACHE_DIR}/${RT_PKG_PATTERN}" > /dev/null; then
    echo "==> Found cached RT kernel packages, installing..."
    echo "==> (To build RT kernel, run ./build-rt-kernel-docker.sh before main build)"

    # Remove stock kernel (conflicts with RT kernel)
    echo "==> Removing stock linux-rpi kernel..."
    pacman -R --noconfirm linux-rpi linux-rpi-headers

    # Install RT kernel
    echo "==> Installing RT kernel packages..."
    pacman -U --noconfirm "${CACHE_DIR}"/linux-rpi-rt-*.pkg.tar.*

    # Restore pistomp config.txt (RT kernel package overwrites it)
    echo "==> Restoring pistomp boot configuration..."
    install -m 644 /root/pistomp-arch/files/config.txt /boot/config.txt
    install -m 644 /root/pistomp-arch/files/cmdline.txt /boot/cmdline.txt

    # Verify installation
    if pacman -Q linux-rpi-rt &>/dev/null; then
        echo "==> RT kernel installed successfully:"
        pacman -Q linux-rpi-rt linux-rpi-rt-headers
    else
        echo "ERROR: RT kernel installation failed"
        exit 1
    fi
else
    echo "==> No cached RT kernel found, using stock kernel"
    echo "==> To use RT kernel: run ./build-rt-kernel-docker.sh then rebuild image"
    echo "==> Stock kernel installed:"
    pacman -Q linux-rpi linux-rpi-headers
fi

echo "==> 01-rt-kernel: Done"
