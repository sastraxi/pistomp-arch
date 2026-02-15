# pistomp-arch

Builds a bootable Arch Linux ARM image for [pi-Stomp](https://github.com/TreeFallSound/pi-stomp) guitar pedal hardware.

Supports Raspberry Pi 3, 4, and 5.

## Quick Start

```bash
# Build image (Docker, works on macOS/Linux)
./build-docker.sh

# Output: deploy/pistompOS-arch-<date>.img.zst
```

Requires Docker with [buildx](https://docs.docker.com/build/buildx/install/). On macOS with Homebrew: `brew install docker-buildx` and add `"cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"]` to `~/.docker/config.json`. First run downloads ~500MB of base OS + LV2 plugins into `cache/`.

## What's in the Image

- **Arch Linux ARM** with stock `linux-rpi` kernel
- **JACK2** + `jack-example-tools` (from pacman)
- **lilv/serd/sord/sratom/lv2** (from pacman, including Python bindings)
- **mod-host**, **mod-ui**, **browsepy**, **amidithru**, **ttymidi**, **mod-midi-merger**
- **pyenv** + Python 3.11 + per-app virtualenvs at `/opt/pistomp/venvs/`
- Pre-installed LV2 plugins + default pedalboards

## How the Build Works

The build is two-stage: **host-side image setup** followed by **chroot configuration**.

1. **Image creation (host)** — `build.sh` creates a raw `.img` file, partitions it (FAT32 boot + ext4 root), attaches it as a loop device via `losetup`/`kpartx`, and mounts the partitions.
2. **pacstrap (host)** — Installs a fresh Arch Linux ARM rootfs directly from ALARM mirrors into the mounted image. No pre-built tarball needed.
3. **Chroot scripts (target)** — `arch-chroot` enters the rootfs and runs the numbered scripts (`00-base.sh` through `04-cleanup.sh`) sequentially. These configure the system as if running on the Pi itself.
4. **Finalize (host)** — Unmounts everything, detaches the loop device, and compresses the image with zstd.

When running via `build-docker.sh`, the entire process happens inside a privileged Docker container (an aarch64 Arch Linux image with `arch-install-scripts`). The host only needs Docker.

## Build Scripts

| Script | Phase |
|--------|-------|
| `00-base.sh` | Pacman init, kernel, locale, users |
| `01-system.sh` | Networking, SSH, GPIO, authbind |
| `02-audio.sh` | JACK2, LV2 stack, ALSA config, RT limits |
| `03-pistomp.sh` | pyenv, uv, PKGBUILDs, venvs, app data, services |
| `04-cleanup.sh` | Clear caches, remove build artifacts |

## Flashing

Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (select "Use custom" .img) or `dd`.

After flashing, mount the boot partition (FAT32 — auto-mounts on Mac/Windows/Linux) and edit **`pistomp.conf`**:

```ini
WIFI_SSID="MyNetwork"
WIFI_PASSWORD="secret"
SSH_AUTHORIZED_KEY="ssh-ed25519 AAAA..."
```

Settings are applied on first boot. See the file for all options (hostname, timezone, password).

## RT Kernel

The image ships with a standard (non-RT) kernel. See [docs/rt-kernel.md](docs/rt-kernel.md) for options — since Linux 6.12, PREEMPT_RT is a config flag, no patch needed.

## Direct Build (Linux only)

```bash
# Download LV2 plugins cache first
mkdir -p cache
curl -L -o cache/lv2plugins.tar.gz https://www.treefallsound.com/downloads/lv2plugins.tar.gz

# Build as root (requires arch-install-scripts, parted, dosfstools, e2fsprogs, multipath-tools)
sudo ./build.sh
```
