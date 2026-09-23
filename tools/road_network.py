"""The road network: centrelines and widths of the space between buildings.

The ground height field already knows which cells are building and which are
open. Thinning that open space to one-cell-wide lines gives the street
centrelines; the distance transform at each point gives how wide the street is
there. Junctions are where three or more lines meet.

Output (source_slices/ground/roads.json):
  runs:      [{pts: [[x, z], ...], width: studs, class: "arterial"|"street"|"alley"}]
  junctions: [{x, z, r}]

  python tools/road_network.py [--preview]
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices" / "ground"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402

MIN_WIDTH = 10.0     # studs: thinner gaps are not streets, they are slots between buildings
SIMPLIFY = 4.0       # studs: polyline simplification
SPUR = 60.0          # studs: dead-end branches shorter than this are thinning artefacts
CLASSES = ((60.0, "arterial"), (24.0, "street"), (0.0, "alley"))


def thin(mask):
    """Zhang-Suen thinning to one-cell-wide lines (skimage is not installed)."""
    img = mask.astype(np.uint8).copy()
    while True:
        changed = False
        for step in (0, 1):
            p = np.pad(img, 1)
            n = [p[:-2, 1:-1], p[:-2, 2:], p[1:-1, 2:], p[2:, 2:],
                 p[2:, 1:-1], p[2:, :-2], p[1:-1, :-2], p[:-2, :-2]]   # P2..P9 clockwise
            b = sum(n)
            trans = sum(((n[i] == 0) & (n[(i + 1) % 8] == 1)).astype(np.uint8) for i in range(8))
            if step == 0:
                cond = (n[0] * n[2] * n[4] == 0) & (n[2] * n[4] * n[6] == 0)
            else:
                cond = (n[0] * n[2] * n[6] == 0) & (n[0] * n[4] * n[6] == 0)
            kill = (img == 1) & (b >= 2) & (b <= 6) & (trans == 1) & cond
            if kill.any():
                img[kill] = 0
                changed = True
        if not changed:
            return img.astype(bool)


def trace(skel):
    """Skeleton -> polylines between endpoints/junctions, in cell coordinates."""
    # Branch count = the CROSSING NUMBER (0->1 transitions around the 8-ring),
    # not the neighbour count: an 8-connected line steps diagonally, so a plain
    # neighbour count makes nearly every cell look like a junction (27k "nodes"
    # out of 72k skeleton cells).
    p = np.pad(skel.astype(np.uint8), 1)
    ring = [p[:-2, 1:-1], p[:-2, 2:], p[1:-1, 2:], p[2:, 2:],
            p[2:, 1:-1], p[2:, :-2], p[1:-1, :-2], p[:-2, :-2]]
    cn = sum(((ring[i] == 0) & (ring[(i + 1) % 8] == 1)).astype(np.uint8) for i in range(8))
    nodes = skel & (cn != 2)
    visited = set()
    runs = []
    idx = {(i, j) for i, j in zip(*np.nonzero(skel))}

    def neighbours(c):
        i, j = c
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                if (di or dj) and (i + di, j + dj) in idx:
                    yield (i + di, j + dj)

    # a junction is a CLUSTER of adjacent node cells; treat it as one node, or
    # every cell of it looks like a dead end and pruning eats the network
    clusters, _ = ndimage.label(nodes, structure=np.ones((3, 3)))
    starts = [tuple(c) for c in zip(*np.nonzero(nodes))]
    for s in starts:
        for nb in neighbours(s):
            if (s, nb) in visited:
                continue
            path, prev, cur = [s], s, nb
            while True:
                visited.add((prev, cur))
                visited.add((cur, prev))
                path.append(cur)
                if nodes[cur]:
                    break
                nxt = [c for c in neighbours(cur) if c != prev]
                if len(nxt) != 1:
                    break
                prev, cur = cur, nxt[0]
            if len(path) > 1:
                runs.append(path)
    return runs, starts, clusters


def simplify(pts, tol):
    """Douglas-Peucker."""
    if len(pts) < 3:
        return pts
    a, b = np.array(pts[0]), np.array(pts[-1])
    ab = b - a
    n = np.linalg.norm(ab)
    arr = np.array(pts)
    if n < 1e-9:
        d = np.linalg.norm(arr - a, axis=1)
    else:
        rel = arr - a
        d = np.abs(ab[0] * rel[:, 1] - ab[1] * rel[:, 0]) / n
    k = int(np.argmax(d))
    if d[k] <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[:k + 1], tol)[:-1] + simplify(pts[k:], tol)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true")
    args = ap.parse_args()
    d = np.load(DATA / "heights.npz")
    known, x0, z0, cell = d["known"], float(d["x0"]), float(d["z0"]), float(d["cell"])
    free = ~known
    dist = ndimage.distance_transform_edt(free) * cell
    # streets: open space at least MIN_WIDTH wide, and inside the city (not the outskirts)
    wide = free & (dist >= MIN_WIDTH / 2)
    city = ndimage.binary_dilation(known, iterations=int(200 / cell))
    street = wide & city
    street = ndimage.binary_closing(street, np.ones((3, 3)))
    lab, n = ndimage.label(street)
    if n:
        sizes = ndimage.sum(street, lab, range(1, n + 1))
        street = lab == (1 + int(np.argmax(sizes)))     # the connected street network
    print(f"street cells {street.sum()} ({street.sum() * cell * cell / 1e6:.1f}M sq studs)", flush=True)
    skel = thin(street)
    print(f"skeleton cells {skel.sum()}", flush=True)
    runs, nodes, clusters = trace(skel)
    print(f"{len(runs)} raw runs, {len(nodes)} node cells, {clusters.max()} junctions", flush=True)
    # Pruning was tried and is a trap: removing dead-end runs cascades and
    # leaves stubs instead of a network (97k studs of centreline against 378k).
    # Short runs are simply skipped when the parts are emitted.

    out_runs = []
    for path in runs:
        pts = [(x0 + i * cell, z0 + j * cell) for i, j in path]
        w = float(np.median([2 * dist[i, j] for i, j in path]))
        if len(pts) * cell < 24 and w < 24:
            continue
        simple = simplify(pts, SIMPLIFY)
        cls = next(name for lim, name in CLASSES if w >= lim)
        out_runs.append({"pts": [[round(x, 1), round(z, 1)] for x, z in simple],
                         "width": round(min(w, 120.0), 1), "class": cls})
    seen, junctions = set(), []
    for i, j in nodes:
        c = int(clusters[i, j])
        if c in seen or dist[i, j] < MIN_WIDTH / 2:
            continue
        seen.add(c)
        junctions.append({"x": round(x0 + i * cell, 1), "z": round(z0 + j * cell, 1),
                          "r": round(float(dist[i, j]), 1)})
    total = sum(sum(float(np.hypot(*(np.array(r["pts"][k + 1]) - np.array(r["pts"][k]))))
                    for k in range(len(r["pts"]) - 1)) for r in out_runs)
    by = {}
    for r in out_runs:
        by[r["class"]] = by.get(r["class"], 0) + 1
    (DATA / "roads.json").write_text(json.dumps({"runs": out_runs, "junctions": junctions}))
    print(f"{len(out_runs)} runs {by}, {len(junctions)} junctions, {total:,.0f} studs of centreline "
          f"-> {DATA / 'roads.json'}")
    if args.preview:
        import ground_preview as P
        img = np.zeros((known.shape[0], known.shape[1], 3))
        img[known] = [0.25, 0.25, 0.28]
        img[free] = [0.55, 0.55, 0.5]
        img[street] = [0.42, 0.42, 0.45]
        img[skel] = [1.0, 0.85, 0.2]
        P.write_png(str(DATA / "roads.png"), (np.clip(img, 0, 1) * 255).astype(np.uint8).transpose(1, 0, 2))
        print(f"-> {DATA / 'roads.png'}")


if __name__ == "__main__":
    main()
