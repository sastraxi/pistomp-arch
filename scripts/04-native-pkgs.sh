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

PKG_CACHE="/root/pistomp-arch/cache/pkgs"
mkdir -p "${PKG_CACHE}"

build_pkg() {
    local pkg="$1"

    # Check cache: extract expected filename from PKGBUILD metadata
    local build_dir="/tmp/build-${pkg}"
    cp -r "${PKGBUILDS}/${pkg}" "${build_dir}"
    local _pkgname _pkgver _pkgrel
    _pkgname=$(bash -c "source ${build_dir}/PKGBUILD && echo \$pkgname")
    _pkgver=$(bash -c "source ${build_dir}/PKGBUILD && echo \$pkgver")
    _pkgrel=$(bash -c "source ${build_dir}/PKGBUILD && echo \$pkgrel")
    local cached
    cached=$(compgen -G "${PKG_CACHE}/${_pkgname}-${_pkgver}-${_pkgrel}-*.pkg.tar.*" | head -1) || true

    if [[ -n "${cached}" ]]; then
        echo "==> Installing cached package: ${pkg} (${_pkgver}-${_pkgrel})"
        pacman -U --noconfirm "${cached}"
        rm -rf "${build_dir}"
        return
    fi

    echo "==> Building PKGBUILD: ${pkg}..."
    chown -R builduser:builduser "${build_dir}"
    pushd "${build_dir}" > /dev/null
    su builduser -c "makepkg -s --noconfirm"
    pacman -U --noconfirm "${build_dir}"/*.pkg.tar.*
    # Cache the built package for next time
    cp "${build_dir}"/*.pkg.tar.* "${PKG_CACHE}/"
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

# lg's SWIG module installs against system python3 (/usr/bin/python3).
build_pkg "lg"

build_pkg "lcd-splash"

echo "==> 04-native-pkgs: Done"
