#!/bin/bash
# Regenerate splash.rgb565 from splash.png
# Run this on the host whenever splash.png changes, then commit the result.
set -euo pipefail
cd "$(dirname "$0")"
ffmpeg -y -i splash.png \
    -vf "scale=320:240:force_original_aspect_ratio=decrease,pad=320:240:-1:-1:color=black" \
    -sws_dither ed -f rawvideo -pix_fmt rgb565be splash.rgb565
echo "Generated splash.rgb565 ($(wc -c < splash.rgb565) bytes)"
