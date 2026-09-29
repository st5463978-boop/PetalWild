#!/usr/bin/env python3
"""Height-from-luma normal (OpenGL +Y) and inverted-luma roughness."""
import argparse, numpy as np
from PIL import Image, ImageFilter

def wrap_gauss(a, sigma):
    pad = int(max(4, round(sigma * 3)))
    p = np.pad(a, pad, mode="wrap")
    im = Image.fromarray((np.clip(p, 0, 1) * 255).astype(np.uint8))
    im = im.filter(ImageFilter.GaussianBlur(radius=sigma))
    crop = np.asarray(im)[pad:-pad, pad:-pad].astype(np.float32) / 255.0
    return crop

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out-normal", required=True)
    ap.add_argument("--out-rough", required=True)
    ap.add_argument("--strength", type=float, default=1.0)
    ap.add_argument("--rough-min", type=float, default=0.7)
    ap.add_argument("--rough-max", type=float, default=0.95)
    ap.add_argument("--size", type=int, default=1024)
    A = ap.parse_args()
    im = Image.open(A.src).convert("RGB")
    if A.size:
        im = im.resize((A.size, A.size), Image.Resampling.LANCZOS)
    rgb = np.asarray(im).astype(np.float32) / 255.0
    height = rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722
    height = wrap_gauss(height, 1.5)
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * (0.5 * A.strength * 8.0)
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * (0.5 * A.strength * 8.0)
    n = np.stack([-dx, dy, np.ones_like(dx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True).clip(1e-6)
    nrm = ((n * 0.5 + 0.5) * 255).round().astype(np.uint8)
    Image.fromarray(nrm).save(A.out_normal)
    inv = 1.0 - height
    span = float(inv.max() - inv.min()) + 1e-6
    rgh = A.rough_min + (A.rough_max - A.rough_min) * (inv - inv.min()) / span
    Image.fromarray((np.clip(rgh, 0, 1) * 255).round().astype(np.uint8)).save(A.out_rough)
    print("detail", A.out_normal, A.out_rough)

if __name__ == "__main__":
    main()
