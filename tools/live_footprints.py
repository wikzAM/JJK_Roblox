"""Rasterise the LIVE buildings' ground-floor footprints (uploaded from Studio as
tools/source_slices/live_footprints.txt) onto the ground grid.

heights.npz's `known` mask dates from when the ground was generated and still
holds buildings that have since been removed (viaducts, replaced greys), so it
cut streets where nothing stands. road_fit.py blocks on this mask instead.

  python tools/live_footprints.py   -> source_slices/ground/live_footprints.npy
"""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402  (puts tools/python_deps on the path)
import numpy as np  # noqa: E402


def contains(P, C):
    """Even-odd point-in-polygon for many points C against polygon P (numpy)."""
    x, z = C[:, 0], C[:, 1]
    inside = np.zeros(len(C), bool)
    j = len(P) - 1
    for i in range(len(P)):
        xi, zi, xj, zj = P[i, 0], P[i, 1], P[j, 0], P[j, 1]
        if zi != zj:
            cross = ((zi > z) != (zj > z)) & (x < (xj - xi) * (z - zi) / (zj - zi) + xi)
            inside ^= cross
        j = i
    return inside

D = ROOT / "source_slices" / "ground"


def main():
    h = np.load(D / "heights.npz")
    known, x0, z0, cell0 = h["known"], float(h["x0"]), float(h["z0"]), float(h["cell"])
    # 2-stud cells: on the 4-stud ground grid a footprint edge could land 2 studs
    # off, and roads fitted to it touched buildings by that much
    cell = 2.0
    shape = (int(known.shape[0] * cell0 / cell), int(known.shape[1] * cell0 / cell))
    live = np.zeros(shape, bool)
    n = 0
    for line in open(ROOT / "source_slices" / "live_footprints.txt", encoding="utf-8"):
        if "|" not in line:
            continue
        _, pts = line.strip().split("|")
        P = np.array([[float(a) for a in p.split(",")] for p in pts.split(";")])
        if len(P) < 3:
            continue
        i0 = max(int((P[:, 0].min() - x0) / cell) - 1, 0)
        i1 = min(int((P[:, 0].max() - x0) / cell) + 2, shape[0])
        j0 = max(int((P[:, 1].min() - z0) / cell) - 1, 0)
        j1 = min(int((P[:, 1].max() - z0) / cell) + 2, shape[1])
        if i1 <= i0 or j1 <= j0:
            continue
        I, J = np.meshgrid(np.arange(i0, i1), np.arange(j0, j1), indexing="ij")
        C = np.stack([x0 + (I + 0.5) * cell, z0 + (J + 0.5) * cell], -1).reshape(-1, 2)
        live[i0:i1, j0:j1] |= contains(P, C).reshape(I.shape)
        n += 1
    np.savez_compressed(D / "live_footprints.npz", mask=live, x0=x0, z0=z0, cell=cell)
    coarse = live.reshape(known.shape[0], 2, known.shape[1], 2).any(axis=(1, 3))
    print(f"{n} polygons | live footprint {live.sum() * cell * cell / 1e6:.2f}M sq studs at {cell}-stud cells")
    print(f"in the old mask but nothing stands there now: {(known & ~coarse).sum() * cell0 * cell0 / 1e6:.2f}M sq studs")


if __name__ == "__main__":
    main()
