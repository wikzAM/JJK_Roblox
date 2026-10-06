"""Footprint mask of the PLATEAU FBX buildings (source_slices/world_triangles.npz,
already in studs) on the same 2-stud grid as live_footprints.npz -- the reference
for checking where streets sit between the real building faces.

  python tools/fbx_mask.py -> source_slices/ground/fbx_footprints.npz (mask, x0, z0, cell)
"""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402

D = ROOT / "source_slices" / "ground"


def main():
    lf = np.load(D / "live_footprints.npz")
    live, x0, z0, cell = lf["mask"], float(lf["x0"]), float(lf["z0"]), float(lf["cell"])
    tri = np.load(ROOT / "source_slices" / "world_triangles.npz")["triangles"]   # (n, 3, 3) x, y, z
    P = tri[:, :, [0, 2]]
    mask = np.zeros_like(live)
    NX, NZ = mask.shape
    # every triangle's XZ projection, rasterised by cell-centre containment (+ its corners)
    for t in P:
        i0 = max(int((t[:, 0].min() - x0) / cell), 0); i1 = min(int((t[:, 0].max() - x0) / cell) + 1, NX)
        k0 = max(int((t[:, 1].min() - z0) / cell), 0); k1 = min(int((t[:, 1].max() - z0) / cell) + 1, NZ)
        if i1 <= i0 or k1 <= k0:
            continue
        if (i1 - i0) * (k1 - k0) == 1:
            mask[i0, k0] = True
            continue
        I, K = np.meshgrid(np.arange(i0, i1), np.arange(k0, k1), indexing="ij")
        X = x0 + (I + 0.5) * cell; Z = z0 + (K + 0.5) * cell
        (ax, az), (bx, bz), (cx, cz) = t
        d1 = (X - bx) * (az - bz) - (ax - bx) * (Z - bz)
        d2 = (X - cx) * (bz - cz) - (bx - cx) * (Z - cz)
        d3 = (X - ax) * (cz - az) - (cx - ax) * (Z - az)
        neg = (d1 < 0) | (d2 < 0) | (d3 < 0); pos = (d1 > 0) | (d2 > 0) | (d3 > 0)
        mask[i0:i1, k0:k1] |= ~(neg & pos)
    np.savez_compressed(D / "fbx_footprints.npz", mask=mask, x0=x0, z0=z0, cell=cell)
    both = (mask & live).sum()
    print(f"FBX cells {int(mask.sum())}, live {int(live.sum())}, both {int(both)}, "
          f"FBX only {int((mask & ~live).sum())}, live only {int((live & ~mask).sum())}")


if __name__ == "__main__":
    main()
