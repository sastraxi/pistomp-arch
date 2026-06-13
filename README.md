# pistomp-arch

Builds a bootable Arch Linux ARM image for [pi-Stomp](https://github.com/TreeFallSound/pi-stomp) guitar pedal hardware.

Supports Raspberry Pi 3, 4, and 5.

## Prerequisites

Requires Docker with [buildx](https://docs.docker.com/build/buildx/install/).

On macOS with Homebrew: `brew install docker-buildx` and add `"cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"]` to `~/.docker/config.json`.

## Quick Start

### Build RT Kernel (optional)

```bash
./build-rt-kernel-docker.sh

# Output: cache/linux-rpi-rt-<version>-aarch64.pkg.tar.xz
#         cache/linux-rpi-rt-headers-<version>-aarch64.pkg.tar.xz
```

Ensure your docker server has plenty of RAM and CPU available; this took about 25 minutes on an M1 Pro. If the RT kernel is not found at the above path, the build will fallback to the default ALARM non-RT kernel.

### Build Image

```bash
./build-docker.sh

# Output: deploy/pistompOS-arch-<date>.img.zst
```

This will cache pacman-fetched packages via (pacoloco) into `cache/pacman-mirror` and locally-built PKGBUILDs into `cache/pkgs` in order to speed up subsequent builds.

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
# etc.
```

Insert the SD card and power on. First boot takes a couple of minutes.

## First Boot

On first boot, `firstboot.service` runs automatically and:

1. Applies settings from `pistomp.conf` (WiFi, hostname, timezone, SSH key, password)
2. Expands the root partition to fill the SD card
3. Copies ALSA mixer state for the IQAudio DAC
4. Sets pi-stomp hardware version (v2.0 for Pi 3, v3.0 for Pi 4/5)
5. Copies JACK configuration from `pistomp.conf` to `/etc/default/jack`
6. Reboots

After the reboot, the full service chain starts: JACK → mod-host → mod-ui → pi-stomp. The web UI is available on port 80.

## Working with a Running Device

### Updating app code without re-flashing

The two main applications are live git clones — update them with a `git pull`:

```bash
# Update pi-stomp
cd ~/pi-stomp && git pull

# Update mod-ui (editable install at /opt/pistomp/mod-ui)
cd /opt/pistomp/mod-ui && git pull

# Restart affected services
sudo systemctl restart mod-ala-pi-stomp   # pi-stomp only
sudo systemctl restart mod-ui             # mod-ui (cascades to pi-stomp)
sudo systemctl restart jack               # full audio stack restart
```

**Note:** If build-time patches were applied to mod-ui (see `patches/mod-ui/`), a `git pull` may conflict. Resolve manually or re-flash if the patch is structural.

For system packages, standard pacman works:

```bash
sudo pacman -Syu
```

Native C components (mod-host, etc.) are pacman packages — to rebuild one, copy the relevant PKGBUILD from `pkgbuilds/` and run `makepkg -si`.

### Adding a Python dependency to the pi-stomp venv

The pi-stomp venv is at `/opt/pistomp/venvs/pi-stomp/` (system Python, `--system-site-packages`). Install directly with `uv`, which is bundled at `/opt/pistomp/bin/uv`:

```bash
sudo /opt/pistomp/bin/uv pip install --python /opt/pistomp/venvs/pi-stomp/bin/python <package>
```

To make it permanent in the image, add the package to pi-stomp's `pyproject.toml`.

---

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

- **Arch Linux ARM** with either stock `linux-rpi` kernel or `linux-rpi-rt` kernel (if built)
- **JACK2** + `jack-example-tools` (from pacman)
- **lilv/serd/sord/sratom/lv2** (from pacman, including Python bindings)
- **mod-host**, **mod-ui**, **browsepy**, **amidithru**, **ttymidi**, **mod-midi-merger**
- **sfizz** SFZ instrument plugin
- **uv** + Python 3.11 + per-app virtualenvs at `/opt/pistomp/venvs/`
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

---

## How the Build Works

The build is two-stage: **host-side image setup** followed by **chroot configuration**.

1. **Image creation (host)** — `build.sh` creates a raw `.img` file, partitions it (FAT32 boot + ext4 root), attaches it as a loop device via `losetup`/`kpartx`, and mounts the partitions.
2. **pacstrap (host)** — Installs a fresh Arch Linux ARM rootfs directly from ALARM mirrors into the mounted image. No pre-built tarball needed.
3. **Chroot scripts (target)** — `arch-chroot` enters the rootfs and runs the numbered scripts (`00-base.sh` through `08-cleanup.sh`) sequentially. These configure the system as if running on the Pi itself.
4. **Finalize (host)** — Unmounts everything, detaches the loop device, and compresses the image with zstd.

When running via `build-docker.sh`, the entire process happens inside a privileged Docker container (an aarch64 Arch Linux image with `arch-install-scripts`). The host only needs Docker.

| Script | Phase |
|--------|-------|
| `00-base.sh` | Pacman init, kernel, locale, users |
| `01-rt-kernel.sh` | Uses a precompiled realtime kernel |
| `02-system.sh` | Networking, SSH, GPIO, udev rules |
| `03-audio.sh` | JACK2, LV2 stack, ALSA config, RT limits |
| `04-native-pkgs.sh` | uv, native C PKGBUILDs (mod-host, lg, etc.) |
| `05-python.sh` | pyenv, Python venvs, pip installs |
| `06-app-data.sh` | Pedalboards, LV2 plugins, user files |
| `07-services.sh` | systemd units, firstboot, helper scripts |
| `08-cleanup.sh` | Clear caches, remove build artifacts |

## Filesystem Recovery

If the root filesystem is detected as read-only at boot (for example, due to an unclean shutdown leaving the ext4 journal in a bad state), the `pistomp-ro-recovery.service` will automatically reboot to give `systemd-fsck` another chance to repair it. Up to 2 recovery attempts are made, with a persistent counter stored in `/boot` to prevent infinite reboot loops. If `/boot` itself is not writable, the script aborts and the device stays read-only for manual repair.

To disable this behavior (for example during debugging), add `pistomp.ro.recovery=0` to the kernel command line in `cmdline.txt`:

```text
root=/dev/mmcblk0p2 ... pistomp.ro.recovery=0
```

## Direct Build (Linux only)

```bash
# Download LV2 plugins cache first
mkdir -p cache
curl -L -o cache/lv2plugins.tar.gz https://www.treefallsound.com/downloads/lv2plugins.tar.gz

# TODO: direct build script for rt kernel

# Build as root (requires arch-install-scripts, parted, dosfstools, e2fsprogs, multipath-tools)
sudo ./build.sh
```
