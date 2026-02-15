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

# ---------- build docker image ----------

if [[ "${1:-}" == "--rebuild" ]] || ! docker image inspect pistomp-arch-builder &>/dev/null; then
    echo "==> Building Docker image..."
    docker buildx build --load -t pistomp-arch-builder "${SCRIPT_DIR}"
else
    echo "==> Using existing Docker image (pass --rebuild to force)"
fi

# ---------- run build ----------

echo "==> Starting build in Docker..."
mkdir -p "${SCRIPT_DIR}/deploy"

TIMESTAMP=$(date +%Y-%m-%d)
LOG_FILE="${SCRIPT_DIR}/deploy/build-${TIMESTAMP}.log"

docker run --rm --privileged \
    -e "BUILD_TIMESTAMP=${TIMESTAMP}" \
    -v "${SCRIPT_DIR}:/build" \
    pistomp-arch-builder 2>&1 | tee "${LOG_FILE}"

echo "==> Done. Image in deploy/, log at ${LOG_FILE}"
