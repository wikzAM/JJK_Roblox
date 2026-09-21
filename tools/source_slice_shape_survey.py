"""How closely do floor plates follow the FBX geometry? Shape, not area.

Area agreement is not fidelity: two different outlines can have identical area.
This measures IoU between a floor's real outline and the FBX cross-section at
that floor's own height, for the live grey buildings.

Input: tools/source_slices/grey_floors.txt, written from Studio by exporting each
sampled grey's widest storey as its slab parts' world-space XZ footprints
(PartExtents.Corners; a WedgePart contributes its 3 material corners, a Part its
4). Each part is convex, so its hull is its footprint; the union is the floor.

  python tools/source_slice_shape_survey.py
"""
from pathlib import Path
import sys
import numpy as np
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections
from shapely.geometry import MultiPoint, Polygon
from shapely.ops import unary_union

DATA = ROOT / "source_slices"
triangles = np.load(DATA / "world_triangles.npz")["triangles"]

rows, skipped = [], 0
for line in (DATA / "grey_floors.txt").read_text().splitlines():
    if not line.strip():
        continue
    name, y_text, blob = line.split("|", 2)
    y = float(y_text)
    pieces = []
    for part in blob.split("/"):
        pts = [tuple(float(v) for v in p.split()) for p in part.split(";") if p]
        if len(pts) >= 3:
            pieces.append(MultiPoint(pts).convex_hull)
    if not pieces:
        continue
    floor = unary_union(pieces).buffer(0)
    if floor.is_empty or floor.area < 100:
        continue
    cx, cy = floor.centroid.x, floor.centroid.y
    lo = triangles[:, :, [0, 2]].min(axis=1); hi = triangles[:, :, [0, 2]].max(axis=1)
    keep = ((hi[:, 0] >= cx - 250) & (lo[:, 0] <= cx + 250)
            & (hi[:, 1] >= cy - 250) & (lo[:, 1] <= cy + 250))
    local = triangles[keep]
    best = None
    # The slab's own mid-height, then nearby: the export drops sections.
    for offset in (2.7, 0.0, 5.0, -2.0, 8.0, 11.0):
        polys = [p for p in sections(local, float(y + offset))[0] if p.area >= 100]
        mine = [p for p in polys if p.intersection(floor).area >= 0.10 * min(p.area, floor.area)]
        if not mine:
            continue
        fbx = unary_union(mine)
        inter = floor.intersection(fbx).area
        if inter <= 0:
            continue
        iou = inter / unary_union([floor, fbx]).area
        out = floor.difference(fbx).area / floor.area
        miss = fbx.difference(floor).area / fbx.area
        if best is None or iou > best[0]:
            best = (iou, out, miss)
        if iou >= 0.99:
            break
    if best is None:
        skipped += 1
        continue
    rows.append((name, *best))

if not rows:
    print("no comparable floors"); raise SystemExit

ious = sorted(r[1] for r in rows)
outs = sorted(r[2] for r in rows)
misses = sorted(r[3] for r in rows)
def pct(v, p): return v[min(len(v) - 1, int(len(v) * p))]
print(f"{len(rows)} live grey floors compared to the FBX section at their own height "
      f"({skipped} had no section)\n")
print("IoU of grey floor outline vs FBX cross-section")
print(f"  p05 {pct(ious,0.05):.3f}  p25 {pct(ious,0.25):.3f}  median {pct(ious,0.50):.3f}  "
      f"p75 {pct(ious,0.75):.3f}  p95 {pct(ious,0.95):.3f}")
for t in (0.98, 0.95, 0.90, 0.80):
    print(f"  IoU >= {t:.2f}: {sum(1 for v in ious if v >= t):3d}/{len(ious)} "
          f"({sum(1 for v in ious if v >= t)/len(ious):.0%})")
print(f"\ngrey spills OUTSIDE the FBX : median {pct(outs,0.5)*100:5.1f}%  p95 {pct(outs,0.95)*100:5.1f}%")
print(f"grey MISSES FBX floor area  : median {pct(misses,0.5)*100:5.1f}%  p95 {pct(misses,0.95)*100:5.1f}%")
print("\nworst 8 by IoU:")
for name, iou, out, miss in sorted(rows, key=lambda r: r[1])[:8]:
    print(f"  {name[:44]:44s} IoU {iou:.3f}  out {out*100:5.1f}%  miss {miss*100:5.1f}%")
