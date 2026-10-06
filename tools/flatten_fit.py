"""Option B (owner, Oct 6): one smooth gentle ground surface for the whole city.

Fits a smooth surface S to the buildings' ground floors (robust: buildings far
off the local trend are left out of the fit), limited to MAX_GRADE, then gives
each building the vertical move that puts its ground floor (lowest Floor1
piece top) on S + FLOOR_UP at its footprint.

  python tools/flatten_fit.py -> source_slices/ground/flatten.json  {building: dy}
                                 source_slices/ground/flat_surface.npz (S, visible ground)
"""
import collections
import json
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402
from live_footprints import contains  # noqa: E402
from floor_cap import hull  # noqa: E402

D = ROOT / "source_slices" / "ground"
CELL = 4.0
SIGMA = 100           # cells (400 studs): the scale of the surface (owner, Oct 6: flatter, gradual)
OUTLIER = 25.0        # studs off the local trend: left out of the fit (and not moved)
MAX_GRADE = 0.05      # rise per stud the surface is limited to
MAX_MOVE = 130.0      # studs: groups needing more are left where they are (reported)
FLOOR_UP = 2.0        # studs a ground-floor top sits above the surface


def main():
    fc = np.load(D / "floor_cap.npz")
    x0, z0 = float(fc["x0"]), float(fc["z0"])
    NX, NZ = fc["BM"].shape
    bfloor, bcells = {}, collections.defaultdict(set)
    # moves already applied in Studio (FlattenDY): the export holds moved floors
    pf = D / "flatten.json"
    prev = json.loads(pf.read_text()) if pf.exists() else {}
    (D / "flatten_prev.json").write_text(json.dumps(prev))
    for line in open(ROOT / "source_slices" / "floor1_parts.txt", encoding="utf-8"):
        f = line.strip().split("|")
        if len(f) != 3:
            continue
        top = float(f[1]) - prev.get(f[0], 0.0)     # the ORIGINAL floor (before any flattening)
        bfloor[f[0]] = min(bfloor.get(f[0], 1e9), top)
        P = hull(np.array([[float(a) for a in q.split(",")] for q in f[2].split(";")]))
        if len(P) < 3:
            continue
        i0 = max(int((P[:, 0].min() - x0) / CELL), 0); i1 = min(int((P[:, 0].max() - x0) / CELL) + 1, NX)
        k0 = max(int((P[:, 1].min() - z0) / CELL), 0); k1 = min(int((P[:, 1].max() - z0) / CELL) + 1, NZ)
        if i1 <= i0 or k1 <= k0:
            continue
        I, K = np.meshgrid(np.arange(i0, i1), np.arange(k0, k1), indexing="ij")
        C = np.stack([x0 + (I + 0.5) * CELL, z0 + (K + 0.5) * CELL], -1).reshape(-1, 2)
        m = contains(P, C).reshape(I.shape)
        for px, pz in np.vstack([P, P.mean(0)[None]]):
            i, k = int((px - x0) / CELL), int((pz - z0) / CELL)
            if i0 <= i < i1 and k0 <= k < k1:
                m[i - i0, k - k0] = True
        for i, k in zip(I[m], K[m]):
            bcells[f[0]].add((int(i), int(k)))
    names = [n for n in bfloor if bcells[n]]
    # STACKED buildings move together: a tower body standing on a podium (its own
    # model, Floor1 high up) shares footprint cells with the podium
    owner = collections.defaultdict(list)
    for n in names:
        for c in bcells[n]:
            owner[c].append(n)
    parent = {n: n for n in names}

    def find(n):
        while parent[n] != n:
            parent[n] = parent[parent[n]]; n = parent[n]
        return n
    for c, ns in owner.items():
        for m in ns[1:]:
            parent[find(m)] = find(ns[0])
    # pairs that collided when moved apart (Studio check): they move together
    lk = D / "flatten_links.txt"
    if lk.exists():
        for line in lk.read_text().splitlines():
            ab = line.split("|")
            if len(ab) >= 2 and ab[0] in parent and ab[1] in parent:
                parent[find(ab[0])] = find(ab[1])
    groups = collections.defaultdict(list)
    for n in names:
        groups[find(n)].append(n)
    base = {g: min(ms, key=lambda m: bfloor[m]) for g, ms in groups.items()}   # the group's ground floor
    print(f"{len(names)} buildings in {len(groups)} stacked groups")
    names_all = names
    names = [base[g] for g in groups]                                        # the fit uses the bases only
    for g, ms in groups.items():
        bcells[base[g]] = set().union(*(bcells[m] for m in ms))
    use = set(names)
    for it in range(4):
        F = np.zeros((NX, NZ)); W = np.zeros((NX, NZ))
        for n in use:
            for i, k in bcells[n]:
                F[i, k] += bfloor[n]; W[i, k] += 1
        Wb = ndimage.gaussian_filter(W, SIGMA)
        S = ndimage.gaussian_filter(F, SIGMA) / np.maximum(Wb, 1e-9)
        dev = {n: np.mean([S[c] for c in bcells[n]]) - bfloor[n] for n in names}
        use = {n for n in names if abs(dev[n]) <= OUTLIER}
    # gentle: a second pass smooths only where the grade is over MAX_GRADE
    for _ in range(6):
        gy, gx = np.gradient(S, CELL)
        steep = ndimage.binary_dilation(np.hypot(gx, gy) > MAX_GRADE, iterations=6)
        S = np.where(steep, ndimage.gaussian_filter(S, 8), S)
    moves = {}
    out = []
    skip = []
    for g, ms in groups.items():
        n = base[g]
        tgt = float(np.mean([S[c] for c in bcells[n]])) + FLOOR_UP
        dy = tgt - bfloor[n]
        if abs(dy) > MAX_MOVE:
            out.append((round(dy, 1), n))
            skip.extend(ms)
            continue
        for m in ms:
            moves[m] = round(dy, 2)
    d = np.abs(np.array(list(moves.values())))
    gy, gx = np.gradient(S, CELL)
    g = np.hypot(gx, gy)[Wb > 1e-3]
    print(f"{len(moves)} buildings moved: median {np.median(d):.1f} p90 {np.percentile(d, 90):.1f} max {d.max():.1f} studs; "
          f"surface grade p50 {np.percentile(g, 50) * 100:.1f}% p95 {np.percentile(g, 95) * 100:.1f}% max {g.max() * 100:.1f}%")
    print(f"{len(out)} groups left where they are (move > {MAX_MOVE}):")
    for dy, n in sorted(out, key=lambda t: -abs(t[0]))[:15]:
        print(f"   {dy:+7.1f}  {n}  floor {bfloor[n]:.0f}")
    (D / "flatten.json").write_text(json.dumps(moves, indent=0))
    (D / "flatten_skip.json").write_text(json.dumps(sorted(skip)))   # left in place: no ground pinned to them
    np.savez_compressed(D / "flat_surface.npz", S=S.astype(np.float32), x0=x0, z0=z0, cell=CELL)


if __name__ == "__main__":
    main()
