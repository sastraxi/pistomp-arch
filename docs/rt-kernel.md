# Realtime Kernel Options for pistompOS-arch

pistompOS-arch ships with Arch ARM's stock `linux-rpi` kernel (currently 6.18.x). This is **not RT** — it uses `CONFIG_PREEMPT` (voluntary preemption), not `CONFIG_PREEMPT_RT` (full realtime). This matches what pi-gen-pistomp ships on Pi 5.

This document covers the path to adding an RT kernel if needed.

## TL;DR

Since Linux 6.12, `PREEMPT_RT` is **merged into mainline** — no patch needed. The RPi Foundation kernel fork inherits it. Building an RT kernel for Arch ARM is: clone the `linux-rpi` PKGBUILD, switch to `bcm2711_rt_defconfig`, run `makepkg`. Cross-compile takes ~10 minutes.

## Current State (Feb 2026)

| Fact | Detail |
|------|--------|
| PREEMPT_RT mainlined | [Linux 6.12, Sep 2024](https://www.phoronix.com/news/Linux-6.12-Does-Real-Time) |
| Arch ARM `linux-rpi` version | 6.18.10 (has RT support in source, not enabled in config) |
| RPi Foundation RT defconfig | `bcm2711_rt_defconfig` exists (Pi 3/4). No `bcm2712_rt_defconfig` yet (Pi 5) |
| Pre-built RT packages for Arch ARM | **None.** Must build your own |
| RPi OS (Debian) RT package | `linux-image-rpi-v8-rt` via apt — Debian only |

## Building an RT Kernel

### Option A: Modify the Arch ARM PKGBUILD (recommended)

1. Clone the [archlinuxarm PKGBUILDs](https://github.com/archlinuxarm/PKGBUILDs) repo
2. Copy `core/linux-rpi/PKGBUILD`
3. Change the defconfig from `bcm2711_defconfig` to `bcm2711_rt_defconfig`
4. For Pi 5 support, add `CONFIG_PREEMPT_RT=y` to the diffconfig overlay (no dedicated rt_defconfig exists yet)
5. Build with `makepkg -s` (native) or cross-compile

The placeholder PKGBUILD at `pkgbuilds/linux-rpi-rt/PKGBUILD` in this repo is a starting point.

### Option B: Build from RPi kernel source directly

```bash
# Clone RPi kernel
git clone --depth 1 -b rpi-6.18.y https://github.com/raspberrypi/linux.git
cd linux

# Pi 3/4 (has official RT defconfig)
make ARCH=arm64 bcm2711_rt_defconfig

# Pi 5 (manual — no rt_defconfig yet)
make ARCH=arm64 bcm2712_defconfig
scripts/config --enable CONFIG_PREEMPT_RT

# Cross-compile
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image.gz modules dtbs
```

### Build Times

| Method | Time |
|--------|------|
| Cross-compile (modern x86 desktop) | ~5–15 min |
| Native on Pi 5 | ~60 min |
| Native on Pi 4 | ~2+ hours |

### Defconfigs

| Board | Standard | RT |
|-------|----------|----|
| Pi 3/4/Zero 2 W | `bcm2711_defconfig` | `bcm2711_rt_defconfig` |
| Pi 5 (4K pages) | `bcm2712_defconfig` | Manual: add `CONFIG_PREEMPT_RT=y` |
| Pi 5 (16K pages) | `bcm2712_defconfig` + 16K | Manual: add `CONFIG_PREEMPT_RT=y` |

## Pi 5 Caveats

- **No official RT defconfig** — enable `CONFIG_PREEMPT_RT=y` manually on top of `bcm2712_defconfig`
- **Worse RT latency than Pi 4** — cyclictest shows Pi 5 spiking to 800–1000+ μs under memory stress vs ~200 μs on Pi 4. Root cause is BCM2712 memory bus contention ([RPi Forums](https://forums.raspberrypi.com/viewtopic.php?t=382231)). This is a hardware limitation.
- **16K page size** works with RT but breaks some userspace software. Use 4K pages for maximum compatibility.

## Pre-built RT Kernel Sources

None are directly usable for Arch ARM:

| Project | Status | Notes |
|---------|--------|-------|
| [RPi Foundation apt packages](https://forums.raspberrypi.com/viewtopic.php?t=388298) | Active | Debian/RPi OS only (`linux-image-rpi-v8-rt`) |
| [kdoren/linux](https://github.com/kdoren/linux) | Active | Pre-built for RPi OS, not Arch |
| [remusmp/rpi-rt-kernel](https://github.com/remusmp/rpi-rt-kernel) | Active | Automated builds, targets RPi OS |
| [emlid/linux-rt-rpi](https://github.com/emlid/linux-rt-rpi) | Abandoned | Last update 2015 (kernel 3.18) |

## Audio-Tuned System Configuration

Beyond the kernel, these settings matter for low-latency audio. Most are already configured in `scripts/03-audio.sh`.

### Already configured in pistompOS-arch

- **rtprio/memlock limits**: `/etc/security/limits.d/99-audio.conf` grants `@audio` group rtprio 95 and unlimited memlock
- **Audio group membership**: `pistomp` and `jack` users in `audio` group

### Additional tuning (if using RT kernel)

**Kernel boot parameters** (add to `/boot/cmdline.txt`):

| Parameter | Purpose |
|-----------|---------|
| `threadirqs` | Force threaded IRQ handlers (default with RT, optional otherwise) |
| `isolcpus=2,3` | Reserve cores 2–3 for audio threads |
| `cpufreq.default_governor=performance` | Prevent frequency scaling jitter |

**CPU core pinning** — pin JACK to isolated cores:
```bash
# In jackdrc or jack.service ExecStart:
taskset -c 2,3 jackd -t 2000 -R -P 95 -d alsa -d hw:0 -r 48000 -p 256 -n 2 -X seq -s
```

**Sysctl tuning** (`/etc/sysctl.d/90-audio.conf`):
```ini
vm.swappiness=10
fs.inotify.max_user_watches=600000
```

**RT kernel config options** (if building custom):

| Option | Value | Purpose |
|--------|-------|---------|
| `CONFIG_PREEMPT_RT` | `y` | Full RT preemption |
| `CONFIG_HZ_1000` | `y` | 1000 Hz timer tick |
| `CONFIG_NO_HZ_FULL` | `y` | Tickless on isolated cores |

### RPi-specific audio topology

On ARM, hardware IRQs default to core 0 and generally cannot be rebalanced. Recommended core allocation:

| Core | Assignment |
|------|-----------|
| 0 | Hardware IRQs, kernel |
| 1 | System services |
| 2–3 | JACK + audio processing (isolated) |

## References

- [Arch Wiki: Professional Audio](https://wiki.archlinux.org/title/Professional_audio)
- [Arch Wiki: Realtime Kernel](https://wiki.archlinux.org/title/Realtime_kernel_patchset)
- [chmaha/ArchProAudio](https://github.com/chmaha/ArchProAudio)
- [LinuxCNC: RPi PREEMPT_RT 6.13 Cookbook](https://forum.linuxcnc.org/9-installing-linuxcnc/55048-raspberry-pi-os-preempt-rt-6-13-kernel-cookbook)
- [RPi Foundation kernel source](https://github.com/raspberrypi/linux)
- [archlinuxarm PKGBUILDs](https://github.com/archlinuxarm/PKGBUILDs)
