#!/bin/bash
# pistomp-arch build configuration

# Image
IMG_NAME="pistompOS-arch"
IMG_SIZE_MB=4096

# System
TARGET_HOSTNAME="pistomp"
LOCALE="en_US.UTF-8"
TIMEZONE="US/Central"
KEYMAP="us"

# Users
FIRST_USER="pistomp"
FIRST_USER_PASS="pistomp"

# ALARM tarball
ALARM_TARBALL_URL="http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz"

# Python
PYTHON_VERSION="3.11.11"

# Repos
PISTOMP_REPO="https://github.com/TreeFallSound/pi-stomp.git"
PISTOMP_BRANCH="pistomp-v3"

MODUI_REPO="https://github.com/sastraxi/mod-ui.git"
MODUI_BRANCH="fix/effect-parameter-from-snapshot"

PEDALBOARDS_REPO="https://github.com/TreeFallSound/dot-pedalboards.git"
PEDALBOARDS_BRANCH="main"

USERFILES_REPO="https://github.com/TreeFallSound/pi-stomp-user-files.git"
USERFILES_BRANCH="main"

BROWSEPY_REPO="https://github.com/micahvdm/browsepy.git"
TOUCHOSC2MIDI_REPO="https://github.com/micahvdm/touchosc2midi.git"

# LV2 plugins tarball
LV2_PLUGINS_URL="https://www.treefallsound.com/downloads/lv2plugins.tar.gz"
LV2_PLUGINS_SHA256=""
