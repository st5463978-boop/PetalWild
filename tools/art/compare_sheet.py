#!/usr/bin/env python3
"""2x2 compare sheet: original | this commit | previous commit | target.
Prints mean chroma, clipped-white %, and a coarse bed-vs-lawn L* delta under each tile."""
import argparse, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 1440, 900
TILE_W, TILE_H = 720, 470
LABEL_H = 48
FOOT_H = 36


def to_lab(rgb):
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def metrics(path):
    if not path or not os.path.exists(path):
        return {"chroma": 0.0, "clip": 0.0, "delta_l": 0.0, "missing": True}
    im = Image.open(path).convert("RGB")
    im.thumbnail((640, 640))
    a = np.asarray(im).astype(float)
    lab = to_lab(a.reshape(-1, 3))
    chroma = float(np.hypot(lab[:, 1], lab[:, 2]).mean())
    clip = float(((a >= 250).all(-1)).mean() * 100)
    # Coarse: darker lower-mid vs greener surround. Not a bed mask; a trend number.
    h, w = a.shape[:2]
    bed = lab.reshape(h, w, 3)[int(h * 0.42) : int(h * 0.72), int(w * 0.28) : int(w * 0.72), 0]
    lawn = lab.reshape(h, w, 3)[int(h * 0.55) : int(h * 0.95), 0 : int(w * 0.22), 0]
    delta = float(np.median(lawn) - np.median(bed)) if bed.size and lawn.size else 0.0
    return {"chroma": chroma, "clip": clip, "delta_l": delta, "missing": False}


def fit(path):
    canvas = Image.new("RGB", (TILE_W, TILE_H), (28, 24, 18))
    if not path or not os.path.exists(path):
        d = ImageDraw.Draw(canvas)
        d.text((24, TILE_H // 2 - 10), "(missing)", fill=(180, 170, 150))
        return canvas
    im = Image.open(path).convert("RGB")
    im.thumbnail((TILE_W, TILE_H))
    x = (TILE_W - im.width) // 2
    y = (TILE_H - im.height) // 2
    canvas.paste(im, (x, y))
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("original")
    ap.add_argument("this_cam")
    ap.add_argument("prev_cam")
    ap.add_argument("target")
    ap.add_argument("--out", required=True)
    ap.add_argument("--labels", nargs=4, default=["00_ORIGINAL", "this commit", "previous commit", "target_garden_02"])
    A = ap.parse_args()
    paths = [A.original, A.this_cam, A.prev_cam, A.target]
    sheet = Image.new("RGB", (TILE_W * 2, (LABEL_H + TILE_H + FOOT_H) * 2), (18, 16, 12))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 18)
        small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
    except Exception:
        font = ImageFont.load_default()
        small = font
    numbers = []
    for i, path in enumerate(paths):
        col, row = i % 2, i // 2
        x, y = col * TILE_W, row * (LABEL_H + TILE_H + FOOT_H)
        draw.rectangle([x, y, x + TILE_W, y + LABEL_H], fill=(42, 36, 28))
        draw.text((x + 12, y + 12), A.labels[i], fill=(245, 219, 180), font=font)
        sheet.paste(fit(path), (x, y + LABEL_H))
        m = metrics(path)
        numbers.append(m)
        foot = "(missing)" if m["missing"] else "chroma %.1f   clip %.2f%%   bed-vs-lawn L* %.1f" % (
            m["chroma"], m["clip"], m["delta_l"]
        )
        draw.rectangle([x, y + LABEL_H + TILE_H, x + TILE_W, y + LABEL_H + TILE_H + FOOT_H], fill=(32, 28, 22))
        draw.text((x + 12, y + LABEL_H + TILE_H + 8), foot, fill=(226, 199, 123), font=small)
        print("%s  %s" % (A.labels[i], foot))
    os.makedirs(os.path.dirname(os.path.abspath(A.out)) or ".", exist_ok=True)
    sheet.save(A.out)
    print("COMPARE_SHEET", A.out)
    if not numbers[1]["missing"] and not numbers[2]["missing"]:
        worse = []
        if numbers[1]["chroma"] + 0.4 < numbers[2]["chroma"]:
            worse.append("chroma dropped")
        if numbers[1]["clip"] > numbers[2]["clip"] + 0.15:
            worse.append("clip rose")
        if numbers[1]["delta_l"] + 0.8 < numbers[2]["delta_l"]:
            worse.append("bed-vs-lawn L* flattened")
        if worse:
            print("REGRESSION " + "; ".join(worse))
            sys.exit(2)
    print("REGRESSION_OK")


if __name__ == "__main__":
    main()
