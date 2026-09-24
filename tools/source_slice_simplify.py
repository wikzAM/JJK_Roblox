"""Simplify the footprint rings so the map costs fewer parts.

Every ring vertex costs slab parts: PolygonSlab ear-clips the ring and each
triangle becomes one or two wedges. Slabs are 83% of the buildings' parts
(198,533 of 237,807, counted live). The rings carry far more detail than a
0.24 m/stud world can show: dropping vertices that move the outline less than a
fraction of the building's own size is invisible and takes out ~33,200 slab
parts (18% of slabs, ~11.5% of the map). An earlier version of this note also
counted a perimeter wall per edge; there are no perimeter walls.

The tolerance is ADAPTIVE (`FRACTION` of sqrt(footprint area), capped at `CAP`),
not fixed. A fixed 2-stud tolerance saves slightly more but spends the error on
the smallest buildings, where 2 studs is a real part of the footprint; scaling
it by size leaves the median footprint unchanged and holds the worst case to
about 6% of area on the smallest rings.

Every ring is GATED, and a ring that fails any check keeps its original outline:

  * stays a simple polygon (no self-intersection, no repeated vertex)
  * area changes by no more than `MAX_AREA_CHANGE`
  * every edge stays at least `MIN_EDGE` studs, so PolygonSlab can still find an
    exact native-size triangulation (its MIN_SIZE is 0.05)
  * keeps at least 4 vertices, and stays the same winding
  * `polygon_slab_sim.buildable` accepts it -- the Python replica of the Luau
    triangulator, so a ring that Studio would reject never reaches Studio

  python tools/source_slice_simplify.py [--apply] [--chunks DIR]

Without --apply it only reports. With --apply it rewrites the chunk files in
place (the originals go to <DIR>/../chunks_presimplify/ first).
"""
from pathlib import Path
import argparse
import json
import math
import shutil
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import numpy as np  # noqa: E402
from polygon_slab_sim import buildable  # noqa: E402

CAP = 3.0               # studs: never move a vertex further than this (0.72 m)
FRACTION = 0.03         # ...or further than this fraction of sqrt(footprint area)
MIN_EDGE = 0.30         # studs: well clear of PolygonSlab's 0.05 MIN_SIZE
MAX_AREA_CHANGE = 0.08  # refuse a ring that loses or gains more than this


def _dp(pts, tol):
    """Douglas-Peucker on an open chain."""
    if len(pts) < 3:
        return pts
    a, b = np.array(pts[0]), np.array(pts[-1])
    ab = b - a
    n = float(np.hypot(*ab))
    rel = np.array(pts) - a
    d = (np.abs(rel[:, 0] * ab[1] - rel[:, 1] * ab[0]) / n if n > 1e-9
         else np.hypot(rel[:, 0], rel[:, 1]))
    k = int(np.argmax(d))
    if d[k] <= tol:
        return [pts[0], pts[-1]]
    return _dp(pts[:k + 1], tol)[:-1] + _dp(pts[k:], tol)


def simplify_ring(ring, tol):
    """A ring has no natural endpoints, so it is cut in two and each half is
    simplified: cutting once would pin the seam vertex and leave a stray corner."""
    r = list(ring)
    k = len(r) // 2
    return _dp(r[:k + 1], tol)[:-1] + _dp(r[k:] + [r[0]], tol)[:-1]


def area(ring):
    P = np.array(ring, dtype=float)
    return float(np.sum(P[:, 0] * np.roll(P[:, 1], -1) - np.roll(P[:, 0], -1) * P[:, 1]) / 2)


def _seg_cross(a, b, c, d):
    def s(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    d1, d2, d3, d4 = s(c, d, a), s(c, d, b), s(a, b, c), s(a, b, d)
    return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0))


def is_simple(ring):
    n = len(ring)
    for i in range(n):
        for j in range(i + 1, n):
            if j == i or (i == 0 and j == n - 1) or j == i + 1:
                continue        # touching edges share a vertex by construction
            if _seg_cross(ring[i], ring[(i + 1) % n], ring[j], ring[(j + 1) % n]):
                return False
    return True


def shortest_edge(ring):
    P = np.array(ring, dtype=float)
    E = np.roll(P, -1, 0) - P
    return float(np.hypot(E[:, 0], E[:, 1]).min())


def try_simplify(ring):
    """Returns (new_ring, reason_refused). reason is None when it was accepted."""
    a0 = area(ring)
    if abs(a0) < 1.0:
        return ring, "degenerate"
    tol = min(CAP, FRACTION * math.sqrt(abs(a0)))
    out = simplify_ring(ring, tol)
    if len(out) < 4:
        return ring, "too few vertices"
    a1 = area(out)
    if (a1 > 0) != (a0 > 0):
        return ring, "winding flipped"
    if abs(abs(a1) - abs(a0)) / abs(a0) > MAX_AREA_CHANGE:
        return ring, "area moved too far"
    if shortest_edge(out) < MIN_EDGE:
        return ring, "edge below the native minimum"
    if not is_simple(out):
        return ring, "self-intersects"
    ok, _states = buildable(out, limit=2048)
    if not ok:
        return ring, "Studio could not triangulate it"
    return out, None


def parts_for(ring):
    """What the ring's slab costs: a rectangle is a single Part; anything else
    ear-clips to n-2 triangles, each needing one or two wedges (1.5 on average).
    (There are no perimeter walls -- an earlier version counted one per edge.)"""
    n = len(ring)
    return 1 if n == 4 else round((n - 2) * 1.5)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--chunks", default=str(ROOT / "source_slices" / "sweep" / "chunks"))
    args = ap.parse_args()
    D = Path(args.chunks)
    files = sorted(D.glob("*.json"))
    if not files:
        sys.exit(f"no chunk files in {D}")

    before = after = 0
    rings = changed = 0
    refused = {}
    worst = []
    out_files = {}
    for f in files:
        doc = json.loads(f.read_text())
        plans = doc.get("plans") if isinstance(doc, dict) else doc
        if not isinstance(plans, list):
            continue
        for p in plans:
            if not isinstance(p, dict) or "levels" not in p:
                continue
            for lv in p["levels"]:
                new_pieces = []
                for ring in lv["pieces"]:
                    rings += 1
                    before += parts_for(ring)
                    out, why = try_simplify(ring)
                    if why:
                        refused[why] = refused.get(why, 0) + 1
                    elif len(out) != len(ring):
                        changed += 1
                        da = abs(abs(area(out)) - abs(area(ring))) / abs(area(ring))
                        worst.append((da, p["id"], len(ring), len(out)))
                    after += parts_for(out)
                    new_pieces.append([[round(x, 4), round(z, 4)] for x, z in out])
                lv["pieces"] = new_pieces
        out_files[f] = doc

    worst.sort(reverse=True)
    print(f"{rings:,} rings over {len(out_files)} chunks; {changed:,} simplified")
    print(f"parts {before:,} -> {after:,}   saved {before - after:,} ({(before - after) / before:.0%})")
    if refused:
        print("refused (outline kept as it was):")
        for k, v in sorted(refused.items(), key=lambda kv: -kv[1]):
            print(f"  {k:32} {v:,}")
    if worst:
        print("largest area changes:")
        for da, bid, n0, n1 in worst[:5]:
            print(f"  {da:.1%}  {bid}  {n0} -> {n1} vertices")
    if not args.apply:
        print("\n(report only -- pass --apply to rewrite the chunks)")
        return
    backup = D.parent / "chunks_presimplify"
    if not backup.exists():
        shutil.copytree(D, backup)
        print(f"originals copied to {backup}")
    for f, doc in out_files.items():
        f.write_text(json.dumps(doc))
    print(f"rewrote {len(out_files)} chunk files in {D}")


if __name__ == "__main__":
    main()
