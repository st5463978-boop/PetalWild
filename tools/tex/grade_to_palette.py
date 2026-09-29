#!/usr/bin/env python3
"""Shift an albedo tile onto a target mean hex and scale chroma."""
import argparse, numpy as np
from PIL import Image

def srgb_to_linear(c):
    return np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)

def linear_to_srgb(c):
    c = np.clip(c, 0, None)
    return np.where(c > 0.0031308, 1.055 * np.power(c, 1 / 2.4) - 0.055, 12.92 * c)

def rgb_to_lab(rgb):
    c = srgb_to_linear(rgb)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ M.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)

def lab_to_rgb(lab):
    fy = (lab[..., 0] + 16) / 116
    fx = lab[..., 1] / 500 + fy
    fz = fy - lab[..., 2] / 200
    f = np.stack([fx, fy, fz], -1)
    xyz = np.where(f > 0.206897, f ** 3, (f - 16 / 116) / 7.787) * np.array([0.95047, 1.0, 1.08883])
    M = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    return np.clip(linear_to_srgb(xyz @ M.T), 0, 1)

def hex_to_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) for i in (0, 2, 4)], dtype=float) / 255.0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mean", required=True)
    ap.add_argument("--chroma", type=float, default=0.85)
    ap.add_argument("--size", type=int, default=1024)
    A = ap.parse_args()
    im = Image.open(A.src).convert("RGB")
    if A.size:
        im = im.resize((A.size, A.size), Image.Resampling.LANCZOS)
    rgb = np.asarray(im).astype(np.float32) / 255.0
    lab = rgb_to_lab(rgb)
    target = rgb_to_lab(hex_to_rgb(A.mean)[None, None, :])[0, 0]
    mean = lab.reshape(-1, 3).mean(0)
    out = lab.copy()
    out[..., 0] = (out[..., 0] - mean[0]) * 0.9 + target[0]
    out[..., 1] = (out[..., 1] - mean[1]) * A.chroma + target[1]
    out[..., 2] = (out[..., 2] - mean[2]) * A.chroma + target[2]
    rgb_out = (lab_to_rgb(out) * 255).round().astype(np.uint8)
    Image.fromarray(rgb_out).save(A.out)
    print("graded", A.out)

if __name__ == "__main__":
    main()
