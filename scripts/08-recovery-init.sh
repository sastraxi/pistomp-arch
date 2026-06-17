#!/bin/bash
set -euo pipefail

echo "==> 08-recovery-init: Initialize recovery git repos and factory state"

FIRST_USER="${FIRST_USER:-pistomp}"
PISTOMP_HOME="/home/${FIRST_USER}"
RECOVERY_DIR="${PISTOMP_HOME}/.pistomp-recovery"
PEDALBOARDS_DIR="${PISTOMP_HOME}/data/.pedalboards"

# Use the venv Python that has pistomp-recovery installed
VENV_PYTHON="/opt/pistomp/venvs/pistomp-recovery/bin/python"

# Create the recovery directory so pistomp-recovery can write its package
# stamp and initialize its git repos at runtime.
mkdir -p "${RECOVERY_DIR}"

# ---------- pedalboards repo ----------
echo "==> Initializing pedalboards git repo..."
if [[ -d "${PEDALBOARDS_DIR}" ]]; then
    cd "${PEDALBOARDS_DIR}"
    if [[ ! -d ".git" ]]; then
        git init --initial-branch device
        git config user.email "recovery@pistomp.local"
        git config user.name "pistomp-recovery"
        git add -A
        git commit -m "factory pedalboards state"
        git branch factory
    fi
    cd - > /dev/null
fi

# ---------- factory packages list ----------
echo "==> Writing factory packages list..."
FACTORY_PKGS="/etc/pistomp/factory-packages.list"
mkdir -p "$(dirname "${FACTORY_PKGS}")"

# Build a JSON dict of all tracked package versions
{
    echo "{"
    first=true
    for pkg in jack2-pistomp mod-host-pistomp mod-midi-merger mod-ttymidi \
               amidithru fluidsynth-headless libfluidsynth2-compat lg \
               lcd-splash sfizz-pistomp jack_capture hylia pi-stomp \
               mod-ui pistomp-recovery; do
        ver=$(pacman -Q "${pkg}" 2>/dev/null | awk '{print $2}' || echo "not-installed")
        if [[ "${first}" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        printf '  "%s": "%s"' "${pkg}" "${ver}"
    done
    echo ""
    echo "}"
} > "${FACTORY_PKGS}"

# ---------- packages stamp file ----------
echo "==> Writing initial packages stamp..."
# The stamp file starts identical to factory — pi-stomp will update it
# when it successfully loads a pedalboard
cp "${FACTORY_PKGS}" "${RECOVERY_DIR}/packages.stamp"

# ---------- ownership ----------
chown -R "${FIRST_USER}:${FIRST_USER}" "${RECOVERY_DIR}"
chown -R "${FIRST_USER}:${FIRST_USER}" "${PEDALBOARDS_DIR}"

echo "==> 08-recovery-init: Done"
