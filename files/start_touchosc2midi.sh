#!/bin/sh
# Discover amidithru's touchosc MIDI ports and launch touchosc2midi
# connected to them (rather than creating its own virtual ports).
T2M=/opt/pistomp/venvs/touchosc2midi/bin/touchosc2midi

IN_PORT_ID=$($T2M list ports 2>&1 | grep touchosc | head -n 1 | egrep -o "\s+[0-9]+: " | egrep -o "[0-9]+")
OUT_PORT_ID=$($T2M list ports 2>&1 | grep touchosc | tail -n 1 | egrep -o "\s+[0-9]+: " | egrep -o "[0-9]+")

if [ -n "$IN_PORT_ID" ] && [ -n "$OUT_PORT_ID" ]; then
    exec $T2M --midi-in=$IN_PORT_ID --midi-out=$OUT_PORT_ID
else
    # Fallback: create virtual ports if amidithru ports not found
    exec $T2M
fi
