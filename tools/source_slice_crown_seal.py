"""Seal a crown triangle soup into a watertight shell.

The Shibuya FBX is photogrammetry/drone-derived, so it is NOT watertight. Across
the 25 sector crowns the raw soup carries 1,770 crack edges -- edges with only
one triangle on them that are not a legitimate open rim. 82% of them sit within
3 studs of another crack edge, i.e. they are the two sides of a slit, not a
surface that merely ends. Rendered as a thin wedge shell those slits show up as
the dark vertical slots you can see through.

Welding does not help: at a 0.25-stud tolerance the Cerulean crown goes from 131
to 130 vertices. The vertices are already shared -- the faces are simply absent.
So the repair has to add geometry, not merge it.

What this does, in order:

  1. Drop slivers TriangleShell would refuse anyway (under the 0.05 stud minimum
     on any side or altitude). Doing it here rather than at build time means the
     hole they leave gets filled by step 4 instead of silently staying open.
  2. Weld near-coincident vertices so boundary edges actually pair up.
  3. Walk the boundary into closed loops. Orientation in the soup is not
     trustworthy, so loops are chained undirected, picking the straightest
     continuation at each vertex.
  4. Fill every loop except the ones we want open, by minimum-area triangulation
     (the standard O(n^3) DP). A slit loop runs up one side and back down the
     other, so filling the loop IS zipping the slit -- no pairwise edge matching
     and no gores at the ends.
  5. Dilate each triangle slightly in its own plane. A shell of thickness t
     centred on the surface leaves a V notch of depth ~t/2*tan(a/2) on the
     outside of every convex fold; the dilation laps over the neighbour instead.

Loops deliberately left open:
  * the bottom rim, where the crown was cut off the floors below and is buried;
  * a flat loop at the very top, which is a genuinely open roof in the FBX (the
    Cerulean helipad) and which the map owner wants to model by hand.
Pass cap_top=True to fill those too.
"""
from collections import defaultdict
import numpy as np

WELD = 0.25        # studs; vertices this close are the same vertex
MIN_SIZE = 0.05    # TriangleShell's floor -- keep the two in step
RIM_TOL = 1.0      # studs; how flat a loop must be to count as a rim
MAX_LOOP = 240     # verts; beyond this the DP is not worth it, fan instead
PAD = 0.35         # studs of in-plane growth, >= half the shell thickness
MAX_PAD_STEP = 1.0  # studs; hard ceiling on how far dilation may move a corner
MAX_BRIDGE = 12.0  # studs; how far apart a broken walk's ends may be to join
MAX_FILL_SHARE = 1.0  # of the crown's own surface area, per loop
MAX_GAP = 16.0     # studs; how wide a fill triangle may be. A crack is narrow
                   # by definition, so a WIDE fill triangle is not closing one --
                   # it is a membrane thrown across open sky. Uncapped, this put
                   # a 0.6 x 92 x 90 stud sail on one building and took another's
                   # largest triangle from 2,450 to 22,380 sq studs.
                   #
                   # 16 is the measured knee, not a guess. Sweeping the cap over
                   # 123 crowns (10,910 raw triangles, raw largest 4,074):
                   #     cap    4    8   12   16   24   40  none
                   #   closed  18%  39%  54%  65%  75%  81%  83%
                   #   wedges 26k  30k  32k  33k  34k  35k   35k
                   #   maxTri 4180 4180 4180 4180 4180 4180 26444
                   #   >2000    29   29   29   29   34   45    95
                   # At any cap up to 16 the seal adds NOTHING bigger than the
                   # FBX already had. 16 is the largest such cap, so it buys the
                   # most closure for no new large geometry.
PASSES = 4         # seal passes; each one mops up what the last could not close


def _norm(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def buildable(a, b, c):
    """Replica of TriangleShell.wedgesFor's accept test. Keep the two in step."""
    d = [(b - a) @ (b - a), (c - a) @ (c - a), (c - b) @ (c - b)]
    if d[0] > d[1] and d[0] > d[2]:
        a, c = c, a
    elif d[1] > d[2] and d[1] > d[0]:
        a, b = b, a
    ab, ac, bc = b - a, c - a, c - b
    normal = np.cross(ac, ab)
    if np.linalg.norm(normal) < 1e-6:
        return False
    along = np.linalg.norm(bc)
    if along < MIN_SIZE:
        return False
    back = bc / along
    up = np.cross(back, normal / np.linalg.norm(normal))
    if np.linalg.norm(up) < 1e-6:
        return False
    up = _norm(up)
    return not (abs(ab @ up) < MIN_SIZE or abs(ab @ back) < MIN_SIZE
                or abs(ac @ back) < MIN_SIZE)


def weld(tris, tol):
    """-> vertex array, face index list. Faces that collapse are dropped."""
    key, pos, faces = {}, [], []
    for tri in tris:
        idx = []
        for p in tri:
            k = tuple(np.round(np.asarray(p, float) / tol).astype(int))
            if k not in key:
                key[k] = len(pos)
                pos.append(np.asarray(p, float))
            idx.append(key[k])
        if len(set(idx)) == 3:
            faces.append(idx)
    return np.array(pos), faces


def boundary_loops(verts, faces):
    """Closed chains of edges carrying exactly one face.

    Chained undirected: a photogrammetry soup has inconsistent winding often
    enough that following half-edge direction drops whole loops on the floor.
    """
    use = defaultdict(int)
    for f in faces:
        for a, b in ((f[0], f[1]), (f[1], f[2]), (f[2], f[0])):
            use[(min(a, b), max(a, b))] += 1
    adj = defaultdict(list)
    for (a, b), count in use.items():
        if count == 1:
            adj[a].append(b)
            adj[b].append(a)

    loops, spent = [], set()
    for seed in list(adj):
        for first in adj[seed]:
            if (min(seed, first), max(seed, first)) in spent:
                continue
            spent.add((min(seed, first), max(seed, first)))
            loop, prev, cur = [seed], seed, first
            while True:
                loop.append(cur)
                if cur == seed:
                    break
                heading = _norm(verts[cur] - verts[prev])
                best, best_dot = None, -2.0
                for nxt in adj[cur]:
                    e = (min(cur, nxt), max(cur, nxt))
                    if e in spent or nxt == prev:
                        continue
                    dot = float(heading @ _norm(verts[nxt] - verts[cur]))
                    if dot > best_dot:
                        best, best_dot = nxt, dot
                if best is None:
                    break
                spent.add((min(cur, best), max(cur, best)))
                prev, cur = cur, best
            if len(loop) < 4:
                continue
            if loop[0] == loop[-1]:
                loops.append(loop[:-1])
            elif np.linalg.norm(verts[loop[0]] - verts[loop[-1]]) <= MAX_BRIDGE:
                # A walk can dead-end at a vertex where three boundary edges
                # meet. Joining the two loose ends is right as long as they are
                # near each other -- that is one slit, walked from inside out.
                loops.append(loop)
    return loops


def fill_loop(verts, loop):
    """Minimum-area triangulation of a closed 3D loop (the Barequet/Liepa DP).

    A slit's boundary runs up one side and back down the other, so the minimum
    area surface spanning it is the zipper across the slit -- exactly the
    geometry the scan is missing.
    """
    n = len(loop)
    if n < 3:
        return []
    P = verts[loop]
    if n > MAX_LOOP:  # the DP is O(n^3); fan from the centroid instead
        c = P.mean(axis=0)
        return [[P[i], P[(i + 1) % n], c] for i in range(n)]

    def area(i, j, k):
        return float(np.linalg.norm(np.cross(P[j] - P[i], P[k] - P[i]))) / 2

    W = np.zeros((n, n))
    O = np.zeros((n, n), dtype=int)
    for gap in range(2, n):
        for i in range(0, n - gap):
            j = i + gap
            best, arg = np.inf, -1
            for k in range(i + 1, j):
                cost = W[i][k] + W[k][j] + area(i, k, j)
                if cost < best:
                    best, arg = cost, k
            W[i][j], O[i][j] = best, arg

    out, stack = [], [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j - i < 2:
            continue
        k = int(O[i][j])
        out.append([P[i], P[k], P[j]])
        stack.append((i, k))
        stack.append((k, j))
    return out


def width(tri):
    """The triangle's shortest altitude -- how wide a gap it spans.

    2*Area/longest edge. For a zipper triangle across a 2-stud slit this is
    about 2; for a membrane thrown over a courtyard it is tens of studs.
    """
    a, b, c = (np.asarray(p, float) for p in tri)
    longest = max(np.linalg.norm(b - a), np.linalg.norm(c - b), np.linalg.norm(a - c))
    if longest < 1e-9:
        return 0.0
    return float(np.linalg.norm(np.cross(b - a, c - a))) / longest


def dilate(tri, pad):
    """Grow a triangle in its own plane so it laps over its neighbours.

    Offsetting every edge outward by `pad` moves each corner along its bisector
    by pad/sin(half-angle). At the tip of a sliver that is enormous, and an
    uncapped version threw visible needles off the Cerulean crown's rim. The
    inradius is the right yardstick: it is the triangle's own thickness, so a
    sliver's corners barely move while a healthy triangle grows the full pad.
    """
    a, b, c = (np.asarray(p, float) for p in tri)
    cen = (a + b + c) / 3
    lengths = [np.linalg.norm(b - a), np.linalg.norm(c - b), np.linalg.norm(a - c)]
    perimeter = sum(lengths)
    if perimeter < 1e-9:
        return [list(a), list(b), list(c)]
    inradius = float(np.linalg.norm(np.cross(b - a, c - a))) / perimeter
    ceiling = min(max(pad, 2 * inradius), MAX_PAD_STEP)

    out = []
    for p, q, r in ((a, b, c), (b, c, a), (c, a, b)):
        d1, d2 = _norm(q - p), _norm(r - p)
        bis = d1 + d2
        if np.linalg.norm(bis) < 1e-9:
            out.append(p)
            continue
        bis = _norm(bis)
        sin_half = max(float(np.linalg.norm(np.cross(d1, bis))), 1e-3)
        step = min(pad / sin_half, ceiling)
        # the bisector points inward, towards the other two corners
        out.append(p - bis * step if bis @ (cen - p) > 0 else p + bis * step)
    return out


def area_of(tris):
    return sum(float(np.linalg.norm(np.cross(
        np.asarray(t[1]) - np.asarray(t[0]),
        np.asarray(t[2]) - np.asarray(t[0])))) / 2 for t in tris)


def _seal_once(tris, cap_top, weld_tol, rim_tol, budget):
    verts, faces = weld(tris, weld_tol)
    if not faces:
        return [], 0, 0, 0
    ymin, ymax = float(verts[:, 1].min()), float(verts[:, 1].max())
    added, filled, left = [], 0, 0
    for loop in boundary_loops(verts, faces):
        ys = verts[loop][:, 1]
        flat = float(ys.max() - ys.min()) <= rim_tol
        at_bottom = flat and abs(float(ys.mean()) - ymin) <= rim_tol
        at_top = flat and abs(float(ys.mean()) - ymax) <= rim_tol
        if at_bottom or (at_top and not cap_top):
            left += 1
            continue
        patch = fill_loop(verts, loop)
        # A patch bigger than this is not a slit; it is a face the FBX left off
        # on purpose, and covering it would wall over real shape.
        if not patch or area_of(patch) > budget:
            left += 1
            continue
        # Zip the narrow stretches of the loop and leave the wide middle open,
        # rather than accept or reject the loop whole. A loop is often a thin
        # crack that opens out into a genuine gap at one end.
        narrow = [t for t in patch if width(t) <= MAX_GAP]
        if not narrow:
            left += 1
            continue
        added.extend(narrow)
        filled += 1
    out = [verts[f] for f in faces] + [np.asarray(t) for t in added]
    return [t for t in out if buildable(*t)], filled, left, len(added)


def seal(tris, cap_top=False, weld_tol=WELD, pad=PAD, rim_tol=RIM_TOL,
         passes=PASSES):
    """-> (triangles, stats). In and out are lists of three [x,y,z] points.

    Sealing runs more than once: a boundary walk can dead-end where three crack
    edges meet, and the edges it had to abandon only chain into a closed loop
    once the first pass has filled its neighbours.
    """
    raw = [np.asarray(t, float) for t in tris]
    work = [t for t in raw if buildable(*t)]
    stats = {"in": len(raw), "slivers": len(raw) - len(work),
             "filled": 0, "open_loops": 0, "added": 0, "passes": 0}
    if not work:
        return [], dict(stats, out=0, cracks=0)

    budget = area_of(work) * MAX_FILL_SHARE
    cracks = crack_count(work, weld_tol, rim_tol)
    for _ in range(passes):
        if cracks == 0:
            break
        nxt, filled, left, added = _seal_once(work, cap_top, weld_tol, rim_tol, budget)
        if not nxt:
            break
        after = crack_count(nxt, weld_tol, rim_tol)
        if after >= cracks and filled == 0:
            break
        work, cracks = nxt, after
        stats["filled"] += filled
        stats["open_loops"] = left
        stats["added"] += added
        stats["passes"] += 1

    out = [[list(map(float, p)) for p in t] for t in work]
    stats.update(out=len(out), cracks=cracks)
    if pad > 0:
        # Dilation detaches the triangles from one another on purpose, so it
        # runs after the crack count is taken -- measuring it afterwards would
        # report every edge as a crack.
        out = [[list(map(float, p)) for p in dilate(t, pad)] for t in work]
        out = [t for t in out if buildable(*(np.asarray(p) for p in t))]
        stats["out"] = len(out)
    return out, stats


def crack_count(tris, weld_tol=WELD, rim_tol=RIM_TOL):
    """Boundary edges that are not a flat top/bottom rim -- the gap metric."""
    verts, faces = weld([np.asarray(t, float) for t in tris], weld_tol)
    if not faces:
        return 0
    use = defaultdict(int)
    for f in faces:
        for a, b in ((f[0], f[1]), (f[1], f[2]), (f[2], f[0])):
            use[(min(a, b), max(a, b))] += 1
    ymin, ymax = verts[:, 1].min(), verts[:, 1].max()
    cracks = 0
    for (a, b), count in use.items():
        if count != 1:
            continue
        ya, yb = verts[a][1], verts[b][1]
        rim = ((abs(ya - ymin) < rim_tol and abs(yb - ymin) < rim_tol)
               or (abs(ya - ymax) < rim_tol and abs(yb - ymax) < rim_tol))
        if not rim:
            cracks += 1
    return cracks
