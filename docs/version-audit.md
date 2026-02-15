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
| **ZynAddSubFX** | Built from source, unpinned | **Missing** | Not present in arch build |
| **Sfizz** | Built from source, unpinned | **Missing** | Not present in arch build |
| **LiquidSFZ** | Built from source, branch `0.3.2` | **Missing** | Not present in arch build |
| **Pedalboards** | `TreeFallSound/pi-stomp-pedalboards`, unpinned | `TreeFallSound/dot-pedalboards`, branch `main` | **Different repo name** |
| **User files** | `TreeFallSound/pi-stomp-user-files` | `TreeFallSound/pi-stomp-user-files` | Match |

## Key Discrepancies

1. **mod-ui uses a different fork/branch** — pi-gen uses `TreeFallSound/mod-ui#ps-1.13`, arch uses `sastraxi/mod-ui#fix/effect-parameter-from-snapshot`. This is the most significant difference — likely different feature sets.

2. **3 synth/effect plugins missing from arch** — ZynAddSubFX, Sfizz, and LiquidSFZ are all built from source in pi-gen but completely absent from the arch build. These provide synthesis capabilities.

3. **Hylia missing from arch** — Built in pi-gen as a mod-ui dependency. Arch may get it transitively via pacman packages or it may be missing.

4. **Pedalboards repo differs** — `dot-pedalboards` vs `pi-stomp-pedalboards`. Could be a rename or a different set of pedalboards.

5. **mod-host lacks CPU optimization flags** — pi-gen sets `-mcpu=cortex-a76 -mtune=cortex-a76`, the arch PKGBUILD doesn't. This affects performance on RPi 5.

6. **JACK2 sourcing differs** — pi-gen builds `v1.9.22` from source (installed to `/opt/pistomp`), arch uses the distro `jack2` package. The distro version may be newer or older.
