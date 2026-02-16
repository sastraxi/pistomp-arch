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

## Flashing

Flash with [Raspberry Pi Imager](https://www.raspberrypi.com/software/) (select "Use custom" .img) or `dd`.

**Important:** When Raspberry Pi Imager asks about "OS customization", click **No** — those options are Pi OS-specific and will not work with this image.

After flashing, mount the boot partition (FAT32 — auto-mounts on Mac/Windows/Linux) and edit **`pistomp.conf`**:

```ini
WIFI_SSID="MyNetwork"
WIFI_PASSWORD="secret"
WIFI_COUNTRY="US"
SSH_AUTHORIZED_KEY="ssh-ed25519 AAAA..."
# HOSTNAME="pistomp"
# TIMEZONE="US/Central"
# USER_PASSWORD="pistomp"
```

Insert the SD card and power on. First boot takes a couple of minutes.

## First Boot

On first boot, `firstboot.service` runs automatically and:

1. Applies settings from `pistomp.conf` (WiFi, hostname, timezone, SSH key, password)
2. Expands the root partition to fill the SD card
3. Copies ALSA mixer state for the IQAudio DAC
4. Sets pi-stomp hardware version (v2.0 for Pi 3, v3.0 for Pi 4/5)
5. Reboots

After the reboot, the full service chain starts: JACK → mod-host → mod-ui → pi-stomp. The web UI is available on port 80.

## Debugging

Default credentials: `pistomp` / `pistomp` (SSH enabled).

```bash
ssh pistomp@pistomp.local

# Check service status
systemctl status jack mod-host mod-ui mod-ala-pi-stomp

# Follow logs
journalctl -f -u jack -u mod-host -u mod-ui

# Restart the audio stack
sudo systemctl restart jack    # cascades to all dependent services
```

The WiFi interface is renamed to `wlan0` via udev rule (Arch defaults to `wld0`, but pi-stomp expects `wlan0`).

## What's in the Image

- **Arch Linux ARM** with stock `linux-rpi` kernel
- **JACK2** + `jack-example-tools` (from pacman)
- **lilv/serd/sord/sratom/lv2** (from pacman, including Python bindings)
- **mod-host**, **mod-ui**, **browsepy**, **amidithru**, **ttymidi**, **mod-midi-merger**
- **pyenv** + Python 3.11 + per-app virtualenvs at `/opt/pistomp/venvs/`
- Pre-installed LV2 plugins + default pedalboards

## Service Chain

```
jack.service (user: jack)
  ├─ mod-host.service (user: pistomp)
  │    ├─ mod-ui.service (user: pistomp, port 80)
  │    │    └─ mod-ala-pi-stomp.service (user: pistomp)
  │    └─ browsepy.service (user: pistomp)
  └─ mod-amidithru.service (user: pistomp)
```

Optional services (installed but not enabled): `ttymidi`, `mod-midi-merger`, `mod-midi-merger-broadcaster`, `mod-touchosc2midi`, `wifi-hotspot`.

## Data Layout

```
/home/pistomp/
  pi-stomp/                    # pi-stomp application source
  data/
    .pedalboards/              # Pedalboard files (git repo)
    .lv2 -> ../.lv2            # Symlink to LV2 plugins
    user-files/                # User-uploaded files (browsepy)
    banks.json                 # Bank configuration
    favorites.json, prefs.json # mod-ui state
  .pedalboards -> data/.pedalboards   # Compat symlink
  .lv2/                        # LV2 plugin bundles

/opt/pistomp/
  pyenv/                       # pyenv + Python 3.11
  venvs/{mod-ui,pi-stomp,browsepy,touchosc2midi}/
  mod-ui/                      # mod-ui source tree (editable install)
  bin/uv                       # uv package manager

/etc/jackdrc                   # JACK startup config (owned by jack:jack)
/boot/pistomp.conf             # First-boot user config (FAT32)
```

## Performance

The image ships with a standard (non-RT) kernel. See [docs/rt-kernel.md](docs/rt-kernel.md) for options — since Linux 6.12, PREEMPT_RT is a config flag, no patch needed.

All supported pi-Stomp hardware has 4 homegeneous cores (i.e. A53/A72/A76). We reserve cores 2 and 3 for mod-host and jack to ensure smooth audio playback at all times, at the expense of pedalboard or mod-ui responsiveness.

---

## How the Build Works

The build is two-stage: **host-side image setup** followed by **chroot configuration**.

1. **Image creation (host)** — `build.sh` creates a raw `.img` file, partitions it (FAT32 boot + ext4 root), attaches it as a loop device via `losetup`/`kpartx`, and mounts the partitions.
2. **pacstrap (host)** — Installs a fresh Arch Linux ARM rootfs directly from ALARM mirrors into the mounted image. No pre-built tarball needed.
3. **Chroot scripts (target)** — `arch-chroot` enters the rootfs and runs the numbered scripts (`00-base.sh` through `05-pistomp.sh`) sequentially. These configure the system as if running on the Pi itself.
4. **Finalize (host)** — Unmounts everything, detaches the loop device, and compresses the image with zstd.

When running via `build-docker.sh`, the entire process happens inside a privileged Docker container (an aarch64 Arch Linux image with `arch-install-scripts`). The host only needs Docker.

| Script | Phase |
|--------|-------|
| `00-base.sh` | Pacman init, kernel, locale, users |
| `01-rt-kernel.sh` | Compiles a realtime kernel |
| `02-system.sh` | Networking, SSH, GPIO, authbind |
| `03-audio.sh` | JACK2, LV2 stack, ALSA config, RT limits |
| `04-pistomp.sh` | pyenv, uv, PKGBUILDs, venvs, app data, services |
| `05-cleanup.sh` | Clear caches, remove build artifacts |

## Direct Build (Linux only)

```bash
# Download LV2 plugins cache first
mkdir -p cache
curl -L -o cache/lv2plugins.tar.gz https://www.treefallsound.com/downloads/lv2plugins.tar.gz

# Build as root (requires arch-install-scripts, parted, dosfstools, e2fsprogs, multipath-tools)
sudo ./build.sh
```
