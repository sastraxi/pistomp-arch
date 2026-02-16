# Version Audit: pistomp-arch vs pi-gen-pistomp

| Component | pi-gen-pistomp | pistomp-arch | Notes |
|---|---|---|---|
| **Python** | System 3.11 (Bookworm) | pyenv `3.11.11` | Arch uses pyenv; same minor version |
| **JACK2** | Built from source, `v1.9.22` pinned | Pacman package (`jack2`) | **Arch uses distro package, not built from source** |
| **Hylia** | Built from source, unpinned (latest) | **Missing** | Not present in arch build |
| **Lilv** | Built from source, `0.24.12` tarball | Pacman packages (`lilv`, `python-lilv`) | Arch uses distro packages |
| **mod-host** | `mod-audio/mod-host`, unpinned, cortex-a76 flags | `mod-audio/mod-host`, unpinned, **no CPU flags** | Same repo, but arch PKGBUILD lacks `-mcpu=cortex-a76` optimization |
| **mod-ui** | `TreeFallSound/mod-ui`, branch `ps-1.13` | `sastraxi/mod-ui`, branch `fix/effect-parameter-from-snapshot` | **Different fork AND different branch** |
| **pi-stomp** | `treefallsound/pi-stomp`, branch `pistomp-v3` | `TreeFallSound/pi-stomp`, branch `pistomp-v3` | Match |
| **amidithru** | `BlokasLabs/amidithru`, unpinned | `BlokasLabs/amidithru`, unpinned | Match |
| **mod-midi-merger** | `micahvdm/mod-midi-merger`, unpinned | `micahvdm/mod-midi-merger`, unpinned | Match |
| **mod-ttymidi** | `moddevices/mod-ttymidi`, unpinned | `moddevices/mod-ttymidi`, unpinned | Match |
| **browsepy** | `micahvdm/browsepy`, unpinned | `micahvdm/browsepy`, unpinned | Match |
| **touchosc2midi** | `micahvdm/touchosc2midi`, unpinned | `micahvdm/touchosc2midi`, unpinned | Match |
| **LV2 plugins tarball** | `treefallsound.com/downloads/lv2plugins.tar.gz` | Same URL | Match |
| **libfluidsynth compat** | N/A (Debian has .so.2 natively) | PKGBUILD shim `.so.2 → .so.3` | Arch-specific, expected |
| **ZynAddSubFX** | `zynaddsubfx` via LV2 bundle | `zynaddsubfx` via LV2 bundle | Match |
| **Sfizz** | Built from source, unpinned | `sfizz-pistomp` (custom, no UI) | Match |
| **LiquidSFZ** | Built from source, branch `0.3.2` | `liquidsfz-lv2` (extra) | Match |
| **Pedalboards** | `TreeFallSound/pi-stomp-pedalboards`, unpinned | `TreeFallSound/dot-pedalboards`, branch `main` | **Different repo name** |
| **User files** | `TreeFallSound/pi-stomp-user-files` | `TreeFallSound/pi-stomp-user-files` | Match |

## Key Discrepancies

1. **mod-ui uses a different fork/branch** — pi-gen uses `TreeFallSound/mod-ui#ps-1.13`, arch uses `sastraxi/mod-ui#fix/effect-parameter-from-snapshot`. This is the most significant difference — likely different feature sets.

2. **Hylia missing from arch** — Built in pi-gen as a mod-ui dependency. Arch may get it transitively via pacman packages or it may be missing.

3. **Pedalboards repo differs** — `dot-pedalboards` vs `pi-stomp-pedalboards`. Could be a rename or a different set of pedalboards.

4. **mod-host lacks CPU optimization flags** — pi-gen sets `-mcpu=cortex-a76 -mtune=cortex-a76`, the arch PKGBUILD doesn't. This affects performance on RPi 5.

5. **JACK2 sourcing differs** — pi-gen builds `v1.9.22` from source (installed to `/opt/pistomp`), arch uses the distro `jack2` package. The distro version may be newer or older.

## Recent Fixes (2026-02-15)

### Service Reliability & Startup Ordering

**Issue**: mod-ui was crashing intermittently at startup with "jack client deactivated NOT" error, caused by mod-host not being ready to accept connections when mod-ui's `checkhost()` callback ran.

**Root cause**: mod-ui scans all LV2 plugins synchronously at startup, then attempts to connect to mod-host (localhost:5555/5556) via a callback. If mod-host isn't listening yet, mod-ui exits with status 1.

**Fixes applied**:
1. Added `wait-for-mod-host.sh` helper script that uses `ss` to check if mod-host is listening on port 5555 (without actually connecting, to avoid consuming the single client slot)
2. Added `ExecStartPre=/usr/local/bin/wait-for-mod-host.sh` to mod-ui.service
3. Increased `RestartSec` for mod-ui (1s → 3s) and mod-ala-pi-stomp (3s → 5s) to reduce restart thrashing

### WiFi Status Monitoring

**Issue**: pi-stomp app was getting "Permission denied" errors when calling `wpa_cli` to query WiFi status, causing log spam.

**Root cause**: Arch Linux + NetworkManager setup doesn't grant non-root access to wpa_supplicant control interface by default.

**Fix**: Replaced `wpa_cli` with `nmcli` in `../pi-stomp/modalapi/wifi.py`, implementing the TODO comment that was already in the code. More idiomatic for Arch + NetworkManager setup.

### WebSocket Exception Handling

**Issue**: mod-ui throwing unhandled KeyError exceptions when WebSocket messages try to set parameters on plugin instances that aren't loaded yet (race condition during pedalboard load).

**Root cause**: `InstanceIdMapper.get_id_without_creating()` raised KeyError when called with unknown plugin instance path.

**Fixes applied** to `../mod-ui/mod/host.py`:
1. Modified `get_id_without_creating()` to catch KeyError, log warning, and return None
2. Updated `param_set()`, `patch_get()`, and `patch_set()` to check for None and bail gracefully with logging
3. Prevents WebSocket handler crashes, allows operations to fail gracefully during timing races
