#!/bin/bash
set -euo pipefail

echo "==> 09-recovery-init: Initialize recovery git repos and factory state"

FIRST_USER="${FIRST_USER:-pistomp}"
PISTOMP_HOME="/home/${FIRST_USER}"
RECOVERY_DIR="${PISTOMP_HOME}/.pistomp-recovery"
PEDALBOARDS_DIR="${PISTOMP_HOME}/data/.pedalboards"
CONFIG_DIR="${PISTOMP_HOME}/data/config"

# Use the venv Python that has pistomp-recovery installed
VENV_PYTHON="/opt/pistomp/venvs/pistomp-recovery/bin/python"

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

# ---------- config repo ----------
echo "==> Initializing config git repo..."
CONFIG_REPO="${RECOVERY_DIR}/config.git"
mkdir -p "${CONFIG_REPO}"
if [[ ! -d "${CONFIG_REPO}/.git" ]]; then
    cd "${CONFIG_REPO}"
    git init --initial-branch device
    git config user.email "recovery@pistomp.local"
    git config user.name "pistomp-recovery"

    # Symlink config files into the repo
    for f in default_config.yml settings.yml; do
        src="${CONFIG_DIR}/${f}"
        if [[ -f "${src}" ]]; then
            ln -s "${src}" "${f}"
        fi
    done

    git add -A
    git commit -m "factory config state"
    git branch factory
    cd - > /dev/null
fi

# ---------- system repo ----------
echo "==> Initializing system git repo..."
SYSTEM_REPO="${RECOVERY_DIR}/system.git"
mkdir -p "${SYSTEM_REPO}"
if [[ ! -d "${SYSTEM_REPO}/.git" ]]; then
    cd "${SYSTEM_REPO}"
    git init --initial-branch device
    git config user.email "recovery@pistomp.local"
    git config user.name "pistomp-recovery"

    # Symlink system files into the repo
    for filepath in /boot/config.txt /boot/cmdline.txt /boot/pistomp.conf /etc/jackdrc /var/lib/alsa/asound.state; do
        if [[ -f "${filepath}" ]]; then
            name=$(basename "${filepath}")
            ln -s "${filepath}" "${name}"
        fi
    done

    git add -A
    git commit -m "factory system config state"
    git branch factory
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

echo "==> 09-recovery-init: Done"
