#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# ---------- download cache ----------

mkdir -p "${SCRIPT_DIR}/cache"

if [[ ! -f "${SCRIPT_DIR}/cache/lv2plugins.tar.gz" ]]; then
    echo "==> Downloading LV2 plugins..."
    curl -L -o "${SCRIPT_DIR}/cache/lv2plugins.tar.gz" "${LV2_PLUGINS_URL}"
fi

ALARM_CACHE="${SCRIPT_DIR}/cache/alarm-aarch64.tar.gz"
if [[ ! -f "${ALARM_CACHE}" ]]; then
    echo "==> Downloading ALARM tarball..."
    curl -L -o "${ALARM_CACHE}" "${ALARM_TARBALL_URL}"
fi

# ---------- build docker image ----------

echo "==> Building Docker image..."
docker build -t pistomp-arch-builder "${SCRIPT_DIR}"

# ---------- run build ----------

echo "==> Starting build in Docker..."
mkdir -p "${SCRIPT_DIR}/deploy"

docker run --rm --privileged \
    -v "${SCRIPT_DIR}:/build" \
    pistomp-arch-builder

echo "==> Done. Image in deploy/"
