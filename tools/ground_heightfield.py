"""The ground: one smooth height field under the whole map, pinned to the buildings.

Studio's terrain is a failed heightmap import -- flat at ~34 studs everywhere
while building bases run 45-260 -- so the only reliable elevation in the map is
the buildings themselves. Every building's footprint is pinned at its ground
floor (floor-1 slab top, less 0.1 so the slab still reads on top); everything
between buildings -- streets, plazas, alleys -- is a membrane stretched across
those pins (a harmonic fill: each free cell is the average of its neighbours, so
a street between two buildings ramps evenly from one base to the other, the
"cloth draped over the buildings" the map owner described). A light smoothing
pass on free cells only takes the corners off.

Inputs: every live source-slice plan (source_slice_orphans.current_plans) and
the lowest parts of every other model in workspace.Buildings
(source_slices/ground_other_buildings.csv, dumped from Studio).

  python tools/ground_heightfield.py            -> source_slices/ground/heights.npz
"""
from pathlib import Path
import csv
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
OUT = DATA / "ground"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from shapely import contains_xy, prepare  # noqa: E402
from shapely.geometry import Polygon  # noqa: E402
import source_slice_orphans as O  # noqa: E402

CELL = 4.0          # studs between height samples
MARGIN = 160.0      # studs of ground beyond the outermost building
UNDER = 0.1         # ground sits this far under a building's floor-1 top
SMOOTH_PASSES = 40  # free-cell smoothing after the harmonic fill
PERCH = 36.0        # studs above the neighbours' median = standing on something
MIN_PIN_AREA = 150.0  # sq studs; smaller pins are crown fragments, and make spikes
NEAR, FAR = 20.0, 100.0  # studs from a building: exact within NEAR, broad trend beyond FAR
TREND_SIGMA = 100.0      # studs; the broad trend's smoothing


def pins():
    """(polygon, ground height) for every building in the map."""
    out = []
    for plan in O.current_plans().values():
        foot = next(iter(O.world_levels(plan)))
        if foot.is_empty:
            continue
        lv = plan["levels"][0]
        out.append((foot, plan["origin"]["y"] + lv["y"] + lv["thickness"] - UNDER))
    with open(DATA / "ground_other_buildings.csv", newline="") as fh:
        for r in csv.DictReader(fh):
            cx, cz, sx, sz, yaw = (float(r[k]) for k in ("cx", "cz", "sx", "sz", "yaw"))
            c, s = math.cos(yaw), math.sin(yaw)
            corners = []
            for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                lx, lz = a * sx / 2, b * sz / 2
                # Roblox yaw: world = (c*lx + s*lz, -s*lx + c*lz)
                corners.append((cx + c * lx + s * lz, cz - s * lx + c * lz))
            out.append((Polygon(corners), float(r["top"]) - UNDER))
    return out


def grounded(buildings):
    """Drop PERCHED pins: a building more than PERCH studs above the median of
    the buildings within 40 studs of it stands on something else (a tower
    stub on its podium, a grey crown fragment, a floating deck). Pinning the
    ground to it put the street at 427 studs beside the tower at 1636,1922."""
    from shapely.strtree import STRtree
    polys = [p for p, _ in buildings]
    tree = STRtree(polys)
    keep, dropped = [], []
    for i, (poly, y) in enumerate(buildings):
        near = [buildings[j][1] for j in tree.query(poly.buffer(40)) if j != i]
        if poly.area < MIN_PIN_AREA or (len(near) >= 2 and y - float(np.median(near)) > PERCH):
            dropped.append((round(y), round(poly.centroid.x), round(poly.centroid.y), round(poly.area)))
        else:
            keep.append((poly, y))
    return keep, dropped


def harmonic_fill(H, known):
    """Membrane interpolation, coarse to fine: free cells converge to the average
    of their neighbours with known cells held fixed."""
    def solve(h, k, iters):
        h = h.copy()
        for _ in range(iters):
            p = np.pad(h, 1, mode="edge")
            avg = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:]) / 4.0
            h = np.where(k, h, avg)
        return h

    def level(h, k):
        if min(h.shape) <= 8:
            fill = np.where(k, h, np.nan)
            m = np.nanmean(fill) if np.isfinite(fill).any() else 0.0
            return solve(np.where(k, h, m), k, 200)
        # restrict: mean of known children
        ny, nx = (h.shape[0] + 1) // 2, (h.shape[1] + 1) // 2
        hp = np.pad(np.where(k, h, 0.0), ((0, ny * 2 - h.shape[0]), (0, nx * 2 - h.shape[1])))
        kp = np.pad(k.astype(float), ((0, ny * 2 - h.shape[0]), (0, nx * 2 - h.shape[1])))
        s = hp.reshape(ny, 2, nx, 2).sum(axis=(1, 3))
        n = kp.reshape(ny, 2, nx, 2).sum(axis=(1, 3))
        coarse_k = n > 0
        coarse = level(np.where(coarse_k, s / np.maximum(n, 1), 0.0), coarse_k)
        up = np.repeat(np.repeat(coarse, 2, axis=0), 2, axis=1)[:h.shape[0], :h.shape[1]]
        return solve(np.where(k, h, up), k, 60)

    return level(H, known)


def biharmonic_fill(H, known, iters=(400, 160)):
    """Thin-plate fill on free cells (discrete bilaplacian = 0), started from the
    harmonic fill, coarse to fine. The harmonic membrane is continuous but
    KINKS at every pin, so the street slope jumps at each building and between
    triangles; the thin plate bends instead of kinking, so slopes carry smoothly
    across streets (Cities: Skylines' terrain around flat building pads)."""
    def relax(h, k, n):
        h = h.copy()
        for _ in range(n):
            p = np.pad(h, 2, mode="edge")
            c = p[2:-2, 2:-2]
            s1 = p[1:-3, 2:-2] + p[3:-1, 2:-2] + p[2:-2, 1:-3] + p[2:-2, 3:-1]
            s2 = p[1:-3, 1:-3] + p[1:-3, 3:-1] + p[3:-1, 1:-3] + p[3:-1, 3:-1]
            s3 = p[:-4, 2:-2] + p[4:, 2:-2] + p[2:-2, :-4] + p[2:-2, 4:]
            new = (8 * s1 - 2 * s2 - s3) / 20.0
            h = np.where(k, h, c + 0.5 * (new - c))   # Jacobi on the bilaplacian is stable only below 0.625
        return h

    def level(h, k, depth):
        if min(h.shape) <= 16 or depth >= 5:
            return relax(h, k, iters[0])
        ny, nx = (h.shape[0] + 1) // 2, (h.shape[1] + 1) // 2
        pad = ((0, ny * 2 - h.shape[0]), (0, nx * 2 - h.shape[1]))
        hp, kp = np.pad(h, pad, mode="edge"), np.pad(k, pad, mode="edge")
        kc = kp.reshape(ny, 2, nx, 2).any(axis=(1, 3))
        sk = np.where(kp, hp, 0).reshape(ny, 2, nx, 2).sum(axis=(1, 3))
        nk = kp.reshape(ny, 2, nx, 2).sum(axis=(1, 3))
        hc = np.where(kc, sk / np.maximum(nk, 1), hp.reshape(ny, 2, nx, 2).mean(axis=(1, 3)))
        coarse = level(hc, kc, depth + 1)
        up = np.repeat(np.repeat(coarse, 2, axis=0), 2, axis=1)[:h.shape[0], :h.shape[1]]
        return relax(np.where(k, h, up), k, iters[1])

    return level(H, known, 0)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    buildings, dropped = grounded(pins())
    (OUT / "perched.txt").write_text("\n".join(" ".join(map(str, d)) for d in sorted(dropped, reverse=True)))
    print(f"{len(dropped)} perched pins left to the fill (see perched.txt)")
    x0 = min(p.bounds[0] for p, _ in buildings) - MARGIN
    z0 = min(p.bounds[1] for p, _ in buildings) - MARGIN
    x1 = max(p.bounds[2] for p, _ in buildings) + MARGIN
    z1 = max(p.bounds[3] for p, _ in buildings) + MARGIN
    nx, nz = int(math.ceil((x1 - x0) / CELL)) + 1, int(math.ceil((z1 - z0) / CELL)) + 1
    print(f"{len(buildings)} buildings; grid {nx} x {nz} at {CELL} studs, x {x0:.0f}..{x1:.0f} z {z0:.0f}..{z1:.0f}")

    H = np.full((nx, nz), np.inf)
    for poly, y in buildings:
        bx0, bz0, bx1, bz1 = poly.bounds
        i0, i1 = max(0, int((bx0 - x0) / CELL)), min(nx - 1, int((bx1 - x0) / CELL) + 1)
        j0, j1 = max(0, int((bz0 - z0) / CELL)), min(nz - 1, int((bz1 - z0) / CELL) + 1)
        X, Z = np.meshgrid(x0 + np.arange(i0, i1 + 1) * CELL, z0 + np.arange(j0, j1 + 1) * CELL, indexing="ij")
        prepare(poly)
        inside = contains_xy(poly, X, Z)
        sub = H[i0:i1 + 1, j0:j1 + 1]
        H[i0:i1 + 1, j0:j1 + 1] = np.where(inside, np.minimum(sub, y), sub)
    known = np.isfinite(H)
    print(f"pinned cells {known.mean():.1%}")
    H = harmonic_fill(np.where(known, H, 0.0), known)
    H = biharmonic_fill(H, known)
    # Far from buildings the membrane is stretched between a few pins and cones
    # around each; blend it into a broad trend there. Near buildings it is exact.
    from scipy import ndimage
    dist = ndimage.distance_transform_edt(~known) * CELL
    trend = ndimage.gaussian_filter(H, TREND_SIGMA / CELL, mode="nearest")
    w = np.clip((dist - NEAR) / (FAR - NEAR), 0.0, 1.0)
    w = w * w * (3 - 2 * w)
    H = H * (1 - w) + trend * w
    gx, gz = np.gradient(H, CELL)
    slope = np.degrees(np.arctan(np.hypot(gx, gz)))
    free = ~known
    print(f"height {H.min():.1f}..{H.max():.1f}; street slope median {np.median(slope[free]):.1f} deg, "
          f"95th pct {np.percentile(slope[free], 95):.1f}, max {slope[free].max():.1f}")
    np.savez_compressed(OUT / "heights.npz", H=H, known=known, x0=x0, z0=z0, cell=CELL)
    print(f"-> {OUT / 'heights.npz'}")


if __name__ == "__main__":
    main()
