#!/bin/bash
set -euo pipefail

echo "==> 01-rt-kernel: Build and install RT kernel"

PKGBUILDS="/root/pistomp-arch/pkgbuilds"
RT_KERNEL_DIR="${PKGBUILDS}/linux-rpi-rt"

# Install build dependencies
echo "==> Installing kernel build dependencies..."
pacman -S --needed --noconfirm base-devel bc kmod inetutils xmlto docbook-xsl git patch

# Create builduser if it doesn't exist (needed for makepkg)
if ! id builduser &>/dev/null; then
    useradd -m -G wheel builduser
    echo "builduser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builduser
fi

echo "==> Preparing RT kernel PKGBUILD..."
cd "${RT_KERNEL_DIR}"
./build-rt-kernel.sh

echo "==> Building RT kernel packages (this will take 5-15 minutes on cross-compile, 60+ min native)..."
# Make parent directories traversable by builduser (need execute permission to cd through them)
chmod a+x /root /root/pistomp-arch /root/pistomp-arch/pkgbuilds
chown -R builduser:builduser "${RT_KERNEL_DIR}"

# Verify builduser can access the directory
echo "==> Verifying builduser permissions..."
su builduser -c "ls -la '${RT_KERNEL_DIR}'" || {
    echo "ERROR: builduser cannot access ${RT_KERNEL_DIR}"
    echo "Directory permissions:"
    ls -ld /root /root/pistomp-arch /root/pistomp-arch/pkgbuilds "${RT_KERNEL_DIR}"
    exit 1
}

su builduser -c "cd '${RT_KERNEL_DIR}' && makepkg -s --noconfirm"

# Install RT kernel (replaces stock linux-rpi due to conflicts)
echo "==> Installing RT kernel packages..."
pacman -U --noconfirm "${RT_KERNEL_DIR}"/linux-rpi-rt-*.pkg.tar.*

# Verify RT kernel is installed
if pacman -Q linux-rpi-rt &>/dev/null; then
    echo "==> RT kernel installed successfully:"
    pacman -Q linux-rpi-rt
    uname -r || echo "(kernel version will be available after boot)"
else
    echo "ERROR: RT kernel installation failed"
    exit 1
fi

echo "==> 01-rt-kernel: Done"
