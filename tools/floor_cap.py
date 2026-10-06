"""The 360-degree floor cap: no ground and no road above the floor of the
buildings around it.

Owner, Oct 5: "the nearest buildings in the 360 degrees for each section of the
road will have the terrain and thus the road be below the floor slab height".

Every ground-floor slab piece (Interior.Floor1 Slab/Part/GrayBlock, exported
from Studio as source_slices/floor1_parts.txt: `building|topY|8 corners x,z`)
is rasterised onto the 4-stud ground grid (FL = lowest slab top over a cell).
Then for every cell, looking out in DIRS directions, the FIRST building cell
hit in each direction (within REACH studs) caps the cell at that floor's top
minus GAP, easing off at EASE per stud beyond STRICT studs. Buildings shadow
the ones behind them, so a street is held under the buildings that line it,
not under one far down the hill.

  python tools/floor_cap.py   -> source_slices/ground/floor_cap.npz (CAP visible studs, FL, BM)
"""
import json
import math
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from live_footprints import contains  # noqa: E402

D = ROOT / "source_slices" / "ground"
CELL = 4.0
GAP = 1.0        # studs the ground stays under a floor's top
DIRS = 24        # directions looked along from every cell
REACH = 160.0    # studs: buildings further than this do not cap a cell
STRICT = 48.0    # ... within this the cap is the floor itself (minus GAP)
EASE = 0.5       # ... beyond it the cap rises this much per stud
CLOSE = 5        # cells: caps narrower than this are closed (alley streaks)
LOCAL = 8.0      # studs: floors this close cap the ground exactly, after the closing


def hull(P):
    """Convex hull (monotone chain) of points P (n,2)."""
    P = sorted(set(map(tuple, P)))
    if len(P) < 3:
        return np.array(P)

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for p in P:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(P):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return np.array(lo[:-1] + hi[:-1])


def main():
    src = D / "terrain_orig"
    index = json.loads((src / "index.json").read_text())
    chunks = [json.loads((src / f"{n}.json").read_text()) for n in index]
    gx0 = min(c["x0"] for c in chunks)
    gz0 = min(c["z0"] for c in chunks)
    gx1 = max(c["x0"] + c["nx"] * CELL for c in chunks)
    gz1 = max(c["z0"] + c["nz"] * CELL for c in chunks)
    NX, NZ = int(round((gx1 - gx0) / CELL)), int(round((gz1 - gz0) / CELL))

    FL = np.full((NX, NZ), np.inf)
    # buildings tools/flatten_fit.py left in place (stilted / slope-straddling / floating
    # records): no ground or road is held to their floors
    sk = D / "flatten_skip.json"
    skip_b = set(json.loads(sk.read_text())) if sk.exists() else set()
    n = 0
    for line in open(ROOT / "source_slices" / "floor1_parts.txt", encoding="utf-8"):
        f = line.strip().split("|")
        if len(f) != 3 or f[0] in skip_b:
            continue
        pts = f[2].split(";")
        if len(pts) not in (6, 8):     # a wedge piece has 6 corners
            continue
        top = float(f[1])
        P = hull(np.array([[float(a) for a in p.split(",")] for p in pts]))
        if len(P) < 3:
            continue
        # cells whose centre is inside, plus cells the piece covers a corner of
        # (pieces thinner than a cell would otherwise miss the grid)
        i0 = max(int((P[:, 0].min() - gx0) / CELL), 0); i1 = min(int((P[:, 0].max() - gx0) / CELL) + 1, NX)
        k0 = max(int((P[:, 1].min() - gz0) / CELL), 0); k1 = min(int((P[:, 1].max() - gz0) / CELL) + 1, NZ)
        if i1 <= i0 or k1 <= k0:
            continue
        I, K = np.meshgrid(np.arange(i0, i1), np.arange(k0, k1), indexing="ij")
        C = np.stack([gx0 + (I + 0.5) * CELL, gz0 + (K + 0.5) * CELL], -1).reshape(-1, 2)
        m = contains(P, C).reshape(I.shape)
        for px, pz in P:
            i, k = int((px - gx0) / CELL), int((pz - gz0) / CELL)
            if i0 <= i < i1 and k0 <= k < k1:
                m[i - i0, k - k0] = True
        sub = FL[i0:i1, k0:k1]
        sub[m] = np.minimum(sub[m], top)
        n += 1
    BM = np.isfinite(FL)
    print(f"{n} ground-floor pieces -> {int(BM.sum())} building cells")

    # first building cell hit in each direction. Hits within STRICT are taken as
    # they are; FARTHER hits are kept apart and closed (grey closing) before use:
    # a single ray slipping down an alley to a building far down the hill left
    # one-cell streaks of a low cap, dug into the ground as lines of pits
    CAP = np.where(BM, FL - GAP, np.inf)
    FAR = np.full((NX, NZ), np.inf)
    steps = int(REACH / CELL)
    pad = steps + 1
    FLp = np.pad(FL, pad, constant_values=np.inf)
    for d in range(DIRS):
        ang = 2 * math.pi * d / DIRS
        dx, dz = math.cos(ang), math.sin(ang)
        hit = np.full((NX, NZ), np.inf)
        found = BM.copy()                       # a building cell is capped by itself
        last = (None, None)
        for k in range(1, steps + 1):
            oi, ok = int(round(k * dx)), int(round(k * dz))
            if (oi, ok) == last:
                continue
            last = (oi, ok)
            sh = FLp[pad + oi:pad + oi + NX, pad + ok:pad + ok + NZ]
            new = ~found & np.isfinite(sh)
            if new.any():
                dist = math.hypot(oi, ok) * CELL
                if dist <= STRICT:
                    hit[new] = sh[new] - GAP
                else:
                    farv = sh - GAP + EASE * (dist - STRICT)
                    FAR[new] = np.minimum(FAR[new], farv[new])
                found |= new
        CAP = np.minimum(CAP, hit)
    from scipy import ndimage
    FARf = np.where(np.isfinite(FAR), FAR, 1e6)
    FARc = ndimage.grey_closing(FARf, size=(CLOSE, CLOSE))
    CAP = np.minimum(CAP, np.where(FARc >= 1e5, np.inf, FARc))
    # the same for the whole cap (a ray through a one-cell gap to a nearer lower
    # building streaks too), then the floors within LOCAL studs imposed again
    # exactly: ground is never above a floor that close, whatever the closing did
    Cf = np.where(np.isfinite(CAP), CAP, 1e6)
    Cc = ndimage.grey_closing(Cf, size=(CLOSE, CLOSE))
    near_floor = ndimage.minimum_filter(np.where(BM, FL - GAP, 1e6), size=2 * int(LOCAL / CELL) + 1)
    CAP = np.minimum(Cc, near_floor)
    CAP = np.where(CAP >= 1e5, np.inf, CAP)
    capped = np.isfinite(CAP)
    print(f"cells capped: {capped.mean():.1%}")
    np.savez_compressed(D / "floor_cap.npz", CAP=np.where(capped, CAP, 1e6).astype(np.float32),
                        FL=np.where(BM, FL, 1e6).astype(np.float32), BM=BM, x0=gx0, z0=gz0, cell=CELL)
    print(f"-> {D / 'floor_cap.npz'}")


if __name__ == "__main__":
    main()
