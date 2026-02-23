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

# ---------- build and run ----------

echo "==> Starting build with docker compose..."
mkdir -p "${SCRIPT_DIR}/deploy"

TIMESTAMP=$(date +%Y-%m-%d)
LOG_FILE="${SCRIPT_DIR}/deploy/build-${TIMESTAMP}.log"

if [[ "${1:-}" == "--rebuild" ]]; then
    docker compose build --no-cache builder
fi

BUILD_TIMESTAMP="${TIMESTAMP}" docker compose run --rm builder 2>&1 | tee "${LOG_FILE}"

echo "==> Done. Image in deploy/, log at ${LOG_FILE}"
