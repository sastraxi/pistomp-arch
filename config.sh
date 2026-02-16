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

# Python (pyenv, for mod-ui/browsepy/touchosc2midi only;
# pi-stomp uses system Python + --system-site-packages)
PYTHON_VERSION="3.11.11"

# Repos
PISTOMP_REPO="https://github.com/sastraxi/pi-stomp.git"
PISTOMP_BRANCH="release/arch"

MODUI_REPO="https://github.com/sastraxi/mod-ui.git"
MODUI_BRANCH="fix/effect-parameter-from-snapshot"

PEDALBOARDS_REPO="https://github.com/sastraxi/dot-pedalboards.git"
PEDALBOARDS_BRANCH="main"

USERFILES_REPO="https://github.com/TreeFallSound/pi-stomp-user-files.git"
USERFILES_BRANCH="main"

BROWSEPY_REPO="https://github.com/micahvdm/browsepy.git"
TOUCHOSC2MIDI_REPO="https://github.com/micahvdm/touchosc2midi.git"

# LV2 plugins tarball
LV2_PLUGINS_URL="https://www.treefallsound.com/downloads/lv2plugins.tar.gz"
LV2_PLUGINS_SHA256=""

# RT Kernel (upstream Arch ARM linux-rpi PKGBUILD we base on)
LINUX_RPI_PKGBUILD_COMMIT="7c052fb40b1918cc7cae34d2045e237788ebedf5"  # Latest as of 2026-02-15, v6.18.10-1
LINUX_RPI_PKGBUILD_BASE_URL="https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/${LINUX_RPI_PKGBUILD_COMMIT}/core/linux-rpi"
