#!/usr/bin/env python3
"""Generate font.h from a PSF2 console font (.psfu or .psfu.gz)."""

import gzip
import struct
import sys

PSF2_MAGIC = 0x864AB572

path = sys.argv[1]

opener = gzip.open if path.endswith(".gz") else open
with opener(path, "rb") as f:
    data = f.read()

magic, ver, hdrsize, flags, numglyph, bpg, height, width = struct.unpack_from("<8I", data)
if magic != PSF2_MAGIC:
    print(f"Not a PSF2 font: {path}", file=sys.stderr)
    sys.exit(1)

glyphs = data[hdrsize : hdrsize + numglyph * bpg]

print(f"#define FONT_WIDTH      {width}")
print(f"#define FONT_HEIGHT     {height}")
print(f"#define FONT_BPG        {bpg}")
print(f"#define FONT_NUM_GLYPHS {numglyph}")
print(f"static const unsigned char font_data[{numglyph}][{bpg}] = {{")
for i in range(numglyph):
    g = glyphs[i * bpg : (i + 1) * bpg]
    print("  {" + ",".join(f"0x{b:02x}" for b in g) + "},")
print("};")
