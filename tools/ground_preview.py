"""Hillshaded PNG of the ground height field, buildings dark -- for checking by eye.

  python tools/ground_preview.py [--crop x0 z0 x1 z1] [--out FILE] [--scale N]
"""
from pathlib import Path
import argparse
import struct
import zlib

import numpy as np

DATA = Path(__file__).resolve().parent / "source_slices" / "ground"


def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b"")
    Path(path).write_bytes(png)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--crop", nargs=4, type=float)
    ap.add_argument("--out", default=str(DATA / "preview.png"))
    ap.add_argument("--scale", type=int, default=1, help="take every Nth cell")
    args = ap.parse_args()
    d = np.load(DATA / "heights.npz")
    H, known, x0, z0, cell = d["H"], d["known"], float(d["x0"]), float(d["z0"]), float(d["cell"])
    if args.crop:
        cx0, cz0, cx1, cz1 = args.crop
        i0, i1 = int((cx0 - x0) / cell), int((cx1 - x0) / cell)
        j0, j1 = int((cz0 - z0) / cell), int((cz1 - z0) / cell)
        H, known = H[i0:i1, j0:j1], known[i0:i1, j0:j1]
    H, known = H[::args.scale, ::args.scale], known[::args.scale, ::args.scale]
    gx, gz = np.gradient(H, cell * args.scale)
    # hillshade, light from the north-west
    shade = np.clip(0.6 + 0.4 * (-gx * 0.7 - gz * 0.7) / np.sqrt(1 + gx * gx + gz * gz) * 3, 0, 1)
    t = (H - H.min()) / max(np.ptp(H), 1e-6)
    r = (0.25 + 0.75 * t) * shade
    g = (0.55 + 0.25 * (1 - t)) * shade
    b = (0.35 + 0.3 * (1 - t)) * shade
    rgb = np.stack([r, g, b], axis=-1)
    rgb[known] *= 0.45
    # contour lines every 8 studs
    band = np.floor(H / 8.0)
    edge = (np.diff(band, axis=0, prepend=band[:1]) != 0) | (np.diff(band, axis=1, prepend=band[:, :1]) != 0)
    rgb[edge & ~known] = [0.1, 0.1, 0.1]
    img = (np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    # array is [x, z]; image rows = z (north up = -z at top)
    write_png(args.out, np.ascontiguousarray(img.transpose(1, 0, 2)))
    print(f"{args.out}: {img.shape[0]} x {img.shape[1]}, height {H.min():.0f}..{H.max():.0f}")


if __name__ == "__main__":
    main()
