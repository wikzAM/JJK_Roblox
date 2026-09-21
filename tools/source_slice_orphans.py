"""Find every building the FBX has that the map does not, and plan it from roofs.

The section pipeline is GREY-DRIVEN: it only ever slices the FBX under an
existing grey. Shibuya PARCO never had a grey, so it was never considered; the
greys that did exist but whose walls never close ("FBX band too short", "no FBX
section") were refused. This pass starts from the FBX itself.

IDENTITY comes from mesh connectivity. The export is PLATEAU: each building is
its own surfaces, welded to itself and not to its neighbour, so a connected
mesh component is a building (PARCO is exactly one: 261 triangles). A roof
height map was tried first and cannot do this -- touching buildings share a
roof edge in plan, so it either split PARCO into nine pieces (no bridging) or
fused whole blocks into one 864,793 sq stud "building" (with bridging).
Components STACKED on each other in plan -- a tower on its podium, where the
patchy walls leave the two unwelded -- are merged; side-by-side ones are not.

GEOMETRY comes from each building's OWN roof faces (source_slice_roofs), so a
neighbour can never leak into its plates.

  python tools/source_slice_orphans.py --out tools/source_slices/orphans

Plans are written with id `orph_<x>_<z>`. Nothing is applied here.
"""
from pathlib import Path
import argparse
import csv
import glob
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy.sparse import coo_matrix  # noqa: E402
from scipy.sparse.csgraph import connected_components  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402
from shapely.geometry import Point, Polygon, box  # noqa: E402
from shapely.ops import unary_union  # noqa: E402
from shapely.strtree import STRtree  # noqa: E402
from shapely import make_valid, union_all  # noqa: E402
import source_slice_plan_builder as B  # noqa: E402
from source_slice_roofs import roof_triangles, roof_plate, roofs_in, solid, polygons, slice_at, main_roof  # noqa: E402

WELD = 0.1               # studs: vertices this close belong to one surface
MIN_TRIANGLES = 6        # below this a component is a fragment, not a building
STACK_SHARE = 0.3        # plan overlap (of the smaller) that means "stacked, merge"
LIVE_COVER_MAX = 0.2     # a building already this covered by live buildings is skipped
LIVE_CLEARANCE = 0.5     # studs kept between an orphan's plates and a live building
# Shibuya Sky (Building1) is furnished and hand-made; never plan over it.
PROTECTED = [(-630.0, 48.0, 260.0)]
# Level curves: every floor is the building's filled slice at its height, with
# roof seams up to 2*SEAM closed. PARCO's tower floors were two plates 3.28
# studs apart and its podium up to seven pieces; the map owner asked for PARCO
# to be filled within its perimeter at each section, so it gets a wider close.
SEAM = 3.0
SEAM_OVERRIDES = [((705.0, 1720.0), 8.0, "Shibuya PARCO")]


def world_levels(plan):
    o = plan["origin"]
    c, s = math.cos(o.get("yaw", 0.0)), math.sin(o.get("yaw", 0.0))
    for lv in plan["levels"]:
        yield unary_union([Polygon([(o["x"] + c * a + s * b, o["z"] - s * a + c * b)
                                    for a, b in pc]).buffer(0) for pc in lv["pieces"]])


def live_plans():
    """Every plan that is in the map now: sector runs, sweep chunks, rebuilds."""
    plans = {}
    dropped = {"fbx_6_705_2489_-10277"}          # refused twice on the gate, never applied
    for path in glob.glob(str(DATA / "plans_sector*" / "*.json")) + glob.glob(str(DATA / "plans_test" / "*.json")):
        plan = json.loads(Path(path).read_text())
        if plan["id"] not in dropped:
            plans[plan["id"]] = plan
    for path in sorted(glob.glob(str(DATA / "sweep" / "chunks" / "chunk_*.json"))) + \
            sorted(glob.glob(str(DATA / "sweep" / "chunks" / "rebuild_*.json"))):
        for plan in json.loads(Path(path).read_text())["plans"]:
            plans[plan["id"]] = plan
    return plans


def footprint_of(tris):
    """Plan footprint: the union of the ROOF faces, projected.

    Ground faces are excluded. PLATEAU's ground surface can be drawn wider than
    the building and run under its neighbours; with it in, the "stacked" merge
    below joined PARCO to neighbours the map already covers, and the whole group
    was skipped as already built."""
    faces = roof_triangles(tris)
    if len(faces):
        base = tris[:, :, 1].min()
        raised = faces[faces[:, :, 1].min(axis=1) > base + 1.0]
        if len(raised):
            faces = raised
    parts = [Polygon(t[:, [0, 2]]) for t in faces]
    parts = [p.buffer(0.05, join_style=2) for p in parts if p.area > 1e-6]
    if not parts:
        return None
    polys = polygons(make_valid(union_all(parts, grid_size=0.01)))
    return union_all(polys, grid_size=0.01) if polys else None


def outline_of(tris):
    """A building's OUTLINE for identity: roof faces PLUS its wall lines, gaps
    closed, holes filled.

    Roofs alone are not enough. PARCO's tower top is its own mesh component --
    roof only, no walls welded to it -- while PARCO's main component carries
    the walls rising around that tower but not its roof. Roof-only outlines
    never overlapped, so the tower was never merged and came out 5,429 sq studs
    instead of ~36,000. The walls trace the tower, so with them the roof-only
    piece sits inside the outline of the building it belongs to. Side-by-side
    neighbours only share the strip along their common wall."""
    from shapely.geometry import LineString
    n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    ny = np.abs(n[:, 1]) / np.maximum(np.linalg.norm(n, axis=1), 1e-12)
    parts = []
    roof = footprint_of(tris)
    if roof is not None:
        parts.append(roof)
    for t in tris[ny < 0.3]:
        pts = np.unique(np.round(t[:, [0, 2]], 2), axis=0)
        if len(pts) >= 2:
            parts.append(LineString(pts[np.argsort(pts[:, 0] + pts[:, 1])]).buffer(0.75, cap_style=2))
    if not parts:
        return None
    merged = polygons(make_valid(union_all(parts, grid_size=0.01)))
    if not merged:
        return None
    closed = union_all(merged, grid_size=0.01).buffer(2.0, join_style=2).buffer(-2.0, join_style=2)
    return solid(closed)


def areal(geometry):
    """Polygonal parts only, unioned; None if there are none."""
    parts = polygons(geometry)
    return union_all(parts, grid_size=0.01) if parts else None


def components(triangles):
    pts = triangles.reshape(-1, 3)
    pairs = cKDTree(pts).query_pairs(WELD, output_type="ndarray")
    tri = np.repeat(np.arange(len(triangles)), 3)
    graph = coo_matrix((np.ones(len(pairs)), (tri[pairs[:, 0]], tri[pairs[:, 1]])),
                       shape=(len(triangles), len(triangles)))
    return connected_components(graph, directed=False)[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(DATA / "orphans"))
    args = parser.parse_args()

    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    labels = components(triangles)
    order = np.argsort(labels, kind="stable")
    bounds = np.flatnonzero(np.diff(labels[order])) + 1
    groups = [g for g in np.split(order, bounds) if len(g) >= MIN_TRIANGLES]
    print(f"{labels.max() + 1} mesh components, {len(groups)} with >= {MIN_TRIANGLES} triangles", flush=True)

    comps = []
    for idx in groups:
        tris = triangles[idx]
        fp = footprint_of(tris)
        if fp is None or fp.area < 40:
            continue
        # `filled` is for the STACKED test only: a podium's roof is a RING with a
        # hole where its tower rises, so podium and tower roofs never overlap in
        # plan and PARCO's tower was never merged onto its podium (2 levels
        # instead of 23). Holes filled, the ring covers the tower; neighbours
        # standing side by side still do not overlap.
        comps.append(dict(idx=idx, fp=fp, filled=outline_of(tris) or solid(fp)))
    print(f"{len(comps)} components have a roof or ground face", flush=True)

    # Merge components stacked on each other in plan (union-find).
    parent = list(range(len(comps)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    tree = STRtree([c["filled"] for c in comps])
    for i, c in enumerate(comps):
        for j in tree.query(c["filled"]):
            if j <= i:
                continue
            shared = c["filled"].intersection(comps[j]["filled"], grid_size=0.01).area
            if shared >= STACK_SHARE * min(c["filled"].area, comps[j]["filled"].area):
                parent[find(i)] = find(j)
    buildings = {}
    for i in range(len(comps)):
        buildings.setdefault(find(i), []).append(i)
    print(f"{len(buildings)} buildings after merging stacked components", flush=True)

    live = live_plans()
    live_fp = [f for f in (unary_union(list(world_levels(p))) for p in live.values()) if not f.is_empty]
    live_tree = STRtree(live_fp)

    greys = {}
    with open(DATA / "live_extents.csv", newline="") as fh:
        for row in csv.DictReader(fh):
            greys["BuildingSmooth_" + row["n"]] = box(float(row["x0"]), float(row["z0"]),
                                                      float(row["x1"]), float(row["z1"]))
    claimed = {n.strip() for n in (DATA / "applied_greys.txt").read_text().splitlines() if n.strip()}
    for plan in live.values():
        claimed.update(plan.get("sourceInfo", {}).get("replaces", []))
    open_greys = {n: g for n, g in greys.items() if n not in claimed}
    grey_names = list(open_greys)
    grey_tree = STRtree([open_greys[n] for n in grey_names])

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for stale in out.glob("*.json"):
        stale.unlink()
    made, skipped, absorbed = 0, {}, set()
    tri_lo = triangles[:, :, [0, 2]].min(axis=1)
    tri_hi = triangles[:, :, [0, 2]].max(axis=1)

    def skip(why):
        skipped[why] = skipped.get(why, 0) + 1

    # Largest first, and each later building keeps clear of those already
    # planned exactly as it keeps clear of live ones: an outline can reach over
    # a neighbour's roof, and 23 pairs overlapped (worst 2,728 sq studs).
    planned_fp = []
    planned_tree = None
    ordered = sorted(buildings.values(),
                     key=lambda m: -sum(comps[i]["fp"].area for i in m))
    for members in ordered:
        idx = np.concatenate([comps[i]["idx"] for i in members])
        fp = union_all([comps[i]["fp"] for i in members], grid_size=0.01)
        if fp.area < B.MIN_FOOTPRINT:
            skip("footprint under 400 sq studs")
            continue
        c = fp.centroid
        if any((c.x - px) ** 2 + (c.y - pz) ** 2 <= pr * pr for px, pz, pr in PROTECTED):
            skip("protected (Shibuya Sky)")
            continue
        near_live = [live_fp[k] for k in live_tree.query(fp)]
        if near_live:
            covered = union_all([fp.intersection(f, grid_size=0.01) for f in near_live], grid_size=0.01)
            if covered.area > LIVE_COVER_MAX * fp.area:
                skip("already covered by a live building")
                continue
        near_planned = [f for f in planned_fp if f.intersects(fp)]
        others = near_live + near_planned
        blocked = union_all([f.buffer(LIVE_CLEARANCE) for f in others], grid_size=0.01) if others else None

        tris = triangles[idx]
        # Every roof face inside the building's outline counts, whichever mesh
        # component it came from, and plates stay inside that outline.
        outline = union_all([comps[i]["filled"] for i in members], grid_size=0.01)
        reach = outline.buffer(1.0)
        bx0, bz0, bx1, bz1 = reach.bounds
        near = (tri_hi[:, 0] >= bx0) & (tri_lo[:, 0] <= bx1) & (tri_hi[:, 1] >= bz0) & (tri_lo[:, 1] <= bz1)
        roofs = roofs_in(triangles[near], reach)
        base = float(tris[:, :, 1].min())
        seam = SEAM
        for (sx, sz), wide, _name in SEAM_OVERRIDES:
            if outline.buffer(5).contains(Point(sx, sz)):
                seam = wide
        plates, y, below = [], base, None
        while True:
            plate = slice_at(roofs, y + B.SLAB + 1.0, reach, seam)
            if plate is None or plate.is_empty:
                break
            biggest = max((g.area for g in polygons(plate)), default=0.0)
            keep = [g for g in polygons(plate) if g.area >= max(100.0, 0.03 * biggest)]
            plate = union_all(keep, grid_size=0.01) if keep else None
            if plate is not None and blocked is not None:
                plate = areal(plate.difference(blocked, grid_size=0.01))
            # Inside the floor beneath: never let a neighbour's taller roof edge
            # stack a floor on top of this building.
            if plate is not None and below is not None:
                plate = areal(plate.intersection(below.buffer(1.5), grid_size=0.01))
            if plate is None:
                break
            plate = solid(plate.buffer(0.75, join_style=2).buffer(-0.75, join_style=2))
            if plate is None or plate.is_empty or plate.area < B.MIN_FOOTPRINT:
                break
            plates.append((y, plate))
            below = plate
            y += B.PITCH
        # TOP SLAB AT THE ROOF: on a fixed storey grid the last slab lands up to
        # a storey below it (median building 20.8 studs short of the FBX).
        if plates:
            last_y, last_plate = plates[-1]
            roof_y = main_roof(roofs, last_plate, last_y + B.SLAB, last_y + B.SLAB + 2 * B.PITCH, reach)
            want = roof_y - B.SLAB
            if want - (last_y + B.SLAB) >= B.MIN_CLEAR:
                top = slice_at(roofs, roof_y - 2.0, reach, seam)
                top = areal(top.intersection(last_plate, grid_size=0.01)) if top is not None else None
                if top is not None and top.area >= B.MIN_FOOTPRINT:
                    plates.append((want, top))
            elif want > last_y + 0.5 and (len(plates) < 2 or want - (plates[-2][0] + B.SLAB) >= B.MIN_CLEAR):
                plates[-1] = (want, last_plate)
        widest = max((p.area for _, p in plates), default=0)
        while len(plates) > 2 and plates[-1][1].area < B.SLIVER_SHARE * widest:
            plates.pop()
        if len(plates) < 2:
            skip("under two storeys")
            continue
        ox, oz, yaw = B.frame_of(plates[0][1].convex_hull)
        levels, overlap = [], None
        for py, plate in plates:
            rings = B.to_local(plate, ox, oz, yaw)
            shape = B._rings_shape(rings) if rings else None
            if shape is None:
                continue
            levels.append(dict(y=round(py - base, 4), thickness=round(B.SLAB, 4),
                               pieces=[[[round(float(a), 3), round(float(b), 3)] for a, b in r] for r in rings]))
            overlap = shape if overlap is None else overlap.intersection(shape)
        if len(levels) < 2 or overlap is None or overlap.is_empty:
            skip("no common core area")
            continue
        core = B.largest_core(overlap)
        if core is None:
            skip("no 4-stud core")
            continue
        hx, hz = min(core[1], 30.0), min(core[2], 30.0)
        foot = plates[0][1]
        replaces = []
        for k in grey_tree.query(foot):
            name = grey_names[k]
            g = open_greys[name]
            if name not in absorbed and g.intersection(foot).area >= 0.5 * g.area:
                replaces.append(name)
        absorbed.update(replaces)
        plan = dict(
            id=f"orph_{foot.centroid.x:.0f}_{foot.centroid.y:.0f}",
            origin=dict(x=round(ox, 4), y=round(base, 4), z=round(oz, 4), yaw=round(yaw, 6)),
            levels=levels,
            core=dict(minX=round(core[3] - hx, 4), minZ=round(core[4] - hz, 4),
                      maxX=round(core[3] + hx, 4), maxZ=round(core[4] + hz, 4)),
            sourceInfo=dict(origin="mesh component + roof envelope", base=round(base, 2),
                            components=len(members), triangles=int(len(idx)),
                            footprintArea=round(foot.area, 1), replaces=sorted(replaces)))
        problems = B.validate(plan)
        if problems:
            skip("contract: " + problems[0].split(":")[0])
            continue
        (out / f"{plan['id']}.json").write_text(json.dumps(plan))
        planned_fp.append(union_all([pl for _, pl in plates], grid_size=0.01))
        made += 1
        if made % 100 == 0:
            print(f"  ... {made} planned", flush=True)
    print(f"\n{made} orphan buildings planned -> {out}; they absorb {len(absorbed)} greys")
    for why, n in sorted(skipped.items(), key=lambda kv: -kv[1]):
        print(f"  skipped {n}: {why}")


if __name__ == "__main__":
    main()
