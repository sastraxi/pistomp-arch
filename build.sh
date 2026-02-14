#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# ---------- helpers ----------

log()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

cleanup() {
    log "Cleaning up..."
    # Unmount in reverse order
    for mp in dev/pts dev/shm dev proc sys tmp; do
        mountpoint -q "${ROOT_MNT}/${mp}" 2>/dev/null && umount -lf "${ROOT_MNT}/${mp}" || true
    done
    mountpoint -q "${BOOT_MNT}" 2>/dev/null && umount -lf "${BOOT_MNT}" || true
    mountpoint -q "${ROOT_MNT}" 2>/dev/null && umount -lf "${ROOT_MNT}" || true
    [[ -n "${LOOP_DEV:-}" ]] && losetup -d "${LOOP_DEV}" 2>/dev/null || true
}
trap cleanup EXIT

run_in_chroot() {
    local script="$1"
    log "Running ${script} in chroot..."
    cp "${SCRIPT_DIR}/${script}" "${ROOT_MNT}/tmp/current-script.sh"
    chmod +x "${ROOT_MNT}/tmp/current-script.sh"

    # Export config vars into chroot environment
    arch-chroot "${ROOT_MNT}" /bin/bash -c "
        export FIRST_USER='${FIRST_USER}'
        export FIRST_USER_PASS='${FIRST_USER_PASS}'
        export TARGET_HOSTNAME='${TARGET_HOSTNAME}'
        export LOCALE='${LOCALE}'
        export TIMEZONE='${TIMEZONE}'
        export KEYMAP='${KEYMAP}'
        export PYTHON_VERSION='${PYTHON_VERSION}'
        export PISTOMP_REPO='${PISTOMP_REPO}'
        export PISTOMP_BRANCH='${PISTOMP_BRANCH}'
        export MODUI_REPO='${MODUI_REPO}'
        export MODUI_BRANCH='${MODUI_BRANCH}'
        export PEDALBOARDS_REPO='${PEDALBOARDS_REPO}'
        export PEDALBOARDS_BRANCH='${PEDALBOARDS_BRANCH}'
        export USERFILES_REPO='${USERFILES_REPO}'
        export USERFILES_BRANCH='${USERFILES_BRANCH}'
        export BROWSEPY_REPO='${BROWSEPY_REPO}'
        export TOUCHOSC2MIDI_REPO='${TOUCHOSC2MIDI_REPO}'
        /tmp/current-script.sh
    "
    rm -f "${ROOT_MNT}/tmp/current-script.sh"
}

# ---------- preflight ----------

[[ $EUID -eq 0 ]] || die "Must run as root"

for cmd in fallocate parted losetup mkfs.vfat mkfs.ext4 arch-chroot; do
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
mkdir -p "${ROOT_MNT}" "${BOOT_MNT}"

# Use cached ALARM tarball (from cache/ or work/)
if [[ -f "${SCRIPT_DIR}/cache/alarm-aarch64.tar.gz" ]]; then
    TARBALL="${SCRIPT_DIR}/cache/alarm-aarch64.tar.gz"
elif [[ -f "${WORK_DIR}/alarm-aarch64.tar.gz" ]]; then
    TARBALL="${WORK_DIR}/alarm-aarch64.tar.gz"
else
    TARBALL="${WORK_DIR}/alarm-aarch64.tar.gz"
    log "Downloading ALARM tarball..."
    curl -L -o "${TARBALL}" "${ALARM_TARBALL_URL}"
fi

# Create image file
log "Creating ${IMG_SIZE_MB}MB image..."
fallocate -l "${IMG_SIZE_MB}M" "${IMG_FILE}"

# Partition: 512MB FAT32 boot + rest ext4 root
log "Partitioning image..."
parted -s "${IMG_FILE}" mklabel msdos
parted -s "${IMG_FILE}" mkpart primary fat32 1MiB 513MiB
parted -s "${IMG_FILE}" set 1 boot on
parted -s "${IMG_FILE}" mkpart primary ext4 513MiB 100%

# Attach loop device
log "Setting up loop device..."
LOOP_DEV=$(losetup --find --show --partscan "${IMG_FILE}")
BOOT_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

# Wait for partition devices
sleep 1
[[ -b "${BOOT_PART}" ]] || die "Boot partition ${BOOT_PART} not found"
[[ -b "${ROOT_PART}" ]] || die "Root partition ${ROOT_PART} not found"

# Format
log "Formatting partitions..."
mkfs.vfat -F 32 "${BOOT_PART}"
mkfs.ext4 -F "${ROOT_PART}"

# Mount
log "Mounting partitions..."
mount "${ROOT_PART}" "${ROOT_MNT}"
mkdir -p "${ROOT_MNT}/boot"
mount "${BOOT_PART}" "${BOOT_MNT}"
# ALARM expects /boot to be the FAT32 partition
mount --bind "${BOOT_MNT}" "${ROOT_MNT}/boot"

# Extract tarball
log "Extracting ALARM tarball..."
bsdtar -xpf "${TARBALL}" -C "${ROOT_MNT}"

# Copy qemu for cross-arch execution (if host is not aarch64)
if [[ "$(uname -m)" != "aarch64" ]]; then
    QEMU_BIN=$(command -v qemu-aarch64-static 2>/dev/null || true)
    if [[ -n "${QEMU_BIN}" ]]; then
        log "Installing qemu-aarch64-static for cross-arch chroot..."
        cp "${QEMU_BIN}" "${ROOT_MNT}/usr/bin/qemu-aarch64-static"
    else
        die "qemu-aarch64-static not found. Install qemu-user-static for cross-arch builds."
    fi
fi

# Copy project files into chroot
log "Copying project files into chroot..."
mkdir -p "${ROOT_MNT}/tmp/pistomp-arch"
cp -r "${SCRIPT_DIR}/files" "${ROOT_MNT}/tmp/pistomp-arch/"
cp -r "${SCRIPT_DIR}/pkgbuilds" "${ROOT_MNT}/tmp/pistomp-arch/"
cp -r "${SCRIPT_DIR}/patches" "${ROOT_MNT}/tmp/pistomp-arch/"

# Mount pseudo-filesystems for chroot
mount -t proc proc "${ROOT_MNT}/proc"
mount -t sysfs sys "${ROOT_MNT}/sys"
mount --bind /dev "${ROOT_MNT}/dev"
mount --bind /dev/pts "${ROOT_MNT}/dev/pts"
mount --bind /dev/shm "${ROOT_MNT}/dev/shm"
mount -t tmpfs tmpfs "${ROOT_MNT}/tmp"

# Re-copy files to tmpfs-mounted /tmp
mkdir -p "${ROOT_MNT}/tmp/pistomp-arch"
cp -r "${SCRIPT_DIR}/files" "${ROOT_MNT}/tmp/pistomp-arch/"
cp -r "${SCRIPT_DIR}/pkgbuilds" "${ROOT_MNT}/tmp/pistomp-arch/"
cp -r "${SCRIPT_DIR}/patches" "${ROOT_MNT}/tmp/pistomp-arch/"
cp -r "${SCRIPT_DIR}/cache" "${ROOT_MNT}/tmp/pistomp-arch/"

# ---------- run build scripts ----------

run_in_chroot "scripts/00-base.sh"
run_in_chroot "scripts/01-system.sh"
run_in_chroot "scripts/02-audio.sh"
run_in_chroot "scripts/03-pistomp.sh"
run_in_chroot "scripts/04-cleanup.sh"

# ---------- finalize ----------

log "Unmounting..."
cleanup

# Remove qemu from image
if [[ "$(uname -m)" != "aarch64" ]]; then
    # Re-mount briefly to remove qemu
    mount "${ROOT_PART}" "${ROOT_MNT}"
    rm -f "${ROOT_MNT}/usr/bin/qemu-aarch64-static"
    umount "${ROOT_MNT}"
fi

# Compress
TIMESTAMP=$(date +%Y-%m-%d)
OUTPUT="${DEPLOY_DIR}/${IMG_NAME}-${TIMESTAMP}.img.zst"
log "Compressing image to ${OUTPUT}..."
zstd -T0 -19 "${IMG_FILE}" -o "${OUTPUT}"

log "Build complete: ${OUTPUT}"
log "Image size: $(du -h "${OUTPUT}" | cut -f1)"
