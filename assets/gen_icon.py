"""Generate MacMerge app icon: two overlapping file documents."""
from PIL import Image, ImageDraw
import math, os

SIZE = 1024

# Catppuccin Mocha palette
BG        = (30,  30,  46,  0)    # transparent background
DOC_BACK  = (137, 180, 250, 220)  # blue (back doc)
DOC_FRONT = (203, 166, 247, 255)  # mauve (front doc)
FOLD_BACK = (100, 140, 210, 220)
FOLD_FRONT= (160, 120, 200, 255)
SHADOW    = (0,   0,   0,   60)
LINE_COL  = (30,  30,  46,  180)  # dark lines on doc

def draw_doc(draw, ox, oy, w, h, body_color, fold_color, fold_size=None):
    """Draw a document icon (rectangle with top-right corner folded)."""
    if fold_size is None:
        fold_size = w * 0.22

    fold = int(fold_size)
    r = int(w * 0.08)  # corner radius for the rest

    # Body polygon (all corners except top-right are rounded via rect)
    # Draw main body minus top-right fold triangle
    pts_body = [
        (ox + r,         oy),
        (ox + w - fold,  oy),
        (ox + w,         oy + fold),
        (ox + w,         oy + h - r),
        (ox + w - r,     oy + h),
        (ox + r,         oy + h),
        (ox,             oy + h - r),
        (ox,             oy + r),
    ]
    draw.polygon(pts_body, fill=body_color)

    # Fold flap (lighter triangle)
    pts_fold = [
        (ox + w - fold, oy),
        (ox + w,        oy + fold),
        (ox + w - fold, oy + fold),
    ]
    draw.polygon(pts_fold, fill=fold_color)

    # Crease line
    draw.line([(ox + w - fold, oy), (ox + w - fold, oy + fold), (ox + w, oy + fold)],
              fill=LINE_COL, width=max(2, int(w * 0.015)))

    # Horizontal lines (text lines) on body
    line_x0 = ox + int(w * 0.18)
    line_x1 = ox + int(w * 0.75)
    line_y_start = oy + int(h * 0.40)
    line_gap = int(h * 0.11)
    lw = max(2, int(w * 0.025))
    for i in range(3):
        y = line_y_start + i * line_gap
        draw.line([(line_x0, y), (line_x1, y)], fill=LINE_COL, width=lw)


def make_icon(size):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    s = size
    # Document dimensions (relative to canvas)
    dw = int(s * 0.52)
    dh = int(s * 0.63)

    # Back document (blue) — shifted up-left
    back_ox = int(s * 0.12)
    back_oy = int(s * 0.10)
    draw_doc(draw, back_ox, back_oy, dw, dh, DOC_BACK, FOLD_BACK)

    # Front document (mauve) — shifted down-right
    front_ox = int(s * 0.34)
    front_oy = int(s * 0.27)
    draw_doc(draw, front_ox, front_oy, dw, dh, DOC_FRONT, FOLD_FRONT)

    return img


# ---- Build iconset ----
out_dir = os.path.dirname(os.path.abspath(__file__))
iconset_dir = os.path.join(out_dir, 'AppIcon.iconset')
os.makedirs(iconset_dir, exist_ok=True)

specs = [
    ('icon_16x16.png',      16),
    ('icon_16x16@2x.png',   32),
    ('icon_32x32.png',      32),
    ('icon_32x32@2x.png',   64),
    ('icon_128x128.png',    128),
    ('icon_128x128@2x.png', 256),
    ('icon_256x256.png',    256),
    ('icon_256x256@2x.png', 512),
    ('icon_512x512.png',    512),
    ('icon_512x512@2x.png', 1024),
]

base = make_icon(1024)

for fname, px in specs:
    img = base.resize((px, px), Image.LANCZOS)
    img.save(os.path.join(iconset_dir, fname))
    print(f'  {fname}')

# Save 1024px PNG as well (for electron-builder fallback)
base.save(os.path.join(out_dir, 'icon.png'))
print('Done.')
