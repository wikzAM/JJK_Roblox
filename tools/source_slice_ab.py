"""A/B: at the same building and the same height, which follows the FBX better --
the live grey fragments, or the generated slice?

Both are scored the same way against the FBX cross-section at that height:
  IoU, spill (plate area outside the FBX), miss (FBX area not covered).

Greys come from group_floors.txt (every storey of every member grey of a plan,
as its slab parts' world XZ footprints). Slices come from the plan JSON.

  python tools/source_slice_ab.py [plansDir]
"""
from pathlib import Path
import glob, json, sys
from collections import defaultdict
import numpy as np
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections
from shapely.geometry import MultiPoint, Polygon
from shapely.ops import unary_union

DATA = ROOT / "source_slices"
PLANS = Path(sys.argv[1]) if len(sys.argv) > 1 else DATA / "plans_v4"
tri = np.load(DATA / "world_triangles.npz")["triangles"]

grey = defaultdict(dict)          # plan id -> floor bottom Y -> polygon
for line in (DATA / "group_floors.txt").read_text().splitlines():
    if not line.strip():
        continue
    pid, y, blob = line.split("|", 2)
    pieces = []
    for part in blob.split("/"):
        pts = [tuple(float(v) for v in p.split()) for p in part.split(";") if p]
        if len(pts) >= 3:
            pieces.append(MultiPoint(pts).convex_hull)
    if pieces:
        poly = unary_union(pieces).buffer(0)
        if not poly.is_empty:
            y = float(y)
            grey[pid][y] = unary_union([grey[pid][y], poly]) if y in grey[pid] else poly

def score(shape, fbx):
    if shape is None or shape.is_empty or fbx is None or fbx.is_empty:
        return None
    inter = shape.intersection(fbx).area
    if inter <= 0:
        return (0.0, 1.0, 1.0)
    return (inter / unary_union([shape, fbx]).area,
            shape.difference(fbx).area / shape.area,
            fbx.difference(shape).area / fbx.area)

rows = []
for path in sorted(glob.glob(str(PLANS / "*.json"))):
    plan = json.load(open(path))
    pid, si, o = plan["id"], plan["sourceInfo"], plan["origin"]
    if pid not in grey:
        continue
    ox, oz, yaw, oy = o["x"], o["z"], o["yaw"], o["y"]
    cos, sin = np.cos(yaw), np.sin(yaw)
    def w(r): return [(ox + cos*a + sin*b, oz - sin*a + cos*b) for a, b in r]
    lo = tri[:, :, [0, 2]].min(axis=1); hi = tri[:, :, [0, 2]].max(axis=1)
    keep = ((hi[:,0]>=ox-400)&(lo[:,0]<=ox+400)&(hi[:,1]>=oz-400)&(lo[:,1]<=oz+400))
    local = tri[keep]
    gi, si_, n = [], [], 0
    for lv in plan["levels"]:
        y = oy + lv["y"] + lv["thickness"] / 2
        if y < si["fbxBottom"] or y > si["fbxTop"]:
            continue
        plate = unary_union([Polygon(w(p)).buffer(0) for p in lv["pieces"]])
        # nearest exported grey storey to this height
        cand = min(grey[pid], key=lambda gy: abs(gy + 2.7 - y), default=None)
        if cand is None or abs(cand + 2.7 - y) > 9:
            continue
        gpoly = grey[pid][cand]
        best = None
        for off in (0.0, 0.6, -0.6, 1.5, -1.5, 3.0, -3.0):
            polys = [p for p in sections(local, float(y + off))[0] if p.area >= 100]
            mine = [p for p in polys
                    if p.intersection(plate).area > 0 or p.intersection(gpoly).area > 0]
            if not mine:
                continue
            fbx = unary_union(mine)
            a, b = score(plate, fbx), score(gpoly, fbx)
            if a is None or b is None:
                continue
            if best is None or (a[0] + b[0]) > (best[0][0] + best[1][0]):
                best = (a, b)
        if best is None:
            continue
        si_.append(best[0]); gi.append(best[1]); n += 1
    if n:
        rows.append((pid, n,
                     sum(x[0] for x in si_)/n, sum(x[1] for x in si_)/n, sum(x[2] for x in si_)/n,
                     sum(x[0] for x in gi)/n,  sum(x[1] for x in gi)/n,  sum(x[2] for x in gi)/n))

print(f"{len(rows)} plans compared, level by level, against the FBX at the same height\n")
print(f"{'plan':22s} {'lv':>3}  {'SLICE IoU':>9} {'spill':>6} {'miss':>6}   "
      f"{'GREY IoU':>8} {'spill':>6} {'miss':>6}   winner")
better = 0
for pid, n, si_iou, si_out, si_miss, g_iou, g_out, g_miss in sorted(rows, key=lambda r: r[2]-r[5]):
    win = "slice" if si_iou > g_iou + 0.01 else ("grey" if g_iou > si_iou + 0.01 else "tie")
    if win == "slice": better += 1
    print(f"{pid:22s} {n:3d}  {si_iou:9.3f} {si_out*100:5.1f}% {si_miss*100:5.1f}%   "
          f"{g_iou:8.3f} {g_out*100:5.1f}% {g_miss*100:5.1f}%   {win}")
if rows:
    s_iou = sorted(r[2] for r in rows); g_iou = sorted(r[5] for r in rows)
    print(f"\nmedian IoU  slice {s_iou[len(s_iou)//2]:.3f}   grey {g_iou[len(g_iou)//2]:.3f}")
    print(f"IoU >= 0.95 slice {sum(1 for v in s_iou if v>=0.95)}/{len(rows)}   "
          f"grey {sum(1 for v in g_iou if v>=0.95)}/{len(rows)}")
    print(f"slice strictly better on {better}/{len(rows)} plans")
