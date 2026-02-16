# linux-rpi-rt - RT Kernel for Raspberry Pi

This directory builds a **PREEMPT_RT realtime kernel** for Raspberry Pi by patching the upstream Arch Linux ARM `linux-rpi` package.

## Architecture

1. **Download** the official `linux-rpi` PKGBUILD from a pinned commit (see `config.sh`)
2. **Patch** it with our RT modifications (`linux-rpi-to-rt.patch`)
3. **Add** RT-specific kernel config options (`archarm-rt.diffconfig`)
4. **Build** with `makepkg`

## Files

```
linux-rpi-rt/
├── README.md                    # This file
├── build-rt-kernel.sh           # Download upstream, patch, prepare for build
├── linux-rpi-to-rt.patch        # Transforms linux-rpi → linux-rpi-rt
├── archarm-rt.diffconfig        # RT-specific kernel options (HZ_1000, etc.)
└── (downloaded at build time)   # PKGBUILD, config.txt, etc.
```

## Usage

### Build the RT kernel package

```bash
cd pkgbuilds/linux-rpi-rt
./build-rt-kernel.sh   # Download upstream PKGBUILD, patch it
makepkg -s             # Build the package (requires aarch64 or cross-compile setup)
```

This produces:
- `linux-rpi-rt-6.18.10-1-aarch64.pkg.tar.xz` (kernel)
- `linux-rpi-rt-headers-6.18.10-1-aarch64.pkg.tar.xz` (headers)

### Install in the image build

The main `build.sh` script will call `build-rt-kernel.sh` and install the resulting package during `pacstrap`.

## Upgrading the Base Kernel

When Arch ARM releases a new `linux-rpi` version:

1. Check the latest commit: https://github.com/archlinuxarm/PKGBUILDs/commits/master/core/linux-rpi
2. Update `config.sh`:
   ```bash
   LINUX_RPI_PKGBUILD_COMMIT="<new-commit-hash>"  # v6.20.x
   ```
3. Test the build:
   ```bash
   ./build-rt-kernel.sh
   makepkg -s
   ```
4. If the patch fails, update `linux-rpi-to-rt.patch` to match upstream changes

## What the Patch Does

The `linux-rpi-to-rt.patch` file:

- Changes `pkgbase=linux-rpi` → `pkgbase=linux-rpi-rt`
- Adds `archarm-rt.diffconfig` to sources
- For ARM64 (Pi 4/5): Uses `bcm2711_rt_defconfig` if available, else enables `CONFIG_PREEMPT_RT` manually
- For ARMv7 (Pi 3): Enables `CONFIG_PREEMPT_RT` manually on `bcm2709_defconfig`
- Updates package descriptions, provides, and conflicts
- Adds RT verification check in `prepare()` function

## RT Kernel Options

The `archarm-rt.diffconfig` file enables:

- `CONFIG_PREEMPT_RT=y` - Full realtime preemption
- `CONFIG_HZ_1000=y` - 1000 Hz timer (lower latency)
- `CONFIG_NO_HZ_FULL=y` - Tickless on isolated cores
- `CONFIG_IRQ_FORCED_THREADING_DEFAULT=y` - Threaded IRQs
- Plus other latency-reducing options (see file for details)

These are applied **on top of** Arch ARM's standard `archarm.diffconfig`.

## Multi-Device Support

Like the stock `linux-rpi` package, `linux-rpi-rt`:

- Uses a **single kernel** for all Pi 3/4/5 (ARM64)
- Includes **all device tree blobs** in `/boot/`
- Relies on **bootloader auto-detection** to select the correct DTB at runtime

No special configuration needed—the same package works on Pi 3, 4, and 5.

## References

- Upstream PKGBUILD: https://github.com/archlinuxarm/PKGBUILDs/tree/master/core/linux-rpi
- Pinned commit: See `LINUX_RPI_PKGBUILD_COMMIT` in `config.sh`
- RT kernel docs: `docs/rt-kernel.md`
