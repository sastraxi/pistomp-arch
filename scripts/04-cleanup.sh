#!/bin/bash
set -euo pipefail

echo "==> 04-cleanup: Cleaning up"

# ---------- remove build dependencies (optional) ----------

# Keep base-devel for now — some pip packages with C extensions may
# need recompilation on the device. Remove manually if not needed:
#   pacman -Rns $(pacman -Qqdt) --noconfirm

# ---------- clear package cache ----------

pacman -Scc --noconfirm

# ---------- clear temporary files ----------

rm -rf /tmp/pistomp-arch
rm -rf /tmp/build-*
rm -rf /tmp/mod-ui
rm -rf /var/log/journal/*
rm -rf /var/cache/pacman/pkg/*

# ---------- clear Python caches ----------

find /opt/pistomp -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find /home -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# ---------- remove qemu (will also be removed by build.sh) ----------

rm -f /usr/bin/qemu-aarch64-static

# ---------- remove pyenv build cache ----------

rm -rf /opt/pistomp/pyenv/cache/*
rm -rf /opt/pistomp/pyenv/sources/*

echo "==> 04-cleanup: Done"
echo "==> Build complete!"
