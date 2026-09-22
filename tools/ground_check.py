"""Offline ground checks, before anything is built in Studio.

  * EDGE probes (ground/edge_probes.json, 1 stud outside building edges): each
    must lie on a ground triangle; reports the ground-minus-floor offset there.
  * HOLES: a regular sample of the map inside the city; each point must be on
    ground or inside a building footprint.

  python tools/ground_check.py
"""
from pathlib import Path
import glob
import json
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices" / "ground"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from shapely import contains_xy, union_all  # noqa: E402
from shapely.geometry import Polygon  # noqa: E402
from shapely.strtree import STRtree  # noqa: E402
import ground_heightfield as G  # noqa: E402


def main():
    tris = []
    for f in glob.glob(str(DATA / "tiles" / "ground_*.json")):
        tris += json.loads(Path(f).read_text())["triangles"]
    polys = [Polygon([(p[0], p[2]) for p in t]) for t in tris]
    tree = STRtree(polys)

    def ground_y(x, z):
        from shapely.geometry import Point
        pt = Point(x, z)
        for k in tree.query(pt):
            if polys[k].buffer(0.02).contains(pt):
                a, b, c = (np.array(v) for v in tris[k])
                n = np.cross(b - a, c - a)
                if abs(n[1]) < 1e-9:
                    return float(max(a[1], b[1], c[1]))
                return float(a[1] - (n[0] * (x - a[0]) + n[2] * (z - a[2])) / n[1])
        return None

    probes = json.loads((DATA / "edge_probes.json").read_text())
    offs, miss = [], []
    for x, z, y in probes:
        g = ground_y(x, z)
        if g is None:
            miss.append((x, z, y))
        else:
            offs.append(g - y)
    offs = np.array(offs)
    print(f"edge probes {len(probes)}: on ground {len(offs)}, MISSING {len(miss)} {miss[:5]}")
    print(f"  ground - floor: p1 {np.percentile(offs, 1):.2f} p5 {np.percentile(offs, 5):.2f} "
          f"median {np.median(offs):.2f} p95 {np.percentile(offs, 95):.2f} p99 {np.percentile(offs, 99):.2f}")

    allb = union_all([p.buffer(0) for p, _ in G.pins()], grid_size=0.01)
    xs = np.arange(-2600, 2800, 23.0)
    zs = np.arange(-2200, 3000, 23.0)
    X, Z = np.meshgrid(xs, zs)
    inb = contains_xy(allb, X, Z)
    holes = []
    for x, z in zip(X[~inb], Z[~inb]):
        if ground_y(float(x), float(z)) is None:
            holes.append((round(float(x)), round(float(z))))
    print(f"hole sample: {(~inb).sum()} points off buildings, {len(holes)} with no ground {holes[:8]}")


if __name__ == "__main__" and "--cracks" not in sys.argv and "--poke" not in sys.argv:
    main()


def cracks():
    """Every triangle edge must be shared by two triangles unless it lies on a
    building outline or the map border; a lone edge anywhere else is a crack."""
    from collections import Counter
    import shapely
    tris = []
    for f in glob.glob(str(DATA / "tiles" / "ground_*.json")):
        tris += json.loads(Path(f).read_text())["triangles"]
    key = lambda p: (round(p[0], 2), round(p[2], 2))
    edges = Counter()
    for t in tris:
        a, b, c = (key(p) for p in t)
        for e in ((a, b), (b, c), (c, a)):
            edges[tuple(sorted(e))] += 1
    lone = [e for e, n in edges.items() if n == 1]
    xs = [p[0] for e in edges for p in e]
    zs = [p[1] for e in edges for p in e]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    buildings, _ = G.grounded(G.pins())
    allb = union_all([p.buffer(0) for p, _ in buildings], grid_size=0.01)
    shapely.prepare(allb)
    bad = []
    for (p, q) in lone:
        mx, mz = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        on_border = min(abs(mx - x0), abs(mx - x1), abs(mz - z0), abs(mz - z1)) < 0.05
        if on_border:
            continue
        from shapely.geometry import Point
        if allb.contains(Point(mx, mz)):
            continue            # an outline edge, under a building
        bad.append(((round(mx, 1), round(mz, 1)), round(((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2) ** 0.5, 2)))
    print(f"edges {len(edges)}, lone {len(lone)}, lone edges in the OPEN (cracks) {len(bad)} {bad[:8]}")


if __name__ == "__main__" and "--cracks" in sys.argv:
    cracks()


def poke():
    """Ground inside a building's footprint must stay under its floor top."""
    from shapely.geometry import Point
    tris = []
    for f in glob.glob(str(DATA / "tiles" / "ground_*.json")):
        tris += json.loads(Path(f).read_text())["triangles"]
    buildings, _ = G.grounded(G.pins())
    tree = STRtree([p for p, _ in buildings])
    over = []
    samples = 0
    for t in tris:
        a, b, c = (np.array(v) for v in t)
        for w in ((1 / 3, 1 / 3, 1 / 3), (.6, .2, .2), (.2, .6, .2), (.2, .2, .6)):
            p = w[0] * a + w[1] * b + w[2] * c
            pt = Point(p[0], p[2])
            for k in tree.query(pt):
                poly, y = buildings[k]
                if poly.contains(pt):
                    samples += 1
                    if p[1] > y + 0.15:
                        over.append((round(p[1] - y, 2), round(p[0]), round(p[2])))
    over.sort(reverse=True)
    print(f"ground samples inside footprints {samples}, above the floor top {len(over)} "
          f"({len(over) / max(samples, 1):.1%}); worst {over[:6]}")


if __name__ == "__main__" and "--poke" in sys.argv:
    poke()
