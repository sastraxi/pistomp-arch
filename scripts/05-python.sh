#!/bin/bash
set -euo pipefail

echo "==> 05-python: Python environments and applications"

PISTOMP_DIR="/opt/pistomp"
VENV_BASE="${PISTOMP_DIR}/venvs"
UV_BIN="${PISTOMP_DIR}/bin/uv"

mkdir -p "${VENV_BASE}"

# ---------- Python 3.11 (provided by the pistomp-python311 package) ----------

# mod-ui and pi-stomp are now pacman packages built in 04-native-pkgs.sh.
# The bundled Python 3.11 they (and browsepy/touchosc2midi) need ships as the
# pistomp-python311 package, installed at a fixed /opt path.
PYTHON_BIN="/opt/pistomp/python311/bin/python3.11"

# ---------- Python virtualenvs ----------

create_venv() {
    local name="$1"
    echo "==> Creating venv: ${name}..."
    "${UV_BIN}" venv --python "${PYTHON_BIN}" "${VENV_BASE}/${name}"
}

# mod-ui and pi-stomp are now built as pacman packages (pkgbuilds/mod-ui,
# pkgbuilds/pi-stomp) in 04-native-pkgs.sh, so they no longer install here.
# The ~/pi-stomp symlink and the ALSA asound.state seeding live in 06-app-data.sh.

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
