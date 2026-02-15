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
  01-system.sh               # Networking, SSH, GPIO, authbind
  02-audio.sh                # JACK2, LV2, ALSA, RT limits
  03-pistomp.sh              # pyenv, uv, PKGBUILDs, venvs, services, app data
  04-cleanup.sh              # Shrink image
pkgbuilds/                   # Pacman packages for C components (mod-host, amidithru, etc.)
files/                       # Static config files, systemd units, pacman configs, boot scripts
patches/                     # Patches applied during build (mod-ui, etc.)
docs/                        # Extended docs (RT kernel guide, etc.)
cache/                       # Downloaded LV2 plugins tarball (gitignored)
```

## Principles

1. **Pacman-tracked everything.** Native C components are PKGBUILDs, not bare `make install`. This means clean upgrades and removals.

2. **Isolated Python.** pyenv pins Python 3.11 at `/opt/pistomp/pyenv/`. Each app gets its own venv in `/opt/pistomp/venvs/<app>/`. System Python is untouched. Service files reference venv Python directly.

3. **Scripts are sequential and idempotent.** `00-base.sh` → `04-cleanup.sh` run in order inside chroot. Each script should be safe to re-run (use `--needed`, check before creating, etc.).

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

## When editing

- **Adding a system package?** Put it in the right numbered script. Audio packages → `02-audio.sh`, general system → `01-system.sh`.
- **Adding a native C component?** Create a PKGBUILD in `pkgbuilds/`, build it in `03-pistomp.sh`.
- **Adding a Python app?** Create a venv in `03-pistomp.sh`, add a service file in `files/`.
- **Changing a version or repo?** Edit `config.sh`, not the scripts.
- **Adding a service?** Install the unit file, then symlink to enable (see chroot limitation above). Check the dependency chain.
