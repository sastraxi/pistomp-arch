# Migration: ALARM tarball → pacstrap

## Overview

Replace the current approach (extract ALARM tarball → `pacman -Syu` → fight stale packages) with `pacstrap` installing a fresh rootfs from ALARM repos directly.

## Steps

### 1. Add `files/pacman-aarch64.conf`

Custom pacman config targeting ALARM repos:

```ini
[options]
HoldPkg     = pacman glibc
Architecture = aarch64
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5
DisableSandbox

[core]
Server = http://mirror.archlinuxarm.org/$arch/$repo

[extra]
Server = http://mirror.archlinuxarm.org/$arch/$repo

[alarm]
Server = http://mirror.archlinuxarm.org/$arch/$repo

[aur]
Server = http://mirror.archlinuxarm.org/$arch/$repo
```

Note: `DisableSandbox` needed for Docker/chroot. `CheckSpace` omitted for same reason.

### 2. Update `build.sh` — replace tarball extract with pacstrap

Remove:
- ALARM tarball download/lookup logic (lines ~76-85)
- `bsdtar -xpf` extraction step
- QEMU copy step (we're aarch64-on-aarch64, and pacstrap handles scriptlets natively)

Replace with:

```bash
log "Installing base system with pacstrap..."
pacstrap -C "${SCRIPT_DIR}/files/pacman-aarch64.conf" -M -K "${ROOT_MNT}" \
    base sudo \
    linux-rpi linux-rpi-headers \
    raspberrypi-bootloader firmware-raspberrypi \
    archlinuxarm-keyring
```

This installs the kernel, boot firmware, and a minimal base — all at current versions.

### 3. Update `build-docker.sh` — remove ALARM tarball download

Remove the `alarm-aarch64.tar.gz` download block. The tarball is no longer used.

Keep the LV2 plugins download (still needed).

### 4. Update `00-base.sh` — simplify dramatically

Remove:
- `pacman-key --init` / `--populate` (pacstrap `-K` handles this)
- `DisableSandbox` sed hack (already in our custom pacman.conf, and pacstrap copies it to the target)
- vim/gvim removal (never installed)
- `pacman -Syu` (already current)
- `linux-aarch64` / `uboot-raspberrypi` removal (never installed)

Keep:
- vconsole.conf creation
- `pacman -S --needed sudo` (or move sudo into the pacstrap package list)
- Locale, timezone, hostname, users, fstab, boot config

The script shrinks to just locale/users/config setup.

### 5. Update `00-base.sh` — install the ALARM keyring properly

pacstrap's `-K` creates an empty keyring. The `archlinuxarm-keyring` package (installed by pacstrap) provides the key material, but we still need to populate it:

```bash
pacman-key --init
pacman-key --populate archlinuxarm
```

Keep these in `00-base.sh` as the first step.

### 6. Copy the custom pacman.conf into the rootfs

After pacstrap, the target rootfs has a stock `pacman.conf` from the `pacman` package. Replace it with our ALARM-configured version (minus `DisableSandbox` for the final image):

```bash
# Install the real pacman.conf (without Docker workarounds)
install -m 644 "${SCRIPT_DIR}/files/pacman-alarm.conf" "${ROOT_MNT}/etc/pacman.conf"
```

Or: have `00-base.sh` write the mirrorlist and patch pacman.conf inside the chroot. Either works.

### 7. Verify boot firmware lands on the FAT32 partition

With the tarball, boot files were pre-placed. With pacstrap, the `raspberrypi-bootloader` package installs to `/boot/`. Confirm that `/boot` is bind-mounted to the FAT32 partition *before* running pacstrap (it already is in `build.sh`).

### 8. Update `config.sh`

Remove `ALARM_TARBALL_URL` — no longer needed.

### 9. Update `.dockerignore` / `.gitignore`

Remove `cache/alarm-aarch64.tar.gz` references if any are specific to it. The `cache/` directory gitignore still covers LV2 plugins.

## Files changed

| File | Change |
|------|--------|
| `files/pacman-aarch64.conf` | **New** — ALARM repo config for pacstrap |
| `build.sh` | Replace tarball logic with pacstrap call |
| `build-docker.sh` | Remove ALARM tarball download |
| `scripts/00-base.sh` | Remove -Syu, vim hacks, kernel swap; keep locale/users |
| `config.sh` | Remove `ALARM_TARBALL_URL` |

## Risks

- **Untested package combos**: pacstrap pulls latest from mirrors. A broken `linux-rpi` push could produce an unbootable image. Mitigate by testing after builds.
- **Mirror availability**: pacstrap needs network during build. If mirror.archlinuxarm.org is down, build fails. Could add fallback mirrors to the conf.
- **Boot firmware**: must verify `raspberrypi-bootloader` installs `config.txt`, `cmdline.txt`, etc. to the right place. We overwrite `config.txt` anyway.
