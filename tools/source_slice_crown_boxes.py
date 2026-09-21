"""Build a crown as SOLID objects: a box where the FBX is box-like, else a prism.

  python tools/source_slice_crown_boxes.py <plansDir> [outJson]

Why it works per OBJECT, not per slice
--------------------------------------
The first version sliced the crown band every few studs and cut each slice into
rectangles. Two rewrites in, it still produced contour terracing: a mass came out
as a wedding cake of stacked plates, because slicing throws away the fact that a
rooftop is a few discrete THINGS.

So: split the crown mesh into connected components. Each component is one
physical object -- a plant room, an AC unit, a parapet, a lift overrun -- and
each becomes ONE solid spanning its own full height. No stacking, no terracing.

Per component:

  * Bound it in the building's own yaw frame (only 3.2% of vertical crown faces
    are world-axis-aligned, so world axes fit almost nothing).
  * Project it to a footprint and compare that with its own bounding rectangle.
  * fill >= BOX_FILL -> ONE Part. It is a box; say so.
  * otherwise        -> a PRISM: that footprint extruded over the component's
                        height, built by PolygonSlab, which tiles a rectangle as
                        one Part and any other polygon into exact right-triangle
                        wedges. Solid either way, never a hollow shell.

Measured over 123 crowns / 692 connected components: the median component has
ALL its vertices on its own bounding-box surface, and the median footprint fills
0.76 of its bounding rectangle. 23% pass a strict box test, ~51% fill 0.75+.

Do NOT judge boxiness by surface area. The scan only captured the faces it could
see -- median surface area is 0.38 of a closed box -- so an area test rejects
boxes that are merely missing their underside. Filling those in is the point.
"""
from pathlib import Path
from collections import defaultdict
import glob
import json
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline as pipe  # noqa: E402,F401  (fixes the deps path)
import numpy as np  # noqa: E402
import shapely  # noqa: E402
from shapely.geometry import Polygon  # noqa: E402
from shapely.ops import unary_union  # noqa: E402

DATA = ROOT / "source_slices"
DEFAULT_OUT = ROOT.parent / "src" / "server" / "SourceSliceCrownBoxes.json"

OUTLINE_PAD = 14.0     # studs of slack around the top plate
CROWN_HEADROOM = 10.0  # studs a crown may stand above its building's own top
MAX_CROWN = 140.0      # backstop when a plan records no top of its own
WELD = 0.35            # studs; vertices this close join the same component
BOX_FILL = 0.85        # footprint/bounding-rectangle above this is "a box"
CLOSE = 1.2            # studs; closes the seams between a component's faces
SIMPLIFY = 1.5         # studs; prism outline tolerance
MIN_SIDE = 3.0         # studs; a solid thinner than this is not worth a part
MIN_AREA = 25.0        # sq studs of footprint
MAX_VERTS = 24         # PolygonSlab cost climbs with vertices; simplify harder
SEG_MIN = 10.0         # studs; shorter objects are one solid, never segmented
SEG_STEP = 4.0         # studs between cuts when an object IS segmented
SEG_IOU = 0.80         # consecutive cuts this alike belong to the same segment


def band_for(plan, triangles, lo, hi):
    """This building's crown triangles, clipped to its own top."""
    o, levels = plan["origin"], plan["levels"]
    last = levels[-1]
    crown_from = o["y"] + last["y"] + last["thickness"]
    cos, sin = np.cos(o["yaw"]), np.sin(o["yaw"])
    rings = [[(o["x"] + cos * a + sin * b, o["z"] - sin * a + cos * b) for a, b in piece]
             for piece in last["pieces"]]
    top_shape = unary_union([Polygon(r).buffer(0) for r in rings]).buffer(OUTLINE_PAD)
    minx, minz, maxx, maxz = top_shape.bounds

    info = plan.get("sourceInfo", {})
    own_top = max(float(info.get("fbxTop", 0.0)), float(info.get("greyTop", 0.0)))
    ceiling = own_top + CROWN_HEADROOM if own_top > crown_from else crown_from + MAX_CROWN

    near = ((hi[:, 1] >= crown_from) & (lo[:, 1] <= ceiling)
            & (hi[:, 0] >= minx) & (lo[:, 0] <= maxx)
            & (hi[:, 2] >= minz) & (lo[:, 2] <= maxz))
    band = triangles[near]
    if len(band) == 0:
        return None, crown_from, crown_from
    centroids = band.mean(axis=1)
    band = band[shapely.contains_xy(top_shape, centroids[:, 0], centroids[:, 2])]
    if len(band) == 0:
        return None, crown_from, crown_from
    crown_to = min(float(band[:, :, 1].max()), ceiling)
    band = clip_band(band, crown_from, crown_to)
    if len(band) == 0:
        return None, crown_from, crown_from
    return band, crown_from, crown_to


def _clip_half(poly, y, keep_above):
    out = []
    n = len(poly)
    for i in range(n):
        cur, nxt = poly[i], poly[(i + 1) % n]
        cin = (cur[1] >= y) if keep_above else (cur[1] <= y)
        nin = (nxt[1] >= y) if keep_above else (nxt[1] <= y)
        if cin:
            out.append(cur)
        if cin != nin:
            span = nxt[1] - cur[1]
            if abs(span) > 1e-12:
                out.append(cur + (nxt - cur) * ((y - cur[1]) / span))
    return out


def clip_band(tris, y0, y1):
    """Cut triangles to a height window.

    Without this a single wall triangle running the height of the tower stays
    whole, and the component it belongs to reports a 443-stud extent for a
    72-stud crown -- which wrecks its height, its footprint and its segmentation.
    """
    kept = []
    for tri in tris:
        poly = _clip_half([tri[0], tri[1], tri[2]], y0, True)
        if len(poly) < 3:
            continue
        poly = _clip_half(poly, y1, False)
        if len(poly) < 3:
            continue
        for i in range(1, len(poly) - 1):
            fan = np.array([poly[0], poly[i], poly[i + 1]])
            if np.linalg.norm(np.cross(fan[1] - fan[0], fan[2] - fan[0])) / 2 >= 0.25:
                kept.append(fan)
    return np.array(kept) if kept else np.empty((0, 3, 3))


def components(tris):
    """Connected components of the soup. One component is one physical object."""
    key, parent = {}, []

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    faces = []
    for tri in tris:
        idx = []
        for point in tri:
            k = tuple(np.round(np.asarray(point, float) / WELD).astype(int))
            if k not in key:
                key[k] = len(parent)
                parent.append(len(parent))
            idx.append(key[k])
        faces.append(idx)
        union(idx[0], idx[1])
        union(idx[1], idx[2])
    groups = defaultdict(list)
    for face, tri in zip(faces, tris):
        groups[find(face[0])].append(tri)
    return list(groups.values())


def footprint(local):
    """Solid XZ outline of one component, with its face seams closed."""
    pieces = []
    for tri in local:
        poly = Polygon(tri[:, [0, 2]])
        if poly.is_valid and poly.area > 0.05:
            pieces.append(poly)
    if not pieces:
        return None
    # A vertical face projects to a line and adds no area, so close the seams
    # between the faces the scan did capture, then shrink back.
    shape = unary_union(pieces).buffer(CLOSE, join_style=2).buffer(-CLOSE, join_style=2)
    if shape.is_empty:
        return None
    if shape.geom_type == "MultiPolygon":
        shape = max(shape.geoms, key=lambda g: g.area)
    # FILL THE INTERIOR. These are hollow shells, so a thin height window cuts a
    # RING of wall, not a solid cross section. Left as a ring, two consecutive
    # windows of a tapering tower share almost no area, no two windows ever
    # merge, and every 4-stud window becomes its own slab -- which is exactly
    # the contour terracing this rewrite exists to kill.
    shape = Polygon(shape.exterior)
    return shape if shape.is_valid and shape.area >= MIN_AREA else None


def outline(shape):
    """Simple CCW ring for PolygonSlab, simplified until it is cheap enough."""
    for tol in (SIMPLIFY, SIMPLIFY * 2, SIMPLIFY * 4, SIMPLIFY * 8):
        simple = shape.simplify(tol)
        if simple.is_empty or simple.geom_type != "Polygon":
            continue
        points = list(simple.exterior.coords)[:-1]
        if len(points) < 3 or len(points) > MAX_VERTS:
            continue
        poly = Polygon(points)
        if not poly.is_valid or poly.area < MIN_AREA:
            continue
        return points if poly.exterior.is_ccw else points[::-1]
    return None


def segments(local, y0, y1):
    """Split ONE object by height, but only where its shape actually changes.

    A single extrusion is right for an AC unit and wrong for a stepped crown --
    Cerulean's crown is one connected component 72 studs tall and comes out a
    featureless block. Slicing everything instead is what produced the contour
    terracing. So cut the object into windows, and merge consecutive windows
    whose footprints agree: terraces survive, terracing does not.

    Footprints come from PROJECTING a clipped window, not from
    source_slice_pipeline.sections(). These components are open shells -- the
    scan never saw their undersides -- and sections() polygonises closed
    outlines, so it returned zero polygons on every cut of every component.
    """
    if y1 - y0 < SEG_MIN:
        shape = footprint(local)
        return [(y0, y1, shape)] if shape is not None else []

    windows = []
    y = y0
    while y < y1 - 1e-6:
        top = min(y + SEG_STEP, y1)
        piece = clip_band(local, y, top)
        windows.append((y, top, footprint(piece) if len(piece) else None))
        y = top

    groups, cur = [], []
    for bottom, top, shape in windows:
        if shape is None:
            continue
        if cur:
            prev = cur[-1][2]
            union = prev.union(shape).area
            if union <= 0 or prev.intersection(shape).area / union < SEG_IOU:
                groups.append(cur)
                cur = []
        cur.append((bottom, top, shape))
    if cur:
        groups.append(cur)
    if not groups:
        shape = footprint(local)
        return [(y0, y1, shape)] if shape is not None else []

    out = []
    for index, group in enumerate(groups):
        bottom = y0 if index == 0 else group[0][0]
        top = y1 if index == len(groups) - 1 else group[-1][1]
        if top - bottom < MIN_SIDE:
            continue
        shape = unary_union([g[2] for g in group])
        if shape.geom_type == "MultiPolygon":
            shape = max(shape.geoms, key=lambda g: g.area)
        if shape.area >= MIN_AREA:
            out.append((bottom, top, shape))
    return out


def solids_for(plan, triangles, lo, hi):
    band, y0, y1 = band_for(plan, triangles, lo, hi)
    if band is None or y1 - y0 < MIN_SIDE:
        return [], [], (y0, y1, 0)

    o = plan["origin"]
    cos, sin = np.cos(-o["yaw"]), np.sin(-o["yaw"])
    boxes, prisms, skipped = [], [], 0
    for comp in components(band):
        tris = np.array(comp, float)
        dx, dz = tris[:, :, 0] - o["x"], tris[:, :, 2] - o["z"]
        local = np.stack([cos * dx + sin * dz, tris[:, :, 1], -sin * dx + cos * dz], axis=2)
        flat = local.reshape(-1, 3)
        lo3, hi3 = flat.min(axis=0), flat.max(axis=0)
        height = float(hi3[1] - lo3[1])
        if height < MIN_SIDE:
            skipped += 1
            continue
        pieces = segments(local, float(lo3[1]), float(hi3[1]))
        if not pieces:
            skipped += 1
            continue
        for bottom, top, shape in pieces:
            bx0, bz0, bx1, bz1 = shape.bounds
            sx, sz = bx1 - bx0, bz1 - bz0
            fill = shape.area / max(sx * sz, 1e-9)
            if fill >= BOX_FILL and sx >= MIN_SIDE and sz >= MIN_SIDE:
                boxes.append({"x": round((bx0 + bx1) / 2, 3),
                              "y": round((bottom + top) / 2, 3),
                              "z": round((bz0 + bz1) / 2, 3),
                              "sx": round(sx, 3), "sy": round(top - bottom, 3),
                              "sz": round(sz, 3)})
                continue
            ring = outline(shape)
            if ring is None:
                skipped += 1
                continue
            prisms.append({"y": round(bottom, 3), "h": round(top - bottom, 3),
                           "points": [[round(float(a), 3), round(float(b), 3)] for a, b in ring]})
    return boxes, prisms, (y0, y1, skipped)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    plans_dir = Path(args[0]) if args else DATA / "plans_sector2"
    out_path = Path(args[1]) if len(args) > 1 else DEFAULT_OUT

    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    lo, hi = triangles.min(axis=1), triangles.max(axis=1)

    payload, report = {}, []
    for path in sorted(glob.glob(str(plans_dir / "*.json"))):
        plan = json.load(open(path))
        boxes, prisms, (y0, y1, skipped) = solids_for(plan, triangles, lo, hi)
        if not boxes and not prisms:
            report.append((plan["id"], 0, 0, skipped, 0.0))
            continue
        payload[plan["id"]] = {"yaw": round(plan["origin"]["yaw"], 6),
                               "ox": round(plan["origin"]["x"], 3),
                               "oz": round(plan["origin"]["z"], 3),
                               "boxes": boxes, "prisms": prisms}
        report.append((plan["id"], len(boxes), len(prisms), skipped, y1 - y0))

    out_path.write_text(json.dumps(payload))
    print(f"{len(payload)} crowns -> {out_path}\n")
    print(f"{'plan':30s} {'boxes':>6} {'prisms':>7} {'skipped':>8} {'bandH':>7}")
    for pid, b, p, s, h in sorted(report, key=lambda r: -(r[1] + r[2])):
        print(f"{pid:30s} {b:6d} {p:7d} {s:8d} {h:7.1f}")
    tb, tp = sum(r[1] for r in report), sum(r[2] for r in report)
    print(f"\n{tb} boxes + {tp} prisms over {len(payload)} crowns")
    print(f"box share of solids: {tb / max(tb + tp, 1):.0%}; "
          f"skipped components: {sum(r[3] for r in report)}")


if __name__ == "__main__":
    main()
