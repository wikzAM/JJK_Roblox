"""The ground as a triangulated network between buildings -- the street surface.

Buildings standing on the ground (ground_heightfield.grounded) are holes; the
ground is everything between them. The map is covered by ADAPTIVE squares
(MAX_SQUARE down to MIN_SQUARE studs): a square's share of the open ground is
triangulated (constrained Delaunay, building outlines as edges), and the square
is split while those triangles miss the smooth height field by more than TOL
anywhere inside -- flat Shibuya gets big triangles, slopes and bends get small
ones. Heights:
  * a vertex on a building outline takes the lowest ground floor among the
    buildings it touches, so the pavement meets every building flush;
  * any other vertex takes the smooth (thin-plate) height field.
Crack-free: a square whose neighbour along an edge is finer also carries that
neighbour's corners on the shared edge, so both sides have the same vertices.
There is no ground under a building -- its floor 1 is the ground there -- and
outlines are inset INSET studs so the ground always tucks under the slab edge.
(Merging near buildings into blocks was tried and left open slits between them.)

  python tools/ground_tin.py [--tol 0.5] [--count-only]
     -> source_slices/ground/tiles/ground_*.json + index.json
"""
from pathlib import Path
import argparse
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices" / "ground"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
import shapely  # noqa: E402
from shapely import union_all  # noqa: E402
from shapely.geometry import Point, Polygon, box  # noqa: E402
from shapely.strtree import STRtree  # noqa: E402
import ground_heightfield as G  # noqa: E402

SIMPLIFY = 1.0     # studs: outline simplification (4.0 left ground above 17% of floor edges)
INSET = 1.0        # studs the ground reaches under a building's edge (>= SIMPLIFY)
GRID = 0.01        # coordinate precision (shared edges must match exactly)
ON_EDGE = 0.05     # studs: a vertex this close to an outline is on it
TOUCH = 0.6        # studs: a building this close to an outline vertex owns its height
MAX_SQUARE = 512.0
STREET_SIGMA = 32.0  # studs: smoothing of the street surface
PLINTH = 5.2         # studs a pad edge may sit under its floor (slab is 5.36 thick)
CONE = 0.5           # studs of rise per stud of distance allowed above a nearby floor
FACE_DROP = 1.5      # studs the street stays below a building's floor at its face,
                     # so a ground-floor facade is never buried by the ground
BURY = 0.0           # studs a pad edge may sit above its floor. 2.0 showed ground slivers on top of ground-floor slabs
MIN_SQUARE = 64.0
SAMPLES = ((1 / 3, 1 / 3, 1 / 3), (.5, .5, 0), (0, .5, .5), (.5, 0, .5),
           (.25, .25, .5), (.5, .25, .25), (.25, .5, .25))


def polys_of(g):
    if g is None or g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    return [p for p in getattr(g, "geoms", []) if p.geom_type == "Polygon" and p.area > 1e-6]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tol", type=float, default=1.0)
    ap.add_argument("--tile", type=float, default=512.0)
    ap.add_argument("--count-only", action="store_true")
    ap.add_argument("--simplify", type=float, default=SIMPLIFY)
    ap.add_argument("--inset", type=float, default=INSET)
    ap.add_argument("--min-square", type=float, default=128.0)
    ap.add_argument("--street-sigma", type=float, default=STREET_SIGMA)
    args = ap.parse_args()
    assert args.inset >= args.simplify, "the inset must cover the simplification, or edges crack"
    MIN = args.min_square

    d = np.load(DATA / "heights.npz")
    H, hx0, hz0, cell = d["H"], float(d["x0"]), float(d["z0"]), float(d["cell"])
    # The STREET follows a smoothed surface, not each building's exact floor
    # (Cities: Skylines: smooth terrain, flat pads, embankments between): the
    # exact pins folded streets into sharp crests wherever one building stood a
    # few studs above its neighbours.
    from scipy import ndimage
    pinned = d["known"]
    floors = np.where(pinned, H, np.inf)
    H = ndimage.gaussian_filter(H, args.street_sigma / cell, mode="nearest")
    # ...but never above a nearby floor by more than CONE studs per stud of
    # distance: near a building lower than the street, the street eases down to
    # its floor instead of burying its ground floor (17% of ground inside
    # footprints stood above the floor without this).
    U = floors - FACE_DROP
    step, diag = CONE * cell, CONE * cell * 2 ** 0.5
    for _ in range(400):
        p = np.pad(U, 1, mode="edge")
        new = np.minimum.reduce([U, p[:-2, 1:-1] + step, p[2:, 1:-1] + step, p[1:-1, :-2] + step, p[1:-1, 2:] + step,
                                 p[:-2, :-2] + diag, p[:-2, 2:] + diag, p[2:, :-2] + diag, p[2:, 2:] + diag])
        if np.array_equal(new, U):
            break
        U = new
    H = np.minimum(H, U)
    H = np.minimum(ndimage.gaussian_filter(H, 2.0, mode="nearest"), U)

    def field(x, z):
        fi, fj = (x - hx0) / cell, (z - hz0) / cell
        i = min(max(int(fi), 0), H.shape[0] - 2)
        j = min(max(int(fj), 0), H.shape[1] - 2)
        u, v = min(max(fi - i, 0.0), 1.0), min(max(fj - j, 0.0), 1.0)
        return float(H[i, j] * (1 - u) * (1 - v) + H[i + 1, j] * u * (1 - v)
                     + H[i, j + 1] * (1 - u) * v + H[i + 1, j + 1] * u * v)

    buildings, _ = G.grounded(G.pins())
    bpolys = [p for p, _ in buildings]
    bheights = np.array([y for _, y in buildings])
    btree = STRtree(bpolys)
    holes = union_all([p.buffer(0) for p in bpolys], grid_size=GRID)
    holes = shapely.set_precision(holes.simplify(args.simplify).buffer(-args.inset, join_style=2), GRID)
    hole_list = polys_of(holes)
    hole_tree = STRtree(hole_list)
    edges = holes.boundary
    shapely.prepare(edges)
    shapely.prepare(holes)

    cache = {}

    def h(x, z):
        key = (round(x, 2), round(z, 2))
        if key not in cache:
            y = None
            pt = Point(x, z)
            if edges.distance(pt) <= ON_EDGE:
                touching = [k for k in btree.query(pt.buffer(TOUCH)) if bpolys[k].distance(pt) <= TOUCH]
                if touching:
                    # a pad edge: follow the street, but never above the floor
                    # (it would bury floor 1) nor more than PLINTH below it (the
                    # floor slab's side face covers up to its thickness)
                    floor = float(min(bheights[k] for k in touching))
                    y = min(max(field(x, z), floor - PLINTH), floor + BURY)
            cache[key] = field(x, z) if y is None else y
        return cache[key]

    def piece(sx, sz, s, extra=None):
        """The open ground of one square as polygons; `extra` = {edge: [points]}
        inserted on its boundary."""
        corners = [(sx, sz), (sx + s, sz), (sx + s, sz + s), (sx, sz + s)]
        ring = []
        for k in range(4):
            ring.append(corners[k])
            if extra and extra.get(k):
                a = corners[k]
                ring += sorted(extra[k], key=lambda p: abs(p[0] - a[0]) + abs(p[1] - a[1]))
        sq = Polygon(ring)
        hits = [hole_list[k] for k in hole_tree.query(sq)]
        if not hits:
            return [sq]
        return polys_of(shapely.set_precision(sq.difference(union_all(hits, grid_size=GRID), grid_size=GRID), GRID))

    def triangulate(polys):
        out = []
        for poly in polys:
            if poly.area < 0.5:
                continue
            for t in polys_of(shapely.constrained_delaunay_triangles(poly)):
                out.append(list(t.exterior.coords)[:3])
        return out

    def error(tris):
        worst = 0.0
        for (ax, az), (bx, bz), (cx, cz) in tris:
            ha, hb, hc = h(ax, az), h(bx, bz), h(cx, cz)
            for wa, wb, wc in SAMPLES:
                x, z = wa * ax + wb * bx + wc * cx, wa * az + wb * bz + wc * cz
                e = abs(wa * ha + wb * hb + wc * hc - field(x, z))
                if e > worst:
                    worst = e
        return worst

    x0 = math.floor(hx0 / MIN) * MIN + MIN
    z0 = math.floor(hz0 / MIN) * MIN + MIN
    x1 = hx0 + (H.shape[0] - 2) * cell
    z1 = hz0 + (H.shape[1] - 2) * cell
    nx, nz = int(math.ceil((x1 - x0) / MAX_SQUARE)), int(math.ceil((z1 - z0) / MAX_SQUARE))

    # pass 1: leaves by error against the field
    leaves = []
    stack = [(x0 + a * MAX_SQUARE, z0 + b * MAX_SQUARE, MAX_SQUARE) for a in range(nx) for b in range(nz)]
    while stack:
        sx, sz, s = stack.pop()
        polys = piece(sx, sz, s)
        if not polys or s <= MIN or error(triangulate(polys)) <= args.tol:
            leaves.append((sx, sz, s))
        else:
            hs = s / 2
            stack += [(sx, sz, hs), (sx + hs, sz, hs), (sx, sz + hs, hs), (sx + hs, sz + hs, hs)]
    gw, gh = int(nx * MAX_SQUARE / MIN), int(nz * MAX_SQUARE / MIN)
    owner = np.zeros((gw, gh))
    for sx, sz, s in leaves:
        i, j, n = int((sx - x0) / MIN), int((sz - z0) / MIN), int(s / MIN)
        owner[i:i + n, j:j + n] = s

    # pass 2: each leaf carries its finer neighbours' corners on the shared edges
    tris = []
    for sx, sz, s in leaves:
        i, j, n = int((sx - x0) / MIN), int((sz - z0) / MIN), int(s / MIN)
        extra = {0: set(), 1: set(), 2: set(), 3: set()}
        # edge 0: bottom (z = sz, x rising), 1: right (x = sx+s), 2: top (z = sz+s, x falling), 3: left
        for k in range(n):
            for edge, (ci, cj) in ((0, (i + k, j - 1)), (1, (i + n, j + k)), (2, (i + k, j + n)), (3, (i - 1, j + k))):
                if not (0 <= ci < gw and 0 <= cj < gh):
                    continue
                ns = owner[ci, cj]
                if not (0 < ns < s):
                    continue
                if edge in (0, 2):
                    z = sz if edge == 0 else sz + s
                    base = x0 + math.floor((sx + k * MIN - x0) / ns) * ns
                    for x in (base, base + ns):
                        if sx < x < sx + s:
                            extra[edge].add((x, z))
                else:
                    x = sx + s if edge == 1 else sx
                    base = z0 + math.floor((sz + k * MIN - z0) / ns) * ns
                    for z in (base, base + ns):
                        if sz < z < sz + s:
                            extra[edge].add((x, z))
        for t in triangulate(piece(sx, sz, s, {e: list(v) for e, v in extra.items()})):
            tris.append([(x, h(x, z), z) for x, z in t])

    sizes = {}
    for _, _, s in leaves:
        sizes[int(s)] = sizes.get(int(s), 0) + 1
    print(f"tol {args.tol}: {len(leaves)} squares {sorted(sizes.items())}: "
          f"{len(tris)} triangles -> {2 * len(tris)} wedges", flush=True)
    if args.count_only:
        return
    tiles = {}
    for t in tris:
        cx = sum(p[0] for p in t) / 3
        cz = sum(p[2] for p in t) / 3
        key = (int(math.floor(cx / args.tile)), int(math.floor(cz / args.tile)))
        tiles.setdefault(key, []).append([[round(v, 3) for v in p] for p in t])
    out = DATA / "tiles"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.json"):
        f.unlink()
    names = []
    for (tx, tz), ts in sorted(tiles.items()):
        name = f"ground_{tx:+d}_{tz:+d}".replace("+", "p").replace("-", "m")
        (out / f"{name}.json").write_text(json.dumps({"name": name, "triangles": ts}))
        names.append([name, len(ts)])
    (out / "index.json").write_text(json.dumps(names))
    print(f"{len(names)} tiles of {args.tile:.0f} studs, largest {max(n for _, n in names)} triangles -> {out}")


if __name__ == "__main__":
    main()
