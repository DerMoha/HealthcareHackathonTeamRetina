"""Copy app screenshots into studio/public/pitch/shots as Studio cover images (1280 px wide).

Usage: python3 pitch_covers.py SRC_DIR DST_DIR
Older ultrasound shots carry an orange caveat badge on the scanner header; paint over it
when it is there (no-op once the app shots are re-taken in -pitch mode).
"""
import sys
from pathlib import Path
from PIL import Image

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
dst.mkdir(parents=True, exist_ok=True)
for f in sorted(src.glob('*.jpg')):
    if not f.name.startswith(('wrist-', 'us-', 'rt-', 'hero-')):
        continue
    im = Image.open(f).convert('RGB')
    W, H = im.size
    if f.name.startswith('us-'):
        box = (int(W * .304), int(H * .433), int(W * .396), int(H * .452))  # badge area, fixed pitch camera
        px = [im.getpixel((x, y)) for x in range(box[0], box[2], 4) for y in range(box[1], box[3], 2)]
        orange = sum(1 for r, g, b in px if r > 180 and 90 < g < 200 and b < 130)
        if orange > len(px) * .2:  # badge present
            im.paste(im.getpixel((box[0] - 6, box[1] + 4)), box)
    im.thumbnail((1280, 1280))
    im.save(dst / f.name, quality=82)
