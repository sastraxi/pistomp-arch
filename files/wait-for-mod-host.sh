#!/bin/bash
# Wait for mod-host to be ready to accept connections
# Uses ss to check if port 5555 is in LISTEN state (no actual connection made)

timeout=60
attempts=$((timeout * 2))  # Check every 0.5 seconds

for ((i=0; i<attempts; i++)); do
    # Check if mod-host is listening on port 5555 without connecting
    if ss -ltn | grep -q ':5555 '; then
        echo "mod-host is ready (listening on port 5555)"
        exit 0
    fi
    sleep 0.5
done

echo "Timeout waiting for mod-host to be ready" >&2
exit 1
