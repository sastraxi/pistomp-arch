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

    local build_dir="/tmp/build-${pkg}"
    cp -r "${PKGBUILDS}/${pkg}" "${build_dir}"
    chown -R builduser:builduser "${build_dir}"
    pushd "${build_dir}" > /dev/null

    # Export repo/branch configuration so PKGBUILDs can read it as the
    # single source of truth (config.sh). Each PKGBUILD uses defaults so
    # these are optional, but providing them keeps image builds and
    # deploy-pkg.sh in sync with config.sh.
    cat > "${build_dir}/.env" <<EOF
export PISTOMP_REPO='${PISTOMP_REPO:-}'
export PISTOMP_BRANCH='${PISTOMP_BRANCH:-}'
export MODUI_REPO='${MODUI_REPO:-}'
export MODUI_BRANCH='${MODUI_BRANCH:-}'
export MOD_HOST_REPO='${MOD_HOST_REPO:-}'
export MOD_HOST_BRANCH='${MOD_HOST_BRANCH:-}'
export RECOVERY_REPO='${RECOVERY_REPO:-}'
export RECOVERY_BRANCH='${RECOVERY_BRANCH:-}'
EOF

    local _pkgname _pkgver _pkgrel _has_pkgver
    _pkgname=$(bash -c "source ${build_dir}/PKGBUILD && echo \$pkgname")
    _pkgrel=$(bash -c "source ${build_dir}/PKGBUILD && echo \$pkgrel")
    # VCS packages compute pkgver() from the fetched checkout, so the static
    # pkgver= in the PKGBUILD is just a placeholder. Detect the function and, if
    # present, fetch sources + run pkgver() (makepkg -o rewrites the pkgver= line
    # in this build copy) so the cache key matches the real built filename.
    _has_pkgver=$(bash -c "source ${build_dir}/PKGBUILD && type -t pkgver" || true)
    if [[ "${_has_pkgver}" == "function" ]]; then
        echo "==> Resolving dynamic pkgver: ${pkg}..."
        su builduser -c "source ${build_dir}/.env && makepkg -od --noconfirm"
    fi
    _pkgver=$(bash -c "source ${build_dir}/PKGBUILD && echo \$pkgver")

    local cached
    cached=$(compgen -G "${PKG_CACHE}/${_pkgname}-${_pkgver}-${_pkgrel}-*.pkg.tar.*" | head -1) || true

    if [[ -n "${cached}" ]]; then
        echo "==> Installing cached package: ${pkg} (${_pkgver}-${_pkgrel})"
        pacman -U --noconfirm "${cached}"
        popd > /dev/null
        rm -rf "${build_dir}"
        return
    fi

    echo "==> Building PKGBUILD: ${pkg} (${_pkgver}-${_pkgrel})..."
    # -e (noextract) reuses the checkout already fetched above for VCS packages;
    # harmless for the rest since nothing was extracted yet.
    if [[ "${_has_pkgver}" == "function" ]]; then
        su builduser -c "source ${build_dir}/.env && makepkg -es --noconfirm"
    else
        su builduser -c "source ${build_dir}/.env && makepkg -s --noconfirm"
    fi
    pacman -U --noconfirm "${build_dir}"/*.pkg.tar.*
    # Cache the built package for next time
    cp "${build_dir}"/*.pkg.tar.* "${PKG_CACHE}/"
    popd > /dev/null
    rm -rf "${build_dir}"
}

# Built first so it replaces stock jack2 before anything else links against
# libjack. Carries the netadapter PI-controller integrator-reset fix.
# We explicitly remove stock jack2 if present to avoid conflicts during installation.
pacman -Rdd --noconfirm jack2 2>/dev/null || true
build_pkg "jack2-pistomp"

# Now that jack2-pistomp provides jack, we can install the example tools
pacman -S --noconfirm --needed jack-example-tools

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

# Bundled relocatable Python 3.11 for mod-ui. Built before mod-ui so its venv
# can be created against /opt/pistomp/python311.
build_pkg "pistomp-python311"

# Application packages. pi-stomp builds a --system-site-packages venv on the
# system python; mod-ui builds on the bundled 3.11. Both ship their venv + the
# runtime-needed source assets under /opt/pistomp (see their PKGBUILDs).
build_pkg "pi-stomp"
build_pkg "mod-ui"

build_pkg "pistomp-recovery"

# allows capturing audio while JACK is running
build_pkg "jack_capture"

echo "==> 04-native-pkgs: Done"
