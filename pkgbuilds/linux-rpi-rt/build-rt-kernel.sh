#!/bin/bash
set -euo pipefail

# Build linux-rpi-rt kernel package by patching upstream Arch ARM linux-rpi PKGBUILD
#
# This script:
# 1. Downloads the upstream linux-rpi PKGBUILD from a pinned commit
# 2. Downloads required supporting files
# 3. Applies our RT patch
# 4. Adds our RT-specific config
# 5. Prepares for makepkg (actual build happens in calling script)

# Detect script location (works both in chroot and standalone builds)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load config for upstream commit hash
source "${REPO_ROOT}/config.sh"

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# Check we have required files
[[ -f "${SCRIPT_DIR}/linux-rpi-to-rt.patch" ]] || die "Missing linux-rpi-to-rt.patch"
[[ -f "${SCRIPT_DIR}/archarm-rt.diffconfig" ]] || die "Missing archarm-rt.diffconfig"

# Clean previous build artifacts
log "Cleaning previous build artifacts..."
# Force removal with proper permissions (previous builds may have created files as builduser)
chmod -R u+w "${SCRIPT_DIR}/src" "${SCRIPT_DIR}/pkg" 2>/dev/null || true
rm -rf "${SCRIPT_DIR}/src" "${SCRIPT_DIR}/pkg"
rm -f "${SCRIPT_DIR}"/*.tar.* "${SCRIPT_DIR}"/*.pkg.tar.*

# Download upstream PKGBUILD and supporting files
log "Downloading upstream linux-rpi PKGBUILD from commit ${LINUX_RPI_PKGBUILD_COMMIT}"
log "  Base URL: ${LINUX_RPI_PKGBUILD_BASE_URL}"

curl -sSL -o "${SCRIPT_DIR}/PKGBUILD.orig" \
  "${LINUX_RPI_PKGBUILD_BASE_URL}/PKGBUILD"

log "Downloading supporting files..."
for file in cmdline.txt config.txt config8.txt linux.preset \
            0001-Make-proc-cpuinfo-consistent-on-arm64-and-arm.patch \
            archarm.diffconfig linux-rpi.install; do
  log "  - ${file}"
  curl -sSL -o "${SCRIPT_DIR}/${file}" \
    "${LINUX_RPI_PKGBUILD_BASE_URL}/${file}"
done

# Create linux-rpi-rt.install from linux-rpi.install (just rename references)
log "Creating linux-rpi-rt.install..."
sed 's/linux-rpi/linux-rpi-rt/g' "${SCRIPT_DIR}/linux-rpi.install" > "${SCRIPT_DIR}/linux-rpi-rt.install"
rm -f "${SCRIPT_DIR}/linux-rpi.install"

# Apply our RT patch
log "Applying RT patch..."
cd "${SCRIPT_DIR}"
cp PKGBUILD.orig PKGBUILD
patch -p0 < linux-rpi-to-rt.patch

# Apply build optimization patch (optional - disable if you want all features)
log "Applying build time optimizations..."
patch -p0 < disable-heavy-features.patch

# Verify patches applied correctly
if ! grep -q "pkgbase=linux-rpi-rt" PKGBUILD; then
  die "Patch did not apply correctly - pkgbase was not changed"
fi

if ! grep -q "archarm-rt.diffconfig" PKGBUILD; then
  die "Patch did not apply correctly - archarm-rt.diffconfig not added to sources"
fi

log "RT kernel PKGBUILD prepared successfully"
log ""
log "Files in ${SCRIPT_DIR}:"
ls -lh "${SCRIPT_DIR}"/{PKGBUILD,*.diffconfig,*.patch,*.install} 2>/dev/null || true
log ""
log "To build the package, run:"
log "  cd ${SCRIPT_DIR}"
log "  makepkg -s"
log ""
log "Or to build from within a chroot (recommended):"
log "  makepkg -s --noconfirm"
