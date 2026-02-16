# CLAUDE.md — pistomp-arch

Builds a bootable Arch Linux ARM image for pi-Stomp guitar pedal hardware (RPi 3/4/5).

## Quick reference

```
./build-docker.sh          # Build image (Docker, any OS)
sudo ./build.sh            # Build image (Linux, native)
# Output: deploy/pistompOS-arch-<date>.img.zst
```

## Directory structure

```
build.sh / build-docker.sh   # Image builder (pacstrap + arch-chroot)
config.sh                    # All version pins, URLs, repo refs — single source of truth
scripts/
  00-base.sh                 # Pacman keyring, locale, users
  01-rt-kernel.sh            # Compiles a realtime kernel
  02-system.sh               # Networking, SSH, GPIO, authbind
  03-audio.sh                # JACK2, LV2, ALSA, RT limits
  04-pistomp.sh              # pyenv, uv, PKGBUILDs, venvs, services, app data
  05-cleanup.sh              # Shrink image
pkgbuilds/                   # Pacman packages for C components (mod-host, amidithru, etc.)
files/                       # Static config files, systemd units, pacman configs, boot scripts
patches/                     # Patches applied during build (mod-ui, etc.)
docs/                        # Extended docs (RT kernel guide, etc.)
cache/                       # Downloaded LV2 plugins tarball (gitignored)
```

## Principles

1. **Pacman-tracked everything.** Native C components are PKGBUILDs, not bare `make install`. This means clean upgrades and removals.

2. **Isolated Python.** pyenv pins Python 3.11 at `/opt/pistomp/pyenv/`. Each app gets its own venv in `/opt/pistomp/venvs/<app>/`. System Python is untouched. Service files reference venv Python directly.

3. **Scripts are sequential and idempotent.** `00-base.sh` → `05-pistomp.sh` run in order inside chroot. Each script should be safe to re-run (use `--needed`, check before creating, etc.).

4. **config.sh is the single source of truth** for versions, repo URLs, branches, and paths. Scripts read from environment variables — don't hardcode these values in scripts.

5. **Services run as `pistomp` user, not root.** JACK runs as `jack` user. Port 80 access via authbind. Realtime limits via `/etc/security/limits.d/`.

6. **Chroot limitation: no systemctl.** Enable services with symlinks:
   ```
   ln -s /usr/lib/systemd/system/foo.service /etc/systemd/system/multi-user.target.wants/
   ```

## Key decisions

- **pacstrap, not tarball** — rootfs is bootstrapped fresh from ALARM mirrors via `pacstrap`. No pre-built tarball. `files/pacman-aarch64.conf` (with `DisableSandbox` for Docker/chroot) is used during build; `files/pacman-alarm.conf` (without it) is installed into the final image.
- **Stock kernel** — ships `linux-rpi`, not RT. RT kernel is Phase 6 (see `docs/rt-kernel.md`).
- **Pre-built LV2 plugins** — downloaded as tarball, not compiled. `libfluidsynth2-compat` PKGBUILD provides .so.2 shim for Debian-built plugins.
- **makepkg needs a non-root user** — scripts create/destroy a temporary `builduser` for PKGBUILD compilation.
- **First-boot config** — users edit `/boot/pistomp.conf` (FAT32, mountable anywhere). `firstboot.service` applies it once and disables itself.

## Service dependency chain

```
jack.service
  ├─ mod-host.service
  │    ├─ mod-ui.service
  │    │    └─ mod-ala-pi-stomp.service
  │    └─ browsepy.service
  └─ mod-amidithru.service
```

## Troubleshooting with the live device

If we're trying to understand why something doesn't work, sometimes the pi-Stomp v3 hardware will be available to us. We can ssh into it via `ssh pistomp@pistomp.local` and introspect the running environment. We must always use the following ordering:

1. Confirm the runtime crash / bug / deficiency
2. Root-cause it -- what exactly is broken, and why?
3. Determine how our build differs from pi-gen-pistomp, if it does (some bugs are in both)
4. Play around with the running device to get it working
5. Backport the changes into this repository or to the related `../pi-stomp` or `../mod-ui` repository.

## Pitfalls (hard-won lessons)

### JACK permissions
JACK runs as `jack` user. Its socket is `rw-rw----` owned by `jack:jack`. Every JACK client service needs `JACK_PROMISCUOUS_SERVER=jack` in its environment, and `pistomp` must be in the `jack` group. Missing either = "Permission denied" at runtime. `JACK_NO_AUDIO_RESERVATION=1` is also required in `jack.service` (no D-Bus session bus on headless).

### Editable pip installs skip data_files
mod-ui is installed with `pip install -e` (editable). This means `data_files` from `setup.py` are never copied — `sys.prefix + '/share/mod/html/'` doesn't exist. We set `MOD_HTML_DIR` and `MOD_DEFAULT_PEDALBOARD` in `mod-ui.service` to point at the source tree instead.

### libmod_utils.so is not built by pip
mod-ui's `modtools/utils.py` loads `libmod_utils.so` via ctypes. This C library (`utils/` directory) requires a separate `make` step — `pip install` does not build it. The editable install means the fallback path `../utils/libmod_utils.so` resolves correctly from the source tree.

### WiFi interface renamed to wlan0 via udev
Arch uses predictable names (`wld0`), but pi-stomp hardcodes `wlan0`. A udev rule in `02-system.sh` renames the WiFi interface to `wlan0`. The NetworkManager connection must be named `preconfigured` (what pi-stomp's `wifi.py` expects).

### pyliblo is broken; use pyliblo3
`pyliblo` 0.10.0 is incompatible with modern liblo and Cython 3.x. Use `pyliblo3` (maintained fork) with `Cython<3.1` (3.1 removed the `long` builtin). touchosc2midi must be installed `--no-deps` to avoid pulling broken pyliblo.

### Build footguns
- **Never `umount -lf`** — lazy unmount causes data loss (buffered writes lost before loop teardown). Use `umount` + `sync`.
- **`vconsole.conf` must exist before `pacstrap`** — mkinitcpio's `sd-vconsole` hook fails otherwise.
- **Don't `rm -rf /root/pistomp-arch`** in cleanup — it destroys the bind-mounted `cache/` directory (883MB LV2 tarball). Only delete `files/`, `pkgbuilds/`, `patches/`.
- **`config.txt` must use explicit `initramfs` line** — ALARM's initramfs filename (`initramfs-linux.img`) doesn't match what `auto_initramfs=1` expects.

### ALSA state
`firstboot.sh` copies `iqaudiocodec.state` to `/var/lib/alsa/asound.state`. The `alsa-restore.service` (from `alsa-utils`) loads it on every subsequent boot. Without it, JACK's ALSA driver times out.

## Relationship to pi-gen-pistomp

`../pi-gen-pistomp` is the original Debian-based image builder. This repo is a ground-up Arch rewrite. When in doubt about how a component should be configured, cross-reference pi-gen's `stage2/05-pistomp/` (service files, user setup, native builds) and `stage3/01-pistomp/` (app data, pedalboards). Key differences: we use pacman not apt, PKGBUILDs not bare `make install`, venvs not system Python, NetworkManager not wpa_supplicant, and system-packaged binaries (`/usr/bin/`) not `/opt/pistomp/bin/`.

## Relationship to pi-stomp and mod-ui

This repo builds the image that ultimately runs on the pi-Stomp hardware, running our customized versions of mod-ui and pi-stomp. These repositories are usually available checked out as peers to this directory.

## When editing

- **Adding a system package?** Put it in the right numbered script. Audio packages → `03-audio.sh`, general system → `02-system.sh`.
- **Adding a native C component?** Create a PKGBUILD in `pkgbuilds/`, build it in `04-pistomp.sh`.
- **Adding a Python app?** Create a venv in `04-pistomp.sh`, add a service file in `files/`.
- **Changing a version or repo?** Edit `config.sh`, not the scripts.
- **Adding a service?** Install the unit file, then symlink to enable (see chroot limitation above). Check the dependency chain.
