#!/bin/bash
set -euo pipefail

echo "==> 00-base: Bootstrap system"

# ---------- pacman init ----------

pacman-key --init
pacman-key --populate archlinuxarm

# Full system upgrade
pacman -Syu --noconfirm

# Replace generic kernel with RPi-specific kernel (supports Pi 3/4/5)
pacman -S --noconfirm linux-rpi linux-rpi-headers
# Remove generic kernel if present
pacman -Rns --noconfirm linux-aarch64 uboot-raspberrypi 2>/dev/null || true

# ---------- locale ----------

sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# ---------- timezone ----------

ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc || true

# ---------- hostname ----------

echo "${TARGET_HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${TARGET_HOSTNAME}.localdomain ${TARGET_HOSTNAME}
EOF

# ---------- users ----------

# Set root password (same as user for simplicity)
echo "root:${FIRST_USER_PASS}" | chpasswd

# Create pistomp user with sudo
useradd -m -G wheel,audio,video,gpio,spi,i2c -s /bin/bash "${FIRST_USER}"
echo "${FIRST_USER}:${FIRST_USER_PASS}" | chpasswd

# Enable sudo for wheel group (passwordless for convenience)
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

# Create jack user for JACK daemon
useradd -r -M -G audio -s /usr/bin/nologin jack 2>/dev/null || true

# Remove default alarm user (ALARM ships with alarm:alarm)
userdel -r alarm 2>/dev/null || true

# ---------- boot config ----------

install -m 644 /tmp/pistomp-arch/files/config.txt /boot/config.txt

# ---------- fstab ----------

# Generate fstab entries for boot and root
cat > /etc/fstab <<EOF
# <file system>  <mount point>  <type>  <options>  <dump>  <pass>
/dev/mmcblk0p1   /boot          vfat    defaults   0       0
/dev/mmcblk0p2   /              ext4    defaults   0       1
EOF

echo "==> 00-base: Done"
