#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# ---------- helpers ----------

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

cleanup() {
    log "Cleaning up..."
    sync
    # arch-chroot leaves behind /proc, /sys, /dev, /run mounts inside the
    # rootfs. umount -R (recursive) handles all submounts in the correct
    # reverse order. This is NOT lazy unmount — each unmount is real and
    # flushes data before proceeding.
    if mountpoint -q "${ROOT_MNT}" 2>/dev/null; then
        umount -R "${ROOT_MNT}" 2>/dev/null || {
            # If recursive unmount fails, kill stale processes and retry
            fuser -km "${ROOT_MNT}" 2>/dev/null || true
            sleep 1
            umount -R "${ROOT_MNT}" 2>/dev/null || true
        }
    fi
    mountpoint -q "${BOOT_MNT}" 2>/dev/null && umount "${BOOT_MNT}" || true
    sync
    [[ -n "${LOOP_DEV:-}" ]] && kpartx -dv "${LOOP_DEV}" 2>/dev/null || true
    [[ -n "${LOOP_DEV:-}" ]] && losetup -d "${LOOP_DEV}" 2>/dev/null || true
}
trap cleanup EXIT

run_in_chroot() {
    local script="$1"
    log "Running ${script} in chroot..."
    cp "${SCRIPT_DIR}/${script}" "${ROOT_MNT}/root/current-script.sh"
    chmod +x "${ROOT_MNT}/root/current-script.sh"
    arch-chroot "${ROOT_MNT}" /bin/bash -c "
        set -a
        source /root/pistomp-arch/config.sh
        set +a
        /root/current-script.sh
    "
    rm -f "${ROOT_MNT}/root/current-script.sh"
}

# ---------- preflight ----------

[[ $EUID -eq 0 ]] || die "Must run as root"

for cmd in fallocate parted losetup mkfs.vfat mkfs.ext4 arch-chroot kpartx pacstrap; do
    command -v "$cmd" &>/dev/null || die "Missing required command: $cmd"
done

[[ -f "${SCRIPT_DIR}/cache/lv2plugins.tar.gz" ]] || die "LV2 plugins not found. Run: mkdir -p cache && curl -L -o cache/lv2plugins.tar.gz ${LV2_PLUGINS_URL}"

# ---------- image setup ----------

WORK_DIR="${SCRIPT_DIR}/work"
DEPLOY_DIR="${SCRIPT_DIR}/deploy"
mkdir -p "${WORK_DIR}" "${DEPLOY_DIR}"

IMG_FILE="${WORK_DIR}/${IMG_NAME}.img"
ROOT_MNT="${WORK_DIR}/rootfs"
BOOT_MNT="${WORK_DIR}/boot"

# Clean up stale loop devices from previous failed builds
if [[ -f "${IMG_FILE}" ]]; then
    log "Cleaning up previous build artifacts..."
    for loop in $(losetup -j "${IMG_FILE}" 2>/dev/null | cut -d: -f1); do
        kpartx -dv "${loop}" 2>/dev/null || true
        losetup -d "${loop}" 2>/dev/null || true
    done
    rm -f "${IMG_FILE}"
fi
umount -lf "${ROOT_MNT}" 2>/dev/null || true
umount -lf "${BOOT_MNT}" 2>/dev/null || true
mkdir -p "${ROOT_MNT}" "${BOOT_MNT}"

# Create image file
log "Creating ${IMG_SIZE_MB}MB image..."
fallocate -l "${IMG_SIZE_MB}M" "${IMG_FILE}"

# Partition: 512MB FAT32 boot + 4GB ext4 root + rest ext4 data
log "Partitioning image..."
parted -s "${IMG_FILE}" mklabel msdos
parted -s "${IMG_FILE}" mkpart primary fat32 1MiB 513MiB
parted -s "${IMG_FILE}" set 1 boot on
parted -s "${IMG_FILE}" mkpart primary ext4 513MiB 4609MiB
parted -s "${IMG_FILE}" mkpart primary ext4 4609MiB 100%

# Attach loop device and create partition mappings
log "Setting up loop device..."
LOOP_DEV=$(losetup --find --show "${IMG_FILE}")
kpartx -av "${LOOP_DEV}"
sleep 1

# kpartx creates /dev/mapper/loopNp1, /dev/mapper/loopNp2, /dev/mapper/loopNp3
LOOP_NAME=$(basename "${LOOP_DEV}")
BOOT_PART="/dev/mapper/${LOOP_NAME}p1"
ROOT_PART="/dev/mapper/${LOOP_NAME}p2"
DATA_PART="/dev/mapper/${LOOP_NAME}p3"

[[ -b "${BOOT_PART}" ]] || die "Boot partition ${BOOT_PART} not found"
[[ -b "${ROOT_PART}" ]] || die "Root partition ${ROOT_PART} not found"
[[ -b "${DATA_PART}" ]] || die "Data partition ${DATA_PART} not found"

# Format
log "Formatting partitions..."
mkfs.vfat -F 32 -n PISTOMP "${BOOT_PART}"
mkfs.ext4 -F "${ROOT_PART}"
mkfs.ext4 -F "${DATA_PART}"

# Mount
log "Mounting partitions..."
mount "${ROOT_PART}" "${ROOT_MNT}"
mkdir -p "${ROOT_MNT}/boot" "${ROOT_MNT}/home/pistomp"
mount "${BOOT_PART}" "${BOOT_MNT}"
# ALARM expects /boot to be the FAT32 partition
mount --bind "${BOOT_MNT}" "${ROOT_MNT}/boot"
# Mount data partition to home
mount "${DATA_PART}" "${ROOT_MNT}/home/pistomp"
chown 1000:1000 "${ROOT_MNT}/home/pistomp"

# Create vconsole.conf before pacstrap (mkinitcpio's sd-vconsole hook needs it)
mkdir -p "${ROOT_MNT}/etc"
echo "KEYMAP=${KEYMAP}" > "${ROOT_MNT}/etc/vconsole.conf"

# Bootstrap rootfs with pacstrap
log "Running pacstrap..."
pacstrap -C "${SCRIPT_DIR}/files/pacman-aarch64.conf" -M -K "${ROOT_MNT}" \
    base sudo systemd-sysvcompat \
    linux-rpi linux-rpi-headers \
    raspberrypi-bootloader firmware-raspberrypi \
    archlinuxarm-keyring

# Use pacoloco cache during chroot phase, replaced later
install -m 644 "${SCRIPT_DIR}/files/pacman-aarch64.conf" "${ROOT_MNT}/etc/pacman.conf"

# Copy project files into chroot
log "Copying project files into chroot..."
mkdir -p "${ROOT_MNT}/root/pistomp-arch"
cp "${SCRIPT_DIR}/config.sh" "${ROOT_MNT}/root/pistomp-arch/"
cp -r "${SCRIPT_DIR}/files" "${ROOT_MNT}/root/pistomp-arch/"
cp -r "${SCRIPT_DIR}/pkgbuilds" "${ROOT_MNT}/root/pistomp-arch/"
cp -r "${SCRIPT_DIR}/patches" "${ROOT_MNT}/root/pistomp-arch/"
cp -r "${SCRIPT_DIR}/extras" "${ROOT_MNT}/root/pistomp-arch/"
# Bind-mount cache to avoid copying large tarballs
mkdir -p "${ROOT_MNT}/root/pistomp-arch/cache"
mount --bind "${SCRIPT_DIR}/cache" "${ROOT_MNT}/root/pistomp-arch/cache"

# ---------- run build scripts ----------

run_in_chroot "scripts/00-base.sh"
run_in_chroot "scripts/01-rt-kernel.sh"
run_in_chroot "scripts/02-system.sh"
run_in_chroot "scripts/03-audio.sh"
run_in_chroot "scripts/04-native-pkgs.sh"
run_in_chroot "scripts/05-python.sh"
run_in_chroot "scripts/06-app-data.sh"
run_in_chroot "scripts/07-services.sh"
run_in_chroot "scripts/08-cleanup.sh"

# ---------- finalize ----------

# Install the final pacman.conf (real mirrors, no DisableSandbox)
install -m 644 "${SCRIPT_DIR}/files/pacman-alarm.conf" "${ROOT_MNT}/etc/pacman.conf"

log "Unmounting..."
cleanup

# Compress minimally (see recompress-img.sh for distribution)
TIMESTAMP="${BUILD_TIMESTAMP:-$(date +%Y-%m-%d)}"
OUTPUT="${DEPLOY_DIR}/${IMG_NAME}-${TIMESTAMP}.img.zst"

# If file exists, increment filename (file_1.img.zst, file_2.img.zst, etc.)
if [[ -f "${OUTPUT}" ]]; then
    BASE="${DEPLOY_DIR}/${IMG_NAME}-${TIMESTAMP}"
    COUNTER=1
    while [[ -f "${BASE}_${COUNTER}.img.zst" ]]; do
        ((COUNTER++))
    done
    OUTPUT="${BASE}_${COUNTER}.img.zst"
fi

log "Compressing image to ${OUTPUT}..."
zstd -T0 -3 "${IMG_FILE}" -o "${OUTPUT}"

log "Build complete: ${OUTPUT}"
log "Image size: $(du -h "${OUTPUT}" | cut -f1)"
