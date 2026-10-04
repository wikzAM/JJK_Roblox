"""No sunken buildings: hold the ground near every building at or below its
ground floor.

The owner: "the terrain just outside each building [should be] at or below
the terrain below the building" -- buildings looked sunk where the ground
around them rose above the ground-floor slab, which would bury a ground-floor
facade. Per building (tools/source_slices/live_footprints_top.txt, exported
from Studio: ground-floor rings + slab-top Y), the VISIBLE ground may reach at
most `slab top - GAP` within BAND studs of the footprint, then rise back at
SLOPE studs per stud. The cap only ever lowers ground.

Studio renders smooth terrain DELTA_MAX above the height it encodes (measured
Sept 30 on open ground: +2.2..+3.8, median +2.8), and GroundTerrain writes the
files at FILE_TO_STUDIO = +2.5, so a visible cap C is a file cap of
C - DELTA_MAX - 2.5.

Reads source_slices/ground/terrain_orig/ (a copy of the original chunks made on
first run), writes source_slices/ground/terrain/ with `h` clamped and `cap`
added (GradeCorridors applies `cap` last, so road grading cannot raise ground
next to a building again), plus ground_surface.npz: the expected VISIBLE ground
for road heights.

  python tools/ground_clamp.py
"""
import json
import shutil
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402

D = ROOT / "source_slices" / "ground"
GAP = 1.0          # studs the visible ground stays below a ground-floor slab top
BAND = 8.0         # studs from the footprint the cap stays flat (the sidewalk)
SLOPE = 0.5        # studs of rise per stud beyond the band
ROAD_CURB = 1.0    # studs a road surface stays below the nearest ground floors
ROAD_SLOPE = 0.08  # ... easing off this much per stud of distance
DELTA_MAX = 4.0    # visible - encoded, upper end (measured)
DELTA_MED = 2.8    # ... median, for the expected visible surface
FILE_TO_STUDIO = 2.5
CELL = 4.0
MAX_CUT = 10.0     # studs: buildings needing a deeper cut than this are skipped


def contains(P, C):
    x, z = C[:, 0], C[:, 1]
    inside = np.zeros(len(C), bool)
    j = len(P) - 1
    for i in range(len(P)):
        xi, zi, xj, zj = P[i, 0], P[i, 1], P[j, 0], P[j, 1]
        if zi != zj:
            inside ^= ((zi > z) != (zj > z)) & (x < (xj - xi) * (z - zi) / (zj - zi) + xi)
        j = i
    return inside


def main():
    src = D / "terrain_orig"
    if not src.exists():
        shutil.copytree(D / "terrain", src)
        print(f"original chunks backed up to {src}")
    index = json.loads((src / "index.json").read_text())
    chunks = {n: json.loads((src / f"{n}.json").read_text()) for n in index}
    gx0 = min(c["x0"] for c in chunks.values())
    gz0 = min(c["z0"] for c in chunks.values())
    gx1 = max(c["x0"] + c["nx"] * CELL for c in chunks.values())
    gz1 = max(c["z0"] + c["nz"] * CELL for c in chunks.values())
    NX, NZ = int(round((gx1 - gx0) / CELL)), int(round((gz1 - gz0) / CELL))
    H = np.full((NX, NZ), np.nan)
    for c in chunks.values():
        i0, k0 = int(round((c["x0"] - gx0) / CELL)), int(round((c["z0"] - gz0) / CELL))
        H[i0:i0 + c["nx"], k0:k0 + c["nz"]] = np.array(c["h"]).reshape(c["nx"], c["nz"])

    # 1. ground-floor tops rasterised: the LOWEST building top covering each cell
    tops = {}
    polys = []
    for line in open(ROOT / "source_slices" / "live_footprints_top.txt", encoding="utf-8"):
        parts = line.strip().split("|")
        if len(parts) != 3:
            continue
        name, top, pts = parts[0], float(parts[1]), parts[2]
        tops[name] = min(tops.get(name, top), top)
        polys.append((name, np.array([[float(a) for a in p.split(",")] for p in pts.split(";")])))
    # per building: which cells it covers (to judge how deep a cut it would need)
    cells = {}
    for name, P in polys:
        if len(P) < 3:
            continue
        i0 = max(int((P[:, 0].min() - gx0) / CELL) - 1, 0)
        i1 = min(int((P[:, 0].max() - gx0) / CELL) + 2, NX)
        k0 = max(int((P[:, 1].min() - gz0) / CELL) - 1, 0)
        k1 = min(int((P[:, 1].max() - gz0) / CELL) + 2, NZ)
        if i1 <= i0 or k1 <= k0:
            continue
        I, K = np.meshgrid(np.arange(i0, i1), np.arange(k0, k1), indexing="ij")
        C = np.stack([gx0 + (I + 0.5) * CELL, gz0 + (K + 0.5) * CELL], -1).reshape(-1, 2)
        m = contains(P, C).reshape(I.shape)
        cells.setdefault(name, []).append((I[m], K[m]))
    # a building whose ground floor sits more than MAX_CUT below the natural ground
    # around it is a basement / bad record: cutting the ground down to it would
    # leave a crater, so it is skipped (and reported)
    skip = set()
    occ = np.zeros((NX, NZ), bool)
    for name, lst in cells.items():
        for I, K in lst: occ[I, K] = True
    for name, lst in cells.items():
        I = np.concatenate([a for a, _ in lst]); K = np.concatenate([b for _, b in lst])
        if len(I) == 0:
            continue
        sub_i0, sub_i1 = max(I.min() - 4, 0), min(I.max() + 5, NX)
        sub_k0, sub_k1 = max(K.min() - 4, 0), min(K.max() + 5, NZ)
        m = np.zeros((sub_i1 - sub_i0, sub_k1 - sub_k0), bool)
        m[I - sub_i0, K - sub_k0] = True
        ring = ndimage.binary_dilation(m, iterations=3) & ~m & ~occ[sub_i0:sub_i1, sub_k0:sub_k1]
        around = H[sub_i0:sub_i1, sub_k0:sub_k1][ring]
        around = around[~np.isnan(around)]
        if len(around):
            natural_visible = float(np.median(around)) + FILE_TO_STUDIO + DELTA_MED
            if natural_visible - (tops[name] - GAP) > MAX_CUT:
                skip.add(name)
    print(f"{len(skip)} buildings skipped: ground floor more than {MAX_CUT} studs below the ground around them")
    T = np.full((NX, NZ), np.inf)
    for name, P in polys:
        if name in skip:
            continue
        if len(P) < 3:
            continue
        top = tops[name]
        i0 = max(int((P[:, 0].min() - gx0) / CELL) - 1, 0)
        i1 = min(int((P[:, 0].max() - gx0) / CELL) + 2, NX)
        k0 = max(int((P[:, 1].min() - gz0) / CELL) - 1, 0)
        k1 = min(int((P[:, 1].max() - gz0) / CELL) + 2, NZ)
        if i1 <= i0 or k1 <= k0:
            continue
        I, K = np.meshgrid(np.arange(i0, i1), np.arange(k0, k1), indexing="ij")
        C = np.stack([gx0 + (I + 0.5) * CELL, gz0 + (K + 0.5) * CELL], -1).reshape(-1, 2)
        m = contains(P, C).reshape(I.shape)
        sub = T[i0:i1, k0:k1]
        sub[m] = np.minimum(sub[m], top)
    # 2. the visible cap: top - GAP on and within BAND of the footprint, then a cone
    cap = np.where(np.isfinite(T), T - GAP, np.inf)
    band = int(round(BAND / CELL))
    cap = ndimage.minimum_filter(cap, size=2 * band + 1, mode="nearest")   # flat band
    step, diag = SLOPE * CELL, SLOPE * CELL * 2 ** 0.5
    for _ in range(200):
        p = np.pad(cap, 1, mode="edge")
        new = np.minimum.reduce([cap, p[:-2, 1:-1] + step, p[2:, 1:-1] + step, p[1:-1, :-2] + step, p[1:-1, 2:] + step,
                                 p[:-2, :-2] + diag, p[:-2, 2:] + diag, p[2:, :-2] + diag, p[2:, 2:] + diag])
        if np.array_equal(new, cap):
            break
        cap = new
    # 3. file heights clamped, and the expected visible surface for the roads
    file_cap = cap - DELTA_MAX - FILE_TO_STUDIO
    clamped = np.where(np.isnan(H), H, np.minimum(H, file_cap))
    lowered = np.nansum((H - clamped) > 0.05)
    visible = clamped + FILE_TO_STUDIO + DELTA_MED
    # written to terrain_clamped/ -- tools/road_ground.py builds the final
    # terrain/ chunks from these plus the roads
    out = D / "terrain_clamped"
    out.mkdir(exist_ok=True)
    for name, c in chunks.items():
        i0, k0 = int(round((c["x0"] - gx0) / CELL)), int(round((c["z0"] - gz0) / CELL))
        hc = clamped[i0:i0 + c["nx"], k0:k0 + c["nz"]]
        fc = file_cap[i0:i0 + c["nx"], k0:k0 + c["nz"]]
        c2 = dict(c)
        c2["h"] = [round(float(v), 2) for v in hc.ravel()]
        c2["cap"] = [round(float(v), 2) if np.isfinite(v) else 99999 for v in fc.ravel()]
        (out / f"{name}.json").write_text(json.dumps(c2))
    (out / "index.json").write_text(json.dumps(index))
    # ROAD cap: a street surface stays ROAD_CURB below every nearby ground floor,
    # easing off at ROAD_SLOPE per stud (owner, Oct 4: the roads sat above the
    # ground floors -- median +0.4 studs, p90 +4.7). road_fit takes min(G, RC).
    rc = np.where(np.isfinite(T), T - ROAD_CURB, np.inf)
    step, diag = ROAD_SLOPE * CELL, ROAD_SLOPE * CELL * 2 ** 0.5
    for _ in range(400):
        p_ = np.pad(rc, 1, mode="edge")
        new = np.minimum.reduce([rc, p_[:-2, 1:-1] + step, p_[2:, 1:-1] + step, p_[1:-1, :-2] + step, p_[1:-1, 2:] + step,
                                 p_[:-2, :-2] + diag, p_[:-2, 2:] + diag, p_[2:, :-2] + diag, p_[2:, 2:] + diag])
        if np.array_equal(new, rc):
            break
        rc = new
    np.savez_compressed(D / "ground_surface.npz", G=visible.astype(np.float32),
                        RC=np.where(np.isfinite(rc), rc, 1e6).astype(np.float32), x0=gx0, z0=gz0, cell=CELL)
    drop = H - clamped
    outside = ~occ & ~np.isnan(drop)
    od = drop[outside & (drop > 0.05)]
    print(f"OUTSIDE footprints: {len(od)} columns lowered, median {np.median(od):.1f}, p90 {np.percentile(od, 90):.1f}, "
          f"p99 {np.percentile(od, 99):.1f}, max {od.max():.1f} studs")
    big = np.argwhere(outside & (drop > 15))
    if len(big):
        bi, bk = big[len(big) // 2]
        print(f"  e.g. a {drop[bi, bk]:.0f}-stud cut at ({gx0 + bi * CELL:.0f}, {gz0 + bk * CELL:.0f}); cells over 15: {len(big)}")
    print(f"grid {NX}x{NZ}; {len(tops)} buildings; lowered {lowered} columns "
          f"(mean drop {np.nanmean((H - clamped)[(H - clamped) > 0.05]):.1f} studs, max {np.nanmax(H - clamped):.1f})")
    print(f"-> {out} (h clamped + cap), {D / 'ground_surface.npz'}")


if __name__ == "__main__":
    main()
