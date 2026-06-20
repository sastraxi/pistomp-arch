# Package Management

pi-Stomp distributes its custom software via a **pacman repository** hosted on GitHub Releases. This document covers building, deploying, and publishing packages.

## Architecture

All native C components and Python apps are built as pacman packages (PKGBUILDs) in `pkgbuilds/`:

| Package | What it is |
|---------|-----------|
| `jack2-pistomp` | JACK2 with pi-stomp netadapter fix |
| `mod-host-pistomp` | MOD audio host |
| `mod-ui` | Web UI (Tornado) |
| `pi-stomp` | Main app (Python, venv) |
| `pistomp-recovery` | Recovery LCD service |
| `sfizz-pistomp` | SFZ instrument plugin |
| `lg` | lgpio Python bindings |
| `lcd-splash` | LCD boot splash |
| `fluidsynth-headless` | Fluidsynth without X11 |
| `libfluidsynth2-compat` | .so.2 shim for Debian plugins |
| `amidithru` | MIDI thru box |
| `mod-midi-merger` | MIDI merger broadcaster |
| `mod-ttymidi` | ttymidi bridge |
| `hylia` | Audio utilities |
| `jack_capture` | JACK audio capture |
| `pistomp-python311` | Bundled Python 3.11 for mod-ui |

Devices check for updates from the `[pistomp]` repo (configured in `/etc/pacman.conf`):

```ini
[pistomp]
Server = https://github.com/sastraxi/pistomp-arch/releases/download/repo
```

## Deploying to a running device

`deploy-pkg.sh` builds a package on-device with `makepkg` and installs it:

```bash
# Build from git (branch configured in PKGBUILD)
./deploy-pkg.sh pi-stomp

# Build from a local source tree (for testing changes)
./deploy-pkg.sh ../pi-stomp

# Build on a specific device
./deploy-pkg.sh pistomp-recovery --host pistomp.local --user pistomp
```

After a successful build, the script prints the remote path of the `.pkg.tar.zst` artifact. Copy the printed `scp` command to fetch it back.

## Publishing to the package repo

### 1. Fetch the built package

After `deploy-pkg.sh` succeeds:

```bash
# Copy the printed scp command, or:
scp pistomp@pistomp.local:/tmp/deploy-pkg/*.pkg.tar.zst ./repo/
```

### 2. Add to the repo database

```bash
cd repo
repo-add pistomp.db.tar.zst *.pkg.tar.zst
```

This generates `pistomp.db.tar.zst` and a `pistomp.db` symlink. You need both.

### 3. Upload to GitHub Releases

```bash
gh release upload repo pistomp.db.tar.zst pistomp.db *.pkg.tar.zst --clobber
```

The `[pistomp]` repo uses a **fixed tag** (`repo`) so device URLs never change. `--clobber` overwrites existing assets with the same name.

### Full workflow

```bash
# Deploy and test on a real device
./deploy-pkg.sh pi-stomp

# Fetch the artifact back
mkdir -p repo
scp pistomp@pistomp.local:/tmp/deploy-pkg/pi-stomp-*.pkg.tar.zst repo/

# Rebuild the repo database
cd repo
repo-add pistomp.db.tar.zst *.pkg.tar.zst

# Publish
cd ..
gh release upload repo repo/pistomp.db.tar.zst repo/pistomp.db repo/*.pkg.tar.zst --clobber

# Verify
curl -I https://github.com/sastraxi/pistomp-arch/releases/download/repo/pistomp.db.tar.zst
```

## How devices discover updates

`pacman -Syu` checks all configured repos. The `pistomp-recovery` UI runs `pacman -Qu` to list available updates from the `[pistomp]` repo alongside official ALARM updates.

```bash
# On the device
pacman -Qu          # list all pending updates
pacman -Qu pi-stomp # check a specific package
```

## Rolling back

Pacman keeps downloaded packages in `/var/cache/pacman/pkg/`. To roll back:

```bash
# Install a specific older version from cache
sudo pacman -U /var/cache/pacman/pkg/pi-stomp-3.0.0-1-aarch64.pkg.tar.zst

# Or let the recovery app handle it (it knows service dependencies)
```

## Notes

- **No signing yet.** The repo is unsigned (`SigLevel = Optional` on the device). If you add GPG signing later, use `repo-add --sign` and ship the public key to devices.
- **Epoch versions.** Some packages use epoch versions (`1:2.0-1`). Colons in filenames break on some platforms. `deploy-pkg.sh` handles this, but `repo-add` also normalizes them.
- **GitHub Limits.** 2 GB per file, 1000 assets per release. With ~15 packages you'll never hit either.
- **Atomicity.** Upload packages first, then the DB, to avoid a window where the DB references non-existent files. For a 1-person project this is fine; for automation consider the ArchZFS temp-tag trick.
