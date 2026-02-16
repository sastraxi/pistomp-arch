#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <file.img.zst>"
    echo "Re-compresses an img.zst file with maximum compression"
    exit 1
fi

INPUT="$1"

if [ ! -f "$INPUT" ]; then
    echo "Error: File '$INPUT' not found"
    exit 1
fi

if [[ ! "$INPUT" =~ \.img\.zst$ ]]; then
    echo "Error: File must end with .img.zst"
    exit 1
fi

OUTPUT="${INPUT%.img.zst}-max.img.zst"

echo "Re-compressing $INPUT with maximum compression..."
echo "Output: $OUTPUT"
echo ""
zstd -d -c "$INPUT" | zstd -19 -T0 -o "$OUTPUT"

echo ""
echo "Original size: $(ls -lh "$INPUT" | awk '{print $5}')"
echo "New size:      $(ls -lh "$OUTPUT" | awk '{print $5}')"
echo ""
echo "Done! Output: $OUTPUT"
