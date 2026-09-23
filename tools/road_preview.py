"""Top-down PNG of the generated road slabs over the building footprints.

Verifies alignment without Studio: roads should lie in the gaps between
buildings. Orange marks a roadway slab overlapping a footprint.

  python tools/road_preview.py [--crop x0 z0 x1 z1] [--out FILE]
"""
from pathlib import Path
import argparse
import glob
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices" / "ground"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
import ground_preview as P  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--crop", nargs=4, type=float)
    ap.add_argument("--out", default=str(DATA / "road_preview.png"))
    ap.add_argument("--cell", type=float, default=4.0)
    args = ap.parse_args()
    d = np.load(DATA / "heights.npz")
    known, x0, z0, hcell = d["known"], float(d["x0"]), float(d["z0"]), float(d["cell"])
    step = max(1, int(args.cell / hcell))
    kn = known[::step, ::step]
    cell = hcell * step
    shape = kn.shape
    road = np.zeros(shape, bool)
    walk = np.zeros(shape, bool)
    for f in glob.glob(str(DATA / "roads" / "tile_*.json")):
        for s in json.loads(Path(f).read_text())["slabs"]:
            kind, cx, _y, cz, yaw, _pitch, length, _th, width = s[:9]
            c, sn = math.cos(yaw), math.sin(yaw)
            # rasterise the rectangle
            n = max(2, int(length / cell) + 1)
            m = max(2, int(width / cell) + 1)
            for a in np.linspace(-length / 2, length / 2, n):
                for b in np.linspace(-width / 2, width / 2, m):
                    x = cx + a * c - b * sn
                    z = cz + a * sn + b * c
                    i = int(round((x - x0) / cell))
                    j = int(round((z - z0) / cell))
                    if 0 <= i < shape[0] and 0 <= j < shape[1]:
                        (road if kind == "roadway" else walk)[i, j] = True
    img = np.zeros(shape + (3,))
    img[:] = [0.62, 0.62, 0.58]
    img[kn] = [0.22, 0.22, 0.26]
    img[walk] = [0.80, 0.78, 0.72]
    img[road] = [0.15, 0.15, 0.17]
    img[road & kn] = [1.0, 0.55, 0.0]
    if args.crop:
        cx0, cz0, cx1, cz1 = args.crop
        i0, i1 = int((cx0 - x0) / cell), int((cx1 - x0) / cell)
        j0, j1 = int((cz0 - z0) / cell), int((cz1 - z0) / cell)
        img = img[i0:i1, j0:j1]
    P.write_png(args.out, (np.clip(img, 0, 1) * 255).astype(np.uint8).transpose(1, 0, 2))
    tot = road.sum()
    print(f"{args.out}: roadway cells {tot}, on buildings {100 * (road & kn).sum() / max(tot, 1):.1f}%")


if __name__ == "__main__":
    main()
