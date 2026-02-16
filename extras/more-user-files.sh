#!/bin/bash
# A starter pack of instruments, sound effects, etc.
# This script is intended to be executed on the pistomp itself

pushd /home/pistomp/data/user-files >/dev/null

pushd 'SFZ Instruments' >/dev/null
    wget https://freepats.zenvoid.org/Piano/UprightPianoKW/UprightPianoKW-SFZ-20220221.7z
    7z x UprightPianoKW-SFZ-20220221.7z
popd >/dev/null

pushd 'SF2 Instruments' >/dev/null
    wget https://freepats.zenvoid.org/Piano/YDP-GrandPiano/YDP-GrandPiano-SF2-20160804.tar.bz2
    tar xjf YDP-GrandPiano-SF2-20160804.tar.bz2
popd >/dev/null

popd >/dev/null
