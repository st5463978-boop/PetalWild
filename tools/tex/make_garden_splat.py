#!/usr/bin/env python3
"""Paint garden_splat.png: R flagstone, G dirt, B gravel. 5 cm/px over the hedge room."""
import os, numpy as np
from PIL import Image, ImageDraw, ImageFilter

# Hedge room: x -13.6..12.8, z -9.9..7.9. Origin at (-13.6, -9.9)
X0, Z0 = -13.6, -9.9
W_M, D_M = 26.4, 17.8
CM = 0.05
W = int(round(W_M / CM))
H = int(round(D_M / CM))

def to_px(x, z):
    return int(round((x - X0) / CM)), int(round((z - Z0) / CM))

def stroke(draw, a, b, width_m, fill):
    (x0, z0), (x1, z1) = to_px(*a), to_px(*b)
    r = max(1, int(round(width_m / CM * 0.5)))
    draw.line([(x0, z0), (x1, z1)], fill=fill, width=r * 2)

def main():
    img = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(img)
    # Flagstone plaza at stall and 1.2 m walks around the four beds.
    stroke(d, (-6.6, 3.5), (-1.4, 3.5), 1.2, (255, 0, 0))
    stroke(d, (-2.35, 3.5), (-2.35, -6.35), 1.2, (255, 0, 0))
    stroke(d, (-7.4, -6.35), (0.6, -6.35), 1.2, (255, 0, 0))
    stroke(d, (-4.55, 3.5), (-4.55, 5.4), 1.2, (255, 0, 0))
    # Plaza disc at stall
    cx, cz = to_px(-4.55, 5.15)
    r = int(round(1.6 / CM))
    d.ellipse([cx - r, cz - r, cx + r, cz + r], fill=(255, 0, 0))
    # Pond path
    stroke(d, (2.6, -2.5), (6.4, -2.5), 1.2, (255, 0, 0))
    # Dirt spurs
    stroke(d, (-4.55, 5.2), (-4.55, 3.5), 0.7, (0, 255, 0))
    stroke(d, (-11.15, 3.55), (-7.4, 3.5), 0.7, (0, 255, 0))
    # Gravel strip against hedge foot (outer rect inset)
    outer = Image.new("L", (W, H), 0)
    od = ImageDraw.Draw(outer)
    pad = int(round(0.35 / CM))
    od.rectangle([pad, pad, W - pad, H - pad], outline=255, width=int(round(0.3 / CM)))
    arr = np.array(img)
    g = np.asarray(outer)
    arr[..., 2] = np.maximum(arr[..., 2], g)
    img = Image.fromarray(arr).filter(ImageFilter.GaussianBlur(radius=1.6))
    out = os.path.join("assets", "terrain", "garden_splat.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print("splat", out, img.size)

if __name__ == "__main__":
    main()
