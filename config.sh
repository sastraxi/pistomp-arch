#!/bin/bash
# pistomp-arch build configuration

# Image
IMG_NAME="pistompOS-arch"
IMG_SIZE_MB=8192

# System
TARGET_HOSTNAME="pistomp"
LOCALE="en_US.UTF-8"
TIMEZONE="US/Central"
KEYMAP="us"

# Users
FIRST_USER="pistomp"
FIRST_USER_PASS="pistomp"

# Python (uv-managed prebuilt, for mod-ui/browsepy/touchosc2midi only;
# pi-stomp uses system Python + --system-site-packages)
PYTHON_VERSION="3.11.11"

# Repos
PISTOMP_REPO="https://github.com/sastraxi/pi-stomp.git"
PISTOMP_BRANCH="release/patch"

MODUI_REPO="https://github.com/sastraxi/mod-ui.git"
MODUI_BRANCH="feat/web-bpm-rebroadcast"

MOD_HOST_REPO="https://github.com/sastraxi/mod-host.git"
MOD_HOST_BRANCH="fix/effect-drain-midi"

RECOVERY_REPO="https://github.com/sastraxi/pistomp-recovery.git"
RECOVERY_BRANCH="main"

PEDALBOARDS_REPO="https://github.com/TreeFallSound/pi-stomp-pedalboards.git"
PEDALBOARDS_BRANCH="master"

USERFILES_REPO="https://github.com/TreeFallSound/pi-stomp-user-files.git"
USERFILES_BRANCH="main"

# DAW recording over Ethernet; uses only `pi/.
JACKROUTER_REPO="https://github.com/sastraxi/JackRouter.git"
JACKROUTER_REF="master"

BROWSEPY_REPO="https://github.com/micahvdm/browsepy.git"
TOUCHOSC2MIDI_REPO="https://github.com/micahvdm/touchosc2midi.git"

# LV2 plugins tarball
LV2_PLUGINS_URL="https://www.treefallsound.com/downloads/lv2plugins.tar.gz"
LV2_PLUGINS_SHA256=""

# RT Kernel (upstream Arch ARM linux-rpi PKGBUILD we base on)
LINUX_RPI_PKGBUILD_COMMIT="a759a569d5cd77fa3bc3719098d4388a731ba5a5"  # Latest as of 2026-05-30, v6.18.33-3
LINUX_RPI_PKGBUILD_BASE_URL="https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/${LINUX_RPI_PKGBUILD_COMMIT}/core/linux-rpi"
