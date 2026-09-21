"""Does a generated plan's floor plate stick out of the FBX it was sliced from?

Compares each level's polygon against the FBX section at that level's own height,
in world coordinates. "Bigger than the greys" is not evidence of a defect -- the
greys are fragments and a correct slice should exceed them -- but sticking out of
the FBX is, and that is what the review6 preview showed as orange through red.

  python tools/source_slice_pokeout.py [plansDir]
"""
from pathlib import Path
import csv, glob, json, sys
import numpy as np
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections
from shapely.geometry import Polygon, box
from shapely.ops import unary_union

DATA = ROOT / "source_slices"
ARGS = [a for a in sys.argv[1:] if not a.startswith("--")]
PLANS = Path(ARGS[0]) if ARGS else DATA / "plans_v2"
# --json <file> writes the same rows machine-readably, so a sweep of a thousand
# plans can be gated without a human reading the table.
JSON_OUT = next((Path(a.split("=", 1)[1]) for a in sys.argv[1:]
                 if a.startswith("--json=")), None)

triangles = np.load(DATA / "world_triangles.npz")["triangles"]
ext = {r["n"]: r for r in csv.DictReader(open(DATA / "live_extents.csv"))}

def world_ring(piece, ox, oz, yaw):
    cos, sin = np.cos(yaw), np.sin(yaw)
    # builder: world = origin + Rot(yaw) * (x, z); inverse of to_local
    return [(ox + cos * a + sin * b, oz - sin * a + cos * b) for a, b in piece]

rows = []
for path in sorted(glob.glob(str(PLANS / "*.json"))):
    plan = json.load(open(path))
    si = plan["sourceInfo"]
    o = plan["origin"]
    ox, oz, yaw, oy = o["x"], o["z"], o["yaw"], o["y"]
    names = ["BuildingSmooth_" + n[len("BuildingSmooth_"):] for n in si["replaces"]]
    rects = [box(float(ext[n[len('BuildingSmooth_'):]]["x0"]), float(ext[n[len('BuildingSmooth_'):]]["z0"]),
                 float(ext[n[len('BuildingSmooth_'):]]["x1"]), float(ext[n[len('BuildingSmooth_'):]]["z1"]))
             for n in names if n[len('BuildingSmooth_'):] in ext]
    region = unary_union(rects) if rects else None
    cx, cz = ox, oz
    lo = triangles[:, :, [0, 2]].min(axis=1); hi = triangles[:, :, [0, 2]].max(axis=1)
    keep = ((hi[:,0]>=cx-400)&(lo[:,0]<=cx+400)&(hi[:,1]>=cz-400)&(lo[:,1]<=cz+400))
    local = triangles[keep]

    worst, checked, unsupported = 0.0, 0, 0
    iou_sum, miss_worst = 0.0, 0.0
    for lv in plan["levels"]:
        y = oy + lv["y"] + lv["thickness"] / 2
        if y < si["fbxBottom"] or y > si["fbxTop"]:
            continue          # base extension: the FBX is legitimately absent here
        plate = unary_union([Polygon(world_ring(p, ox, oz, yaw)).buffer(0) for p in lv["pieces"]])
        if plate.is_empty or plate.area <= 0:
            continue
        # Outside-only is not enough to say a floor "follows the geometry": a plate
        # that is far too SMALL scores 0% outside. Measure both directions.
        #   outside = plate area not in the FBX      (plate spills out)
        #   missing = FBX section area not in plate  (plate under-covers)
        #   iou     = agreement of the two shapes
        # The building's own section is selected by overlap with the greys' region,
        # independently of the plate, so under-coverage cannot hide.
        best = None
        for offset in (0.0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0, 3.0, -3.0):
            polys = [p for p in sections(local, float(y + offset))[0] if p.area >= 100]
            # SELECTION MUST MATCH THE BUILDER'S. Requiring only `intersection >=
            # 300` pulls in neighbouring buildings that merely clip the greys'
            # axis-aligned region, and then scores the plate as missing them: it
            # reported fbx_poly_170_56 as 89% under-covering when the plate
            # actually matches its own section to 0.1%. Shibuya is dense; a loose
            # rule always finds a neighbour.
            if region is not None:
                mine = [p for p in polys
                        if p.area >= 400
                        and p.intersection(region).area >= 300
                        and p.intersection(region).area / p.area >= 0.35]
            else:
                mine = polys
            if not mine:
                continue
            fbx = unary_union(mine)
            if plate.intersection(fbx).area <= 0:
                continue
            inter = plate.intersection(fbx).area
            outside = plate.difference(fbx).area / plate.area
            missing = fbx.difference(plate).area / fbx.area
            iou = inter / unary_union([plate, fbx]).area
            if best is None or iou > best[2]:
                best = (outside, missing, iou)
            if iou >= 0.995:
                break
        if best is None:
            unsupported += 1
            continue
        worst = max(worst, best[0])
        miss_worst = max(miss_worst, best[1])
        iou_sum += best[2]
        checked += 1

    if checked:
        rows.append((plan["id"], worst, checked, len(plan["levels"]), unsupported,
                     miss_worst, iou_sum / checked))

rows.sort(key=lambda r: -r[1])
print(f"{PLANS.name}: {len(rows)} plans with levels inside the FBX band\n")
print(f"{'plan':24s} {'out%':>7s} {'miss%':>7s} {'meanIoU':>8s}  levels")
rows.sort(key=lambda r: r[6])
for pid, worst, checked, total, unsup, miss, iou in rows:
    flag = f"  ({unsup} hole)" if unsup else ""
    print(f"{pid:24s} {worst*100:6.1f}% {miss*100:6.1f}% {iou:8.3f}  {checked}/{total}{flag}")
vals = [r[1] for r in rows]
ious = sorted(r[6] for r in rows)
misses = sorted(r[5] for r in rows)
if vals:
    vals_sorted = sorted(vals)
    print(f"\nmedian {np.median(vals)*100:.1f}%   p90 {vals_sorted[int(len(vals)*0.9)]*100:.1f}%   "
          f"max {max(vals)*100:.1f}%")
    print(f"plans with >5% outside: {sum(1 for v in vals if v > 0.05)} / {len(vals)}")
    print(f"mean IoU: median {ious[len(ious)//2]:.3f}  p10 {ious[max(0,int(len(ious)*0.1))]:.3f}  "
          f"min {ious[0]:.3f}   |   worst under-coverage: median {misses[len(misses)//2]*100:.1f}%  "
          f"max {misses[-1]*100:.1f}%")
    print(f"plans with mean IoU >= 0.95: {sum(1 for v in ious if v >= 0.95)} / {len(ious)}")
    print(f"levels with no FBX geometry at all (mesh holes): "
          f"{sum(r[4] for r in rows)} across {sum(1 for r in rows if r[4])} plans")


if JSON_OUT is not None:
    JSON_OUT.parent.mkdir(parents=True, exist_ok=True)
    JSON_OUT.write_text(json.dumps([
        {"id": pid, "outside": worst, "checked": checked, "levels": total,
         "holes": unsup, "missing": miss, "iou": iou}
        for pid, worst, checked, total, unsup, miss, iou in rows], indent=1))
    print(f"wrote {len(rows)} rows -> {JSON_OUT}")
