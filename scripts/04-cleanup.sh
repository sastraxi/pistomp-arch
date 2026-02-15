#!/bin/bash
set -euo pipefail

echo "==> 04-cleanup: Cleaning up"

# Debug: verify service files survived from 03-pistomp.sh
echo "==> [debug] Service files before cleanup:"
ls -la /usr/lib/systemd/system/{jack,mod-host,mod-ui,browsepy,mod-amidithru,mod-ala-pi-stomp,firstboot}.service 2>&1

# ---------- remove build dependencies (optional) ----------

# Keep base-devel for now — some pip packages with C extensions may
# need recompilation on the device. Remove manually if not needed:
#   pacman -Rns $(pacman -Qqdt) --noconfirm

# ---------- clear package cache ----------

pacman -Scc --noconfirm

# ---------- clear temporary files ----------

# Preserve cache/ (bind-mounted from host) — only delete project copies
rm -rf /root/pistomp-arch/files
rm -rf /root/pistomp-arch/pkgbuilds
rm -rf /root/pistomp-arch/patches
rm -rf /tmp/build-*
rm -rf /tmp/mod-ui
rm -rf /var/log/journal/*
rm -rf /var/cache/pacman/pkg/*

# ---------- remove docs, locales, and other unneeded files ----------
rm -rf /usr/share/doc/*
rm -rf /usr/share/man/*
# Keep en_US and C locales, remove all others
find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en_US' ! -name 'C' -exec rm -rf {} +


# ---------- clear Python caches ----------

find /opt/pistomp -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find /home -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
rm -rf /root/.cache/uv

# ---------- remove qemu (will also be removed by build.sh) ----------

rm -f /usr/bin/qemu-aarch64-static

# ---------- remove pyenv build cache ----------

rm -rf /opt/pistomp/pyenv/cache/*
rm -rf /opt/pistomp/pyenv/sources/*

# Debug: verify service files survived cleanup
echo "==> [debug] Service files after cleanup:"
ls -la /usr/lib/systemd/system/{jack,mod-host,mod-ui,browsepy,mod-amidithru,mod-ala-pi-stomp,firstboot}.service 2>&1

echo "==> 04-cleanup: Done"
echo "==> Build complete!"
