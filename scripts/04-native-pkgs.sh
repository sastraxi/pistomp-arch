#!/bin/bash
set -euo pipefail

echo "==> 04-native-pkgs: Building native PKGBUILDs"

PISTOMP_DIR="/opt/pistomp"
PKGBUILDS="/root/pistomp-arch/pkgbuilds"

mkdir -p "${PISTOMP_DIR}"

# ---------- uv ----------

echo "==> Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="${PISTOMP_DIR}/bin" INSTALLER_NO_MODIFY_PATH=1 sh

# ---------- native PKGBUILDs ----------

echo "==> Installing build tools for PKGBUILDs..."
pacman -S --needed --noconfirm base-devel

echo "==> Enabling parallel compilation..."
sed -i 's/^#MAKEFLAGS=.*/MAKEFLAGS="-j$(nproc)"/' /etc/makepkg.conf

build_pkg() {
    local pkg="$1"
    echo "==> Building PKGBUILD: ${pkg}..."
    local build_dir="/tmp/build-${pkg}"
    cp -r "${PKGBUILDS}/${pkg}" "${build_dir}"
    chown -R builduser:builduser "${build_dir}"
    pushd "${build_dir}" > /dev/null
    su builduser -c "makepkg -s --noconfirm"
    pacman -U --noconfirm "${build_dir}"/*.pkg.tar.*
    popd > /dev/null
    rm -rf "${build_dir}"
}

build_pkg "hylia"
build_pkg "mod-host-pistomp"
build_pkg "sfizz-pistomp"
build_pkg "amidithru"
build_pkg "mod-midi-merger"
build_pkg "mod-ttymidi"
build_pkg "fluidsynth-headless"    # builds without SDL (no X11 deps)
build_pkg "libfluidsynth2-compat"  # just symlinks -2 to -3

# lg must be built before pyenv is set up, so python3 resolves to
# /usr/bin/python3 (system 3.14) and the SWIG module installs there.
build_pkg "lg"

echo "==> 04-native-pkgs: Done"
