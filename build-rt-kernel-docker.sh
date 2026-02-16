#!/bin/bash
set -euo pipefail

# Standalone RT kernel builder
# Builds the linux-rpi-rt kernel packages and saves them to cache/
# These cached packages will be reused by the main build process

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

CACHE_DIR="${SCRIPT_DIR}/cache"
mkdir -p "${CACHE_DIR}"

# Check if packages already exist
if compgen -G "${CACHE_DIR}/linux-rpi-rt-*.pkg.tar.*" > /dev/null; then
    echo "==> RT kernel packages already cached:"
    ls -lh "${CACHE_DIR}"/linux-rpi-rt-*.pkg.tar.*
    echo ""
    echo "These packages were built at:"
    stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${CACHE_DIR}"/linux-rpi-rt-*.pkg.tar.* 2>/dev/null || \
        stat -c "%y" "${CACHE_DIR}"/linux-rpi-rt-*.pkg.tar.* 2>/dev/null | cut -d. -f1
    echo ""
    read -p "Rebuild? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "==> Keeping existing cached packages"
        exit 0
    fi
    echo "==> Removing old cached packages..."
    rm -f "${CACHE_DIR}"/linux-rpi-rt-*.pkg.tar.*
fi

# Clean up previous build artifacts on host (prevents permission issues with Docker bind mounts)
RT_BUILD_DIR="${SCRIPT_DIR}/pkgbuilds/linux-rpi-rt"
if [[ -d "${RT_BUILD_DIR}/pkg" ]] || [[ -d "${RT_BUILD_DIR}/src" ]]; then
    echo "==> Cleaning previous build artifacts on host..."
    chmod -R u+rwX "${RT_BUILD_DIR}/pkg" "${RT_BUILD_DIR}/src" 2>/dev/null || true
    rm -rf "${RT_BUILD_DIR}/pkg" "${RT_BUILD_DIR}/src"
    rm -f "${RT_BUILD_DIR}"/*.tar.* "${RT_BUILD_DIR}"/*.pkg.tar.* 2>/dev/null || true
fi

# Build kernel in Docker
echo "==> Building RT kernel in Docker (30+ minutes)..."
echo ""

# Ensure Docker image exists
if ! docker image inspect pistomp-arch-builder &>/dev/null; then
    echo "==> Docker image not found, building it first..."
    docker buildx build --load -t pistomp-arch-builder "${SCRIPT_DIR}"
fi

# Run kernel build in a container (without --rm so you can inspect on failure)
# We override the entrypoint to run ONLY the kernel build, not the full image build
CONTAINER_NAME="pistomp-rt-kernel-build-$$"

docker run --name "${CONTAINER_NAME}" --privileged \
    --entrypoint /bin/bash \
    -v "${SCRIPT_DIR}:/build" \
    pistomp-arch-builder \
    -c "
        set -euo pipefail

        # Install build dependencies
        pacman -S --needed --noconfirm base-devel bc kmod inetutils xmlto docbook-xsl git patch

        # Create builduser (required for makepkg)
        useradd -m -G wheel builduser
        echo 'builduser ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builduser

        # Prepare and build
        cd /build/pkgbuilds/linux-rpi-rt
        chmod a+x /build /build/pkgbuilds

        echo '==> Preparing RT kernel PKGBUILD...'
        ./build-rt-kernel.sh

        # Copy to /tmp to avoid macOS bind mount permission issues
        echo '==> Copying to container-local directory to avoid permission issues...'
        cp -r /build/pkgbuilds/linux-rpi-rt /tmp/linux-rpi-rt
        cd /tmp/linux-rpi-rt

        chown -R builduser:builduser .

        echo '==> Building RT kernel packages...'
        # Enable parallel compilation (use all available CPUs)
        sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS=\"-j\$(nproc)\"/' /etc/makepkg.conf
        echo \"Using \$(nproc) CPUs for parallel compilation\"
        su builduser -c 'makepkg -s --noconfirm'

        echo '==> Copying packages to cache...'
        cp linux-rpi-rt-*.pkg.tar.* /build/cache/
    "

BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "==> RT kernel packages built and cached successfully:"
    ls -lh "${CACHE_DIR}"/linux-rpi-rt-*.pkg.tar.*
    echo ""
    echo "These packages will be used automatically by ./build-docker.sh"
    echo "bypassing the kernel compilation step."

    echo ""
    echo "==> Removing build container..."
    docker rm "${CONTAINER_NAME}"
else
    echo ""
    echo "==> Build failed! Container '${CONTAINER_NAME}' preserved for inspection."
    echo "To inspect: docker exec -it ${CONTAINER_NAME} /bin/bash"
    echo "To remove:  docker rm ${CONTAINER_NAME}"
    exit $BUILD_EXIT_CODE
fi
