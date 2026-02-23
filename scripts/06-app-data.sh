#!/bin/bash
set -euo pipefail

echo "==> 06-app-data: Application data and plugins"

PISTOMP_DIR="/opt/pistomp"
FILES="/root/pistomp-arch/files"

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
tar xzf "${LV2_CACHE}" -C "/home/${FIRST_USER}/" --exclude='._*' --warning=no-unknown-keyword
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

echo "==> 06-app-data: Done"
