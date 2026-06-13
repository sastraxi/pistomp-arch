#!/bin/bash
set -euo pipefail

echo "==> 00-base: Bootstrap system"

# ---------- pacman init ----------

pacman-key --init
pacman-key --populate archlinuxarm

# Create vconsole.conf early (mkinitcpio needs it during kernel install)
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# ---------- locale ----------

sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

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
useradd -m -G wheel,audio,video -s /bin/bash "${FIRST_USER}"
echo "${FIRST_USER}:${FIRST_USER_PASS}" | chpasswd

# Enable sudo for wheel group (passwordless for convenience)
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

# Create jack user for JACK daemon
useradd -r -M -G audio -s /usr/bin/nologin jack 2>/dev/null || true

# Create gpio system group for Pi 5 PIO/GPIO device access
groupadd -r gpio 2>/dev/null || true

# pistomp user needs jack group for JACK socket access, gpio for PIO devices
usermod -aG jack,gpio "${FIRST_USER}"

# Create build user for makepkg (will be cleaned up in 08-cleanup.sh)
useradd -m -s /bin/bash builduser 2>/dev/null || true
echo "builduser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builduser

# ---------- boot config ----------

install -m 644 /root/pistomp-arch/files/config.txt /boot/config.txt
install -m 644 /root/pistomp-arch/files/cmdline.txt /boot/cmdline.txt

# ---------- fstab ----------

# Generate fstab entries for boot, root (RO), and data (RW)
# Using tmpfs for logs and temp files to protect the SD card and allow RO root
cat > /etc/fstab <<EOF
# <file system>  <mount point>  <type>  <options>                    <dump>  <pass>
/dev/mmcblk0p1   /boot          vfat    defaults,noatime             0       2
/dev/mmcblk0p2   /              ext4    ro,noatime                   0       1
/dev/mmcblk0p3   /home/pistomp  ext4    defaults,noatime,commit=10   0       2
tmpfs            /tmp           tmpfs   defaults,noatime,mode=1777   0       0
tmpfs            /var/tmp       tmpfs   defaults,noatime,mode=1777   0       0
tmpfs            /var/log       tmpfs   defaults,noatime,mode=0755   0       0
EOF

# ---------- persistent logging ----------

# /var/log is tmpfs (for RO root), so the journal symlink must be recreated each
# boot. tmpfiles.d runs after tmpfs mounts and before journald starts.
mkdir -p /home/pistomp/.system-logs/journal
chown -R 1000:1000 /home/pistomp/.system-logs

cat > /etc/tmpfiles.d/journal-link.conf <<EOF
L /var/log/journal - - - - /home/pistomp/.system-logs/journal
EOF

echo "==> 00-base: Done"
