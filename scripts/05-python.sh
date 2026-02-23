#!/bin/bash
set -euo pipefail

echo "==> 05-python: Python environments and applications"

PISTOMP_DIR="/opt/pistomp"
VENV_BASE="${PISTOMP_DIR}/venvs"
PATCHES="/root/pistomp-arch/patches"
UV_BIN="${PISTOMP_DIR}/bin/uv"

mkdir -p "${VENV_BASE}"

# ---------- Python 3.11 (prebuilt via uv, for mod-ui/browsepy/touchosc2midi) ----------

UV_PYTHON_DIR="${PISTOMP_DIR}/python"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_DIR}"

echo "==> Installing Python ${PYTHON_VERSION} (prebuilt)..."
"${UV_BIN}" python install "${PYTHON_VERSION}"

PYTHON_BIN=$("${UV_BIN}" python find "${PYTHON_VERSION}")

# ---------- Python virtualenvs ----------

create_venv() {
    local name="$1"
    echo "==> Creating venv: ${name}..."
    "${UV_BIN}" venv --python "${PYTHON_BIN}" "${VENV_BASE}/${name}"
}

# ------------------------------------------------------------------------------------
# ---------- mod-ui ----------

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

# ------------------------------------------------------------------------------------
# ---------- pi-stomp ----------

echo "==> Installing pi-stomp..."
# pi-stomp venv uses system Python to access system C extensions
# (lilv, smbus, gpiod, lgpio)
"${UV_BIN}" venv --python /usr/bin/python3 --system-site-packages "${VENV_BASE}/pi-stomp"

git clone --depth 1 -b "${PISTOMP_BRANCH}" "${PISTOMP_REPO}" "/home/${FIRST_USER}/pi-stomp"

# Pre-install ALSA state so alsa-restore loads correct mixer settings on first boot
# (before firstboot.service runs). Without this, the IQAudio DAC doesn't clock and JACK times out.
mkdir -p /var/lib/alsa
cp "/home/${FIRST_USER}/pi-stomp/setup/audio/iqaudiocodec.state" /var/lib/alsa/asound.state

# swig is needed to build lgpio from PyPI sdist (no cp314 wheel yet)
pacman -S --noconfirm --needed swig

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

# ------------------------------------------------------------------------------------
# ---------- browsepy ----------

echo "==> Installing browsepy..."
create_venv "browsepy"

"${UV_BIN}" pip install --python "${VENV_BASE}/browsepy/bin/python" \
    "browsepy @ git+${BROWSEPY_REPO}"

# ------------------------------------------------------------------------------------
# ---------- touchosc2midi ----------

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

echo "==> 05-python: Done"
