#!/bin/bash
set -euo pipefail

echo "==> 03-pistomp: Application stack"

PISTOMP_DIR="/opt/pistomp"
PYENV_ROOT="${PISTOMP_DIR}/pyenv"
VENV_BASE="${PISTOMP_DIR}/venvs"
FILES="/root/pistomp-arch/files"
PKGBUILDS="/root/pistomp-arch/pkgbuilds"
PATCHES="/root/pistomp-arch/patches"

mkdir -p "${PISTOMP_DIR}" "${VENV_BASE}"

# ---------- uv ----------

echo "==> Installing uv..."
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="${PISTOMP_DIR}/bin" INSTALLER_NO_MODIFY_PATH=1 sh
UV_BIN="${PISTOMP_DIR}/bin/uv"

# ---------- native PKGBUILDs ----------

echo "==> Building native PKGBUILDs..."

# Create a build user (makepkg refuses to run as root)
useradd -m -s /bin/bash builduser 2>/dev/null || true
echo "builduser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builduser

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
build_pkg "libfluidsynth2-compat"

# lg must be built before pyenv is set up, so python3 resolves to
# /usr/bin/python3 (system 3.14) and the SWIG module installs there.
build_pkg "lg"

# ---------- pyenv (for mod-ui, browsepy, touchosc2midi only) ----------

echo "==> Installing pyenv..."
git clone --depth 1 https://github.com/pyenv/pyenv.git "${PYENV_ROOT}"

export PYENV_ROOT
export PATH="${PYENV_ROOT}/bin:${PYENV_ROOT}/shims:${PATH}"

# Install Python build dependencies
pacman -S --noconfirm --needed \
    openssl zlib xz tk sqlite bzip2 readline libffi 7zip

# Build Python
echo "==> Building Python ${PYTHON_VERSION}..."
pyenv install "${PYTHON_VERSION}"
pyenv global "${PYTHON_VERSION}"

# ---------- Python virtualenvs ----------

PYTHON_BIN="${PYENV_ROOT}/versions/${PYTHON_VERSION}/bin/python"

create_venv() {
    local name="$1"
    echo "==> Creating venv: ${name}..."
    "${UV_BIN}" venv --python "${PYTHON_BIN}" "${VENV_BASE}/${name}"
}

# --- mod-ui ---

echo "==> Installing mod-ui..."
create_venv "mod-ui"

git clone --depth 1 -b "${MODUI_BRANCH}" "${MODUI_REPO}" /tmp/mod-ui

# Apply patches
if [[ -d "${PATCHES}/mod-ui" ]]; then
    for patch in "${PATCHES}"/mod-ui/*.patch; do
        [[ -f "$patch" ]] && git -C /tmp/mod-ui apply "$patch"
    done
fi

# mod-ui's setup.py declares bogus dependency names (tornado4, pil, pycrypto)
# Install the real packages first, then install mod-ui with --no-deps
MODUI_PYTHON="${VENV_BASE}/mod-ui/bin/python"
"${UV_BIN}" pip install --python "${MODUI_PYTHON}" \
    tornado==4.3 pillow pystache pycryptodome aggdraw pyserial

# Patch tornado 4.3 for Python 3.11+ (collections.MutableMapping moved to collections.abc)
TORNADO_DIR=$("${MODUI_PYTHON}" -c "import tornado, os; print(os.path.dirname(tornado.__file__))")
sed -i 's/collections\.MutableMapping/collections.abc.MutableMapping/g' "${TORNADO_DIR}/httputil.py"

# Install mod-ui as editable, skip broken dependency resolution
"${UV_BIN}" pip install --python "${MODUI_PYTHON}" \
    --no-deps -e /tmp/mod-ui

# Build libmod_utils.so (native C library used by modtools/utils.py)
make -C /tmp/mod-ui/utils clean
make -C /tmp/mod-ui/utils

# Move source to permanent location and re-install
mv /tmp/mod-ui "${PISTOMP_DIR}/mod-ui"
"${UV_BIN}" pip install --python "${MODUI_PYTHON}" \
    --no-deps -e "${PISTOMP_DIR}/mod-ui"

# --- pi-stomp ---

echo "==> Installing pi-stomp..."
# pi-stomp venv uses system Python to access system C extensions
# (lilv, smbus, gpiod, lgpio)
"${UV_BIN}" venv --python /usr/bin/python3 --system-site-packages "${VENV_BASE}/pi-stomp"

git clone --depth 1 -b "${PISTOMP_BRANCH}" "${PISTOMP_REPO}" "/home/${FIRST_USER}/pi-stomp"

# Pre-install ALSA state so alsa-restore loads correct mixer settings on first boot
# (before firstboot.service runs). Without this, the IQAudio DAC doesn't clock and JACK times out.
mkdir -p /var/lib/alsa
cp "/home/${FIRST_USER}/pi-stomp/setup/audio/iqaudiocodec.state" /var/lib/alsa/asound.state

# Create a dummy rpi-gpio package to satisfy dependencies that haven't
# migrated to rpi-lgpio yet (like cap1xxx via gfxhat). rpi-lgpio provides the 
# actual RPi.GPIO module and is installed as part of [hardware] extras.
mkdir -p /tmp/fake-rpi-gpio
cat > /tmp/fake-rpi-gpio/pyproject.toml <<EOF
[project]
name = "rpi-gpio"
version = "99.9.9"
EOF
"${UV_BIN}" pip install --python "${VENV_BASE}/pi-stomp/bin/python" /tmp/fake-rpi-gpio

# Install pi-stomp and its dependencies from pyproject.toml
"${UV_BIN}" pip install --python "${VENV_BASE}/pi-stomp/bin/python" \
    -e "/home/${FIRST_USER}/pi-stomp[hardware]"

# Pi 5 neopixel support (not declared as a dependency by adafruit-circuitpython-neopixel)
"${UV_BIN}" pip install --python "${VENV_BASE}/pi-stomp/bin/python" \
    Adafruit-Blinka-Raspberry-Pi5-Neopixel

# --- browsepy ---

echo "==> Installing browsepy..."
create_venv "browsepy"

"${UV_BIN}" pip install --python "${VENV_BASE}/browsepy/bin/python" \
    "browsepy @ git+${BROWSEPY_REPO}"

# --- touchosc2midi ---

echo "==> Installing touchosc2midi..."
create_venv "touchosc2midi"

# pyliblo 0.10.0 (pulled by touchosc2midi) is broken with modern liblo
# (lo_blob_dataptr signature changed) and Cython 3. Use pyliblo3, the
# maintained fork, which fixes the liblo API issue.
# Cython 3.1+ removed the `long` builtin that pyliblo3 still uses.
_T2M_PY="${VENV_BASE}/touchosc2midi/bin/python"
"${UV_BIN}" pip install --python "${_T2M_PY}" setuptools "Cython<3.1"
"${UV_BIN}" pip install --python "${_T2M_PY}" --no-build-isolation pyliblo3
"${UV_BIN}" pip install --python "${_T2M_PY}" --no-deps \
    "touchosc2midi @ git+${TOUCHOSC2MIDI_REPO}"
# Install touchosc2midi's remaining deps (everything except pyliblo)
"${UV_BIN}" pip install --python "${_T2M_PY}" \
    python-rtmidi mido docopt netifaces zeroconf

# ---------- application data ----------

echo "==> Installing application data..."

# Pedalboards
git clone --depth 1 -b "${PEDALBOARDS_BRANCH}" "${PEDALBOARDS_REPO}" \
    "/home/${FIRST_USER}/data/.pedalboards"
# modify_version.sh and other scripts expect ~/.pedalboards
ln -sf "/home/${FIRST_USER}/data/.pedalboards" "/home/${FIRST_USER}/.pedalboards"

# User files
git clone --depth 1 -b "${USERFILES_BRANCH}" "${USERFILES_REPO}" \
    "/home/${FIRST_USER}/data/user-files"

# Extras folder (utility scripts for pistomp user)
EXTRAS_SRC="/root/pistomp-arch/extras"
if [[ -d "${EXTRAS_SRC}" ]]; then
    echo "==> Copying extras folder to /home/${FIRST_USER}/extras..."
    cp -r "${EXTRAS_SRC}" "/home/${FIRST_USER}/extras"
    # Make all scripts executable
    find "/home/${FIRST_USER}/extras" -type f -name "*.sh" -exec chmod +x {} \;
fi

# LV2 plugins — must be pre-downloaded in cache/
LV2_CACHE="/root/pistomp-arch/cache/lv2plugins.tar.gz"
[[ -f "${LV2_CACHE}" ]] || { echo "ERROR: LV2 plugins not found at ${LV2_CACHE}. Run ./build-docker.sh first to download." >&2; exit 1; }
echo "==> Installing LV2 plugins from cache..."
tar xzf "${LV2_CACHE}" -C "/home/${FIRST_USER}/" --exclude='._*'
ln -sf "/home/${FIRST_USER}/.lv2" "/home/${FIRST_USER}/data/.lv2"

# ---------- last.json generation ----------

echo "==> Generating last.json..."
DATA_DIR="/home/${FIRST_USER}/data"
LAST_JSON="${DATA_DIR}/last.json"
PEDALBOARDS_DIR="${DATA_DIR}/.pedalboards"

# Find first pedalboard (prefer default.pedalboard if it exists)
if [[ -d "${PEDALBOARDS_DIR}/default.pedalboard" ]]; then
    FIRST_PB="${PEDALBOARDS_DIR}/default.pedalboard"
else
    # Find first .pedalboard directory
    FIRST_PB=$(find "${PEDALBOARDS_DIR}" -maxdepth 1 -name '*.pedalboard' -type d | head -n 1 || true)
fi

if [[ -n "${FIRST_PB}" ]]; then
    echo "{\"bank\": -2, \"pedalboard\": \"${FIRST_PB}\", \"supportsDividers\": true}" > "${LAST_JSON}"
else
    echo "Warning: No pedalboards found, creating empty last.json"
    echo '{"bank": -2, "pedalboard": "", "supportsDividers": true}' > "${LAST_JSON}"
fi

# ---------- fix ownership ----------

chown -R "${FIRST_USER}:${FIRST_USER}" "/home/${FIRST_USER}"
chown -R "${FIRST_USER}:${FIRST_USER}" "${PISTOMP_DIR}"

# ---------- service files ----------

echo "==> Installing service files..."

SYSTEMD_DIR="/usr/lib/systemd/system"
WANTS="/etc/systemd/system/multi-user.target.wants"
mkdir -p "${WANTS}"

for svc in jack mod-host mod-ui browsepy mod-amidithru mod-ala-pi-stomp firstboot; do
    install -v -m 644 "${FILES}/${svc}.service" "${SYSTEMD_DIR}/"
done

# Services enabled by default
for svc in jack mod-host mod-ui browsepy mod-amidithru mod-ala-pi-stomp firstboot; do
    ln -sf "${SYSTEMD_DIR}/${svc}.service" "${WANTS}/"
done

# Services installed but NOT enabled by default
for svc in ttymidi mod-midi-merger mod-midi-merger-broadcaster wifi-hotspot mod-touchosc2midi; do
    if [[ -f "${FILES}/${svc}.service" ]]; then
        install -v -m 644 "${FILES}/${svc}.service" "${SYSTEMD_DIR}/"
    fi
done

# Verify service files are in place
echo "==> Verifying service files in ${SYSTEMD_DIR}:"
ls -la "${SYSTEMD_DIR}"/{jack,mod-host,mod-ui,browsepy,mod-amidithru,mod-ala-pi-stomp,firstboot}.service

# ---------- firstboot script ----------

install -m 755 "${FILES}/firstboot.sh" /boot/firstboot.sh
install -m 644 "${FILES}/pistomp.conf" /boot/pistomp.conf

# ---------- helper scripts ----------

install -m 755 "${FILES}/wait-for-mod-host.sh" /usr/local/bin/wait-for-mod-host.sh

# ---------- touchosc2midi start script ----------

mkdir -p /usr/mod/scripts
install -m 755 "${FILES}/start_touchosc2midi.sh" /usr/mod/scripts/

# ---------- wifi hotspot and wifi check scripts ----------

mkdir -p /usr/lib/pistomp-wifi
for f in enable_wifi_hotspot.sh disable_wifi_hotspot.sh wifi-check.sh; do
    if [[ -f "${FILES}/${f}" ]]; then
        install -m 755 "${FILES}/${f}" /usr/lib/pistomp-wifi/
    fi
done

# wifi-check: falls back to hotspot if WiFi is not connected at boot
install -v -m 644 "${FILES}/wifi-check.service" "${SYSTEMD_DIR}/"
ln -sf "${SYSTEMD_DIR}/wifi-check.service" "${WANTS}/"

# ---------- cleanup build user ----------

userdel -r builduser 2>/dev/null || true
rm -f /etc/sudoers.d/builduser

echo "==> 03-pistomp: Done"
