"""How well do the live greys actually match the FBX? The honest version.

Replaces fill_survey.json's `fill`, which divided FBX polygon area by grey
BOUNDING BOX area. Greys are not boxes -- measured, the median grey fills 55% of
its own bounding box -- so that ratio reported a perfectly fitting grey as ~45%
oversized. Every "N greys are oversized" number derived from it is withdrawn.

This compares like with like: a grey's MATERIAL footprint area (summed
SlabFootprintArea of its widest storey, from live_extents.csv via PartExtents)
against the area of the FBX section under its own centre at its own mid-height.

  python tools/source_slice_fit_survey.py [sampleSize]

A ratio near 1.0 means the grey already reproduces the FBX footprint.
"""
from pathlib import Path
import csv, json, random, sys
import numpy as np
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections
from shapely.geometry import Point

DATA = ROOT / "source_slices"
SAMPLE = int(sys.argv[1]) if len(sys.argv) > 1 else 250

triangles = np.load(DATA / "world_triangles.npz")["triangles"]
rows = [r for r in csv.DictReader(open(DATA / "live_extents.csv"))]
# Single-member buildings only: a fragment's own centre is not a fair probe.
solo = [r for r in rows if not any(t in r["n"] for t in ("_Body", "_Residual"))
        and float(r["fa"]) > 200]
random.seed(7)
pick = random.sample(solo, min(SAMPLE, len(solo)))

ratios, missed = [], 0
for r in pick:
    cx = (float(r["x0"]) + float(r["x1"])) / 2
    cz = (float(r["z0"]) + float(r["z1"])) / 2
    y0, y1, fa = float(r["y0"]), float(r["y1"]), float(r["fa"])
    pt = Point(cx, cz)
    lo = triangles[:, :, [0, 2]].min(axis=1); hi = triangles[:, :, [0, 2]].max(axis=1)
    keep = ((hi[:, 0] >= cx - 200) & (lo[:, 0] <= cx + 200)
            & (hi[:, 1] >= cz - 200) & (lo[:, 1] <= cz + 200))
    local = triangles[keep]
    best = None
    # Several heights, because the export drops sections at scattered levels.
    for frac in (0.3, 0.5, 0.7, 0.4, 0.6):
        y = y0 + (y1 - y0) * frac
        hits = [p for p in sections(local, float(y))[0] if p.contains(pt)]
        if hits:
            best = max(hits, key=lambda q: q.area)
            break
    if best is None:
        missed += 1
        continue
    ratios.append(fa / best.area)

ratios.sort()
if ratios:
    def pct(p): return ratios[min(len(ratios) - 1, int(len(ratios) * p))]
    print(f"sampled {len(pick)} solo greys; {len(ratios)} had an FBX section under their centre, "
          f"{missed} did not\n")
    print("grey MATERIAL area / FBX section area")
    print(f"  p05 {pct(0.05):.2f}   p25 {pct(0.25):.2f}   median {pct(0.50):.2f}   "
          f"p75 {pct(0.75):.2f}   p95 {pct(0.95):.2f}")
    within = sum(1 for v in ratios if 0.9 <= v <= 1.1)
    print(f"  within +/-10% of the FBX: {within}/{len(ratios)} ({within/len(ratios):.0%})")
    print(f"  more than 25% larger:     {sum(1 for v in ratios if v > 1.25)}/{len(ratios)}")
    print(f"  more than 25% smaller:    {sum(1 for v in ratios if v < 0.75)}/{len(ratios)}")
