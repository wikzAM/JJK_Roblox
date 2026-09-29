"""Simple roads, FITTED to the buildings: OSM says which streets exist and how
they connect; the building footprints say where they can go.

Plain OSM geometry disagrees with the PLATEAU footprints by up to ~11 m, and
OSM widths are guesses, so roads laid straight from OSM ran into ground floors
(11% of roadway area sat on a footprint). And every street's slabs and joints
overlapped at junctions at slightly different angles and heights.

  1. Ways are split at junctions (OSM node ids shared between ways) into edges.
  2. Every SAMPLE studs along an edge, the open corridor across the street is
     read from the footprint mask. The street is moved to the corridor's
     centre (at most SHIFT_MAX) and narrowed to fit it (MARGIN each side), so
     no slab can enter a ground floor.
  3. Junction nodes closer than a road width merge into one cluster (dual
     carriageways, complex crossings) and get ONE square pad, aligned to the
     widest street; streets are trimmed to stop at its edge.
  4. Round joints only on real bends inside an edge. `service` ways (parking
     aisles, driveways) are dropped, as are edges shorter than a pad.

  python tools/road_fit.py      -> source_slices/ground/roads/ (same format as road_parts.py)
"""
from pathlib import Path
from collections import defaultdict
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import road_parts as RP  # noqa: E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402

DATA = RP.DATA
SAMPLE = 6.0         # studs between corridor readings along a street
SCAN = 60.0          # studs: how far across the street the corridor is read
SHIFT_MAX = 40.0     # studs a street may be moved sideways (OSM is up to ~35 off in places, e.g. Shibuya Pkwy)
MARGIN = 2.0         # studs kept clear of a footprint on each side
MIN_W = 8.0          # studs: narrower gaps are between buildings, not streets
BRIDGE = 10.0        # studs: blocked stretches this short are bridged, not cut
MIN_PIECE = 12.0     # studs: shorter pieces merge into a neighbour
PIECE_SHIFT = 8.0    # studs a piece may slide sideways toward open ground at a corner
RECENTRE = 3.0       # studs: the most one slab may be moved off its street's line
BEND_DEG = 25.0      # a turn sharper than this inside an edge gets a round joint
DROP_KINDS = {"service"}
PAD_OVER = 2.0       # studs a pad extends past the widest street
SLAB_TUCK = 1.0      # studs a street runs under its pad


def main():
    import jgd_cs9
    g = json.loads((DATA / "tile_georef.json").read_text())
    s, rot = g["studs_per_m"], math.radians(g["rotation_deg"])
    mirror = -1.0 if g["mirror_y"] else 1.0
    toff = g["t"]
    c, sn = math.cos(rot), math.sin(rot)

    def to_studs(lat, lon):
        e, n = jgd_cs9.to_xy(lat, lon)
        x, y = e * s, mirror * n * s
        return x * c - y * sn + toff[0], x * sn + y * c + toff[1]

    S, x0, z0, cell = RP.surface()
    inside = np.load(DATA / "heights.npz")["known"]
    city = ndimage.binary_dilation(inside, iterations=int(RP.CITY_MARGIN / cell))
    # the LIVE ground floors (tools/live_footprints.py, uploaded from Studio):
    # heights.npz's mask still held removed buildings and missed newer ones
    lf = np.load(DATA / "live_footprints.npz")
    blocked, bx0, bz0, bcell = lf["mask"], float(lf["x0"]), float(lf["z0"]), float(lf["cell"])
    print(f"blocking on live footprints ({bcell:.0f}-stud cells)")
    nx, nz = inside.shape
    bnx, bnz = blocked.shape

    def is_blocked(x, z):
        i, j = int((x - bx0) / bcell), int((z - bz0) / bcell)
        return not (0 <= i < bnx and 0 <= j < bnz) or bool(blocked[i, j])

    def in_city(x, z):
        i, j = int((x - x0) / cell), int((z - z0) / cell)
        return 0 <= i < nx and 0 <= j < nz and bool(city[i, j])

    def ground(x, z):
        fi = min(max((x - x0) / cell, 0), S.shape[0] - 1.001)
        fj = min(max((z - z0) / cell, 0), S.shape[1] - 1.001)
        i, j = int(fi), int(fj)
        u, v = fi - i, fj - j
        return float(S[i, j] * (1 - u) * (1 - v) + S[i + 1, j] * u * (1 - v)
                     + S[i, j + 1] * (1 - u) * v + S[i + 1, j + 1] * u * v)

    # ---- 1. ways -> edges split at junctions
    osm = json.loads((DATA / "osm_roads.json").read_text(encoding="utf-8"))
    ways = []
    skipped_level = defaultdict(int)
    for w in osm["elements"]:
        tags = w.get("tags", {})
        kind = tags.get("highway")
        if not w.get("geometry") or kind not in RP.KIND or kind in DROP_KINDS:
            continue
        # off the ground: tunnels and underpasses (layer < 0), bridges and the
        # elevated Shuto Expressway (motorway / layer > 0) -- the viaducts were
        # removed from the map, and drawn on the ground they stacked onto the
        # streets beneath them
        # a closed way / area=yes is a plaza OUTLINE, not a street: drawn as a
        # road it made rings of short blades at every angle
        if tags.get("area") == "yes" or w["nodes"][0] == w["nodes"][-1]:
            skipped_level["area/closed"] += 1
            continue
        layer = tags.get("layer", "0")
        if (tags.get("tunnel") in ("yes", "building_passage") or tags.get("bridge") in ("yes", "viaduct")
                or kind == "motorway" or (layer.lstrip("-").isdigit() and int(layer) != 0)):
            skipped_level[kind] += 1
            continue
        road_m, _, prio = RP.KIND[kind]
        oneway = tags.get("oneway") in ("yes", "-1")
        if tags.get("lanes", "").isdigit():
            # on a one-way way, lanes counts only its own direction
            road_m = int(tags["lanes"]) * RP.LANE_M + 1.0 if oneway else max(road_m, int(tags["lanes"]) * RP.LANE_M + 1.0)
        elif oneway and kind in ("trunk", "primary", "secondary", "tertiary"):
            # one half of a dual carriageway: OSM draws each direction as its own
            # way, and both at the full road width stacked into each other
            road_m /= 2
        pts = [to_studs(p["lat"], p["lon"]) for p in w["geometry"]]
        ways.append(dict(id=w["id"], kind=kind, prio=prio, width=road_m * s, nodes=w["nodes"], pts=pts))
    uses = defaultdict(int)
    for w in ways:
        for k, nid in enumerate(w["nodes"]):
            uses[nid] += 2 if 0 < k < len(w["nodes"]) - 1 else 1
    junction = {nid for nid, u in uses.items() if u >= 3}
    node_pos = {}
    edges = []
    for w in ways:
        for nid, p in zip(w["nodes"], w["pts"]):
            node_pos[nid] = p
        start = 0
        for k in range(1, len(w["nodes"])):
            if w["nodes"][k] in junction or k == len(w["nodes"]) - 1:
                edges.append(dict(way=w, a=w["nodes"][start], b=w["nodes"][k], pts=w["pts"][start:k + 1]))
                start = k
    print(f"{len(ways)} ways ({', '.join(sorted(DROP_KINDS))} dropped; off-ground dropped: {dict(skipped_level)}), "
          f"{len(junction)} junction nodes, {len(edges)} edges")

    # ---- 2. fit each edge into its corridor
    def corridor(x, z, nxv, nzv):
        """Open run across the street through (x, z): (centre offset, width) or None."""
        steps = np.arange(-SCAN, SCAN + 0.1, 2.0)
        free = [not is_blocked(x + nxv * t, z + nzv * t) for t in steps]
        runs, cur = [], None
        for t, f in zip(steps, free):
            if f and cur is None: cur = [t, t]
            elif f: cur[1] = t
            elif cur is not None: runs.append(cur); cur = None
        if cur is not None: runs.append(cur)
        if not runs:
            return None
        # the run containing the OSM centreline, else the nearest one
        best = min(runs, key=lambda r: 0 if r[0] <= 0 <= r[1] else min(abs(r[0]), abs(r[1])))
        if not (best[0] <= 0 <= best[1]) and min(abs(best[0]), abs(best[1])) > SHIFT_MAX:
            return None
        return (best[0] + best[1]) / 2, best[1] - best[0]

    def offset_line(pts, o):
        """The polyline moved sideways by o studs (mitred at the vertices)."""
        P = np.array(pts, float)
        segs = P[1:] - P[:-1]
        lens = np.hypot(segs[:, 0], segs[:, 1])
        keep = lens > 1e-6
        if keep.sum() == 0:
            return None
        P = np.vstack([P[:-1][keep], P[-1:]])
        segs = P[1:] - P[:-1]
        u = segs / np.hypot(segs[:, 0], segs[:, 1])[:, None]
        nrm = np.stack([-u[:, 1], u[:, 0]], 1)
        vn = np.vstack([nrm[:1], (nrm[:-1] + nrm[1:]) / 2, nrm[-1:]])
        vn /= np.maximum(np.hypot(vn[:, 0], vn[:, 1]), 1e-6)[:, None]
        return [tuple(p) for p in P + vn * o]

    def band_blocked(pts, w):
        """How many sample points of a road band of width w are over a floor."""
        bad = n = 0
        for k in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[k], pts[k + 1]
            L = math.hypot(bx - ax, bz - az)
            if L < 1e-6: continue
            ux, uz = (bx - ax) / L, (bz - az) / L
            for a in np.arange(0, L, 4.0):
                for b in np.arange(-w / 2, w / 2 + 0.1, 4.0):
                    n += 1
                    bad += is_blocked(ax + ux * a - uz * b, az + uz * a + ux * b)
        return bad, max(n, 1)

    # One sideways offset per edge: OSM's error against PLATEAU is a smooth local
    # shift, so the street keeps its real shape and the whole edge slides to
    # where the least of it is over a building. (Following the open corridor
    # sample by sample made streets zigzag wherever a side gap opened.)
    fitted = []
    shifts = []
    for e in edges:
        pts = RP.simplify(e["pts"], 3.0)   # longer straight pieces; curves still read as curves at 3 studs
        if len(pts) < 2:
            continue
        w = e["way"]["width"]
        best = None
        for o in np.arange(-SHIFT_MAX, SHIFT_MAX + 0.1, 2.0):
            moved = offset_line(pts, o)
            if moved is None: break
            bad, n = band_blocked(moved, w)
            key = (bad, abs(o))
            if best is None or key < best[0]:
                best = (key, o, moved)
        if best is None:
            continue
        shifts.append(best[1])
        fitted.append(dict(e, pts=best[2], width=w))
    sh = np.abs(np.array(shifts))
    print(f"edge shifts: median {np.median(sh):.0f}, p90 {np.percentile(sh, 90):.0f} studs")
    print(f"{len(fitted)} edges fitted to their corridors")

    # ---- 3. junction clusters -> pads
    ends = defaultdict(list)                         # junction node -> fitted edges touching it
    for f in fitted:
        if f["a"] in junction: ends[f["a"]].append((f, 0))
        if f["b"] in junction: ends[f["b"]].append((f, -1))
    parent = {n: n for n in ends}

    def find(n):
        while parent[n] != n:
            parent[n] = parent[parent[n]]; n = parent[n]
        return n
    jn = list(ends)
    jpos = {n: np.mean([f["pts"][k] for f, k in ends[n]], axis=0) for n in jn}
    jw = {n: max(f["width"] for f, _ in ends[n]) for n in jn}
    for i in range(len(jn)):
        for k in range(i + 1, len(jn)):
            a, b = jn[i], jn[k]
            if np.hypot(*(jpos[a] - jpos[b])) < max(jw[a], jw[b]):
                parent[find(a)] = find(b)
    clusters = defaultdict(list)
    for n in jn:
        clusters[find(n)].append(n)
    pads = []
    edge_trim = {}                                   # (id(edge), end index) -> (pad centre, pad half-size)
    for members in clusters.values():
        touching = [(f, k) for n in members for f, k in ends[n]]
        centre = np.mean([jpos[n] for n in members], axis=0)
        spread = max(float(np.hypot(*(jpos[n] - centre))) for n in members)
        widest = max(touching, key=lambda t: t[0]["width"])[0]
        side = max(f["width"] for f, _ in touching) + 2 * spread + PAD_OVER
        p0, p1 = widest["pts"][0], widest["pts"][-1]
        yaw = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        kind = max(touching, key=lambda t: t[0]["way"]["prio"])[0]["way"]
        pad = dict(x=float(centre[0]), z=float(centre[1]), side=side, yaw=yaw,
                   prio=kind["prio"], kind=kind["kind"], way=kind["id"], dropped=False)
        pads.append(pad)
        for f, k in touching:
            edge_trim[(id(f), k)] = (centre, pad)     # trimmed to the pad's FINAL size, if it survives
    print(f"{len(jn)} junction nodes -> {len(pads)} pads")

    # ---- 4. emit
    tiles, counts, total = defaultdict(list), defaultdict(int), 0.0
    dropped = defaultdict(int)

    def emit(kind, x, y, z, yaw, pitch, length, thick, width, cls, wid, extra=None):
        if not in_city(x, z):
            return
        key = (int(math.floor(x / RP.TILE)), int(math.floor(z / RP.TILE)))
        row = [kind, round(x, 2), round(y, 2), round(z, 2), round(yaw, 5), round(pitch, 5),
               round(length, 2), round(thick, 2), round(width, 2), cls, wid]
        if extra is not None:
            row.append(round(extra, 5))       # pads: slope along the local Z axis
        tiles[key].append(row)
        counts[kind] += 1

    def clear_square(x, z, yaw, side):
        """Is a pad square clear of floors (2-stud sampling, MARGIN inset)?"""
        cc, ss = math.cos(yaw), math.sin(yaw)
        h = side / 2 + MARGIN
        for a in np.arange(-h, h + 0.1, 2.0):
            for b in np.arange(-h, h + 0.1, 2.0):
                if is_blocked(x + a * cc - b * ss, z + a * ss + b * cc):
                    return False
        return True

    def clear_radius(x, z, rmax):
        """Distance from (x, z) to the nearest floor, up to rmax."""
        for r in np.arange(1.0, rmax + 0.1, 1.0):
            for k in range(max(8, int(r * 1.6))):
                ang = 2 * math.pi * k / max(8, int(r * 1.6))
                if is_blocked(x + r * math.cos(ang), z + r * math.sin(ang)):
                    return r - 1.0
        return rmax

    for pad in pads:
        side = pad["side"]
        while side >= MIN_W and not clear_square(pad["x"], pad["z"], pad["yaw"], side):
            side -= 2.0
        if side < MIN_W:
            dropped["pad no room"] += 1
            pad["dropped"] = True        # its streets then run on to meet at the node
            continue
        pad["side"] = side
        # the pad follows the ground's slope (a plane through the field at its
        # edges) so streets meeting it at any side arrive at its height
        cy, sy = math.cos(pad["yaw"]), math.sin(pad["yaw"])
        h = side / 2
        px_, pz_ = pad["x"], pad["z"]
        gx = (ground(px_ + cy * h, pz_ + sy * h) - ground(px_ - cy * h, pz_ - sy * h)) / side
        gz = (ground(px_ - sy * h, pz_ + cy * h) - ground(px_ + sy * h, pz_ - cy * h)) / side
        yc = (ground(px_ + cy * h, pz_ + sy * h) + ground(px_ - cy * h, pz_ - sy * h)
              + ground(px_ - sy * h, pz_ + cy * h) + ground(px_ + sy * h, pz_ - cy * h)) / 4
        pad["plane"] = (px_, pz_, yc, gx, gz, cy, sy)
        emit("pad", px_, yc + pad["prio"] * 0.05 + 0.1, pz_, pad["yaw"], gx,
             side, RP.THICKNESS, side, pad["kind"], pad["way"], extra=gz)

    def rect_clear(cx, cz, ux, uz, L, W, grow=1.0):
        """Final check: the whole rectangle, grown by `grow`, is off every floor."""
        hl, hw = L / 2 + grow, W / 2 + grow
        for a in np.arange(-hl, hl + 0.01, 1.0):
            for b in np.arange(-hw, hw + 0.01, 1.0):
                if is_blocked(cx + ux * a - uz * b, cz + uz * a + ux * b):
                    return False
        return True

    def side_clear(sx, sz, nxv, nzv):
        reach = 0.0
        while reach < SCAN and not is_blocked(sx + nxv * (reach + 1), sz + nzv * (reach + 1)):
            reach += 1.0
        return reach

    for f in fitted:
        pts = [np.array(p, float) for p in f["pts"]]
        end_pad = {0: None, -1: None}
        # stop at the pads: pull each junction end back to the pad's edge (a little under it)
        for k in (0, -1):
            t = edge_trim.get((id(f), k))
            if t is None: continue
            centre, pad = t
            if pad["dropped"]:
                continue
            half = pad["side"] / 2
            end_pad[k] = pad
            inner = pts[1] if k == 0 else pts[-2]
            d = inner - centre
            L = float(np.hypot(*d))
            cut = half - SLAB_TUCK
            if L <= cut + 1:
                pts = None; break
            pts[k] = centre + d / L * cut
            if k == 0: pts = [pts[0]] + [p for p in pts[1:] if np.hypot(*(p - centre)) > cut]
            else: pts = [p for p in pts[:-1] if np.hypot(*(p - centre)) > cut] + [pts[-1]]
        if pts is None or len(pts) < 2:
            continue
        w, way = f["width"], f["way"]
        for k in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[k], pts[k + 1]
            seg = math.hypot(bx - ax, bz - az)
            if seg < 1.0: continue
            ux, uz = (bx - ax) / seg, (bz - az) / seg
            # PIECEWISE FIT: the width the street may have at every 2 studs, then
            # pieces of steady width; only the stretches with no room are dropped
            samples = np.arange(0, seg + 0.1, 2.0)
            LR = []
            for a in samples:
                sx, sz = ax + ux * a, az + uz * a
                LR.append((side_clear(sx, sz, -uz, ux), side_clear(sx, sz, uz, -ux)))

            def width_at(i, s):
                l, r = LR[i]
                return min(w, 2 * min(l - s, r + s) - 2 * MARGIN)

            def best_shift(i):
                l, r = LR[i]
                return max(-PIECE_SHIFT, min(PIECE_SHIFT, (l - r) / 2))

            # pieces of steady width AND steady sideways shift: where a building
            # corner narrows one side, the piece slides (<= PIECE_SHIFT) toward
            # the open side instead of the whole street being cut there
            pieces, cur = [], None
            for i in range(len(samples)):
                s = cur[3] if cur else best_shift(i)
                sw = width_at(i, s)
                if cur and (sw < MIN_W or sw < cur[2] - 4):
                    s2 = best_shift(i)
                    if width_at(i, s2) >= MIN_W:
                        pieces.append(cur); cur = None; s, sw = s2, width_at(i, s2)
                if sw < MIN_W:
                    if cur: pieces.append(cur); cur = None
                    dropped["stretch with no room (2-stud samples)"] += 1
                    continue
                if cur is None:
                    cur = [i, i, sw, s]
                elif sw > cur[2] + 6 and i - cur[0] >= 10:
                    pieces.append(cur); cur = [i, i, sw, best_shift(i)]
                else:
                    cur[1] = i; cur[2] = min(cur[2], sw)
                if cur and (samples[cur[1]] - samples[cur[0]]) >= RP.SEGMENT:
                    pieces.append(cur); cur = [i, i, sw, s]
            if cur: pieces.append(cur)
            # no fragments: a piece under MIN_PIECE studs joins a contiguous
            # neighbour with a similar shift (the narrower width wins); a short
            # piece with no neighbour is dropped
            merged = []
            for pc in pieces:
                short = (pc[1] - pc[0]) * 2.0 < MIN_PIECE
                if merged and pc[0] <= merged[-1][1] + 1 and abs(pc[3] - merged[-1][3]) <= 2.0 and (
                        short or (merged[-1][1] - merged[-1][0]) * 2.0 < MIN_PIECE):
                    merged[-1] = [merged[-1][0], pc[1], min(merged[-1][2], pc[2]), merged[-1][3]]
                else:
                    merged.append(list(pc))
            pieces = [pc for pc in merged if (pc[1] - pc[0]) * 2.0 >= MIN_PIECE / 2]
            for pi_, (i0, i1, sw, shf) in enumerate(pieces):
                a0, a1 = samples[i0], samples[i1]
                # overlap a neighbouring piece by a stud; an end that stops at a
                # blocked stretch (a building) gets no overhang -- it poked into
                # the building before
                if pi_ > 0 and pieces[pi_ - 1][1] >= i0 - 1: a0 -= 1.0
                elif i0 == 0 and k > 0: a0 -= 1.0          # meets the previous polyline segment
                if pi_ < len(pieces) - 1 and pieces[pi_ + 1][0] <= i1 + 1: a1 += 1.0
                elif i1 == len(samples) - 1 and k < len(pts) - 2: a1 += 1.0
                L = a1 - a0
                if L < 4.0:
                    continue
                px, pz = ax + ux * a0 - uz * shf, az + uz * a0 + ux * shf
                qx, qz = ax + ux * a1 - uz * shf, az + uz * a1 + ux * shf
                # a slanted building edge can cut between the 2-stud clearance
                # lines or into an end overhang: narrow until the whole piece is clear
                mx, mz = (px + qx) / 2, (pz + qz) / 2
                while sw >= MIN_W and not rect_clear(mx, mz, ux, uz, L, sw):
                    sw -= 2.0
                if sw < MIN_W:
                    dropped["piece failed its final check"] += 1
                    continue
                y0, y1 = ground(px, pz), ground(qx, qz)
                # an end that runs under a pad meets it at the PAD'S height (the
                # pad is a plane; the field curves, and the difference showed as
                # the pad's edge standing proud of the street)
                def on_plane(pad, x, z):
                    cx_, cz_, yc_, gx_, gz_, cy_, sy_ = pad["plane"]
                    dx_, dz_ = x - cx_, z - cz_
                    return yc_ + gx_ * (dx_ * cy_ + dz_ * sy_) + gz_ * (-dx_ * sy_ + dz_ * cy_) + 0.1
                if k == 0 and i0 == 0 and end_pad[0] is not None and "plane" in end_pad[0]:
                    y0 = on_plane(end_pad[0], px, pz)
                if k == len(pts) - 2 and i1 == len(samples) - 1 and end_pad[-1] is not None and "plane" in end_pad[-1]:
                    y1 = on_plane(end_pad[-1], qx, qz)
                emit("roadway", (px + qx) / 2, (y0 + y1) / 2 + way["prio"] * 0.05, (pz + qz) / 2,
                     math.atan2(uz, ux), math.atan2(y1 - y0, L), L, RP.THICKNESS, sw, way["kind"], way["id"])
                total += L
            # a real bend inside the edge: one round joint, as wide as there is room for
            if 0 < k + 1 < len(pts) - 1:
                (cx2, cz2) = pts[k + 2]
                turn = math.atan2(cz2 - bz, cx2 - bx) - math.atan2(bz - az, bx - ax)
                if abs((turn + math.pi) % (2 * math.pi) - math.pi) >= math.radians(BEND_DEG):
                    dia = min(w, 2 * (clear_radius(bx, bz, w / 2 + MARGIN) - MARGIN))
                    if dia >= MIN_W:
                        emit("joint", bx, ground(bx, bz) + way["prio"] * 0.05 - 0.03, bz, 0.0, 0.0, dia,
                             RP.THICKNESS, dia, way["kind"], way["id"])
                    else:
                        dropped["joint no room"] += 1

    # ---- clipping check: roadway area over a ground floor
    on = tot = 0
    for rows in tiles.values():
        for r in rows:
            _, cx_, _, cz_, yaw_, _, L, _, W = r[:9]
            if r[0] == "joint": yaw_ = 0.0
            cc, ss = math.cos(yaw_), math.sin(yaw_)
            for a in np.linspace(-L / 2, L / 2, max(2, int(L / cell) + 1)):
                for b in np.linspace(-W / 2, W / 2, max(2, int(W / cell) + 1)):
                    tot += 1
                    on += is_blocked(cx_ + a * cc - b * ss, cz_ + a * ss + b * cc)

    out = DATA / "roads"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.json"):
        f.unlink()
    names = []
    for (a, b), rows in sorted(tiles.items()):
        name = f"tile_{a:+d}_{b:+d}".replace("+", "p").replace("-", "m")
        (out / f"{name}.json").write_text(json.dumps({"name": name, "slabs": rows}))
        names.append([name, len(rows)])
    (out / "index.json").write_text(json.dumps(names))
    print(f"{counts['roadway']} roadway + {counts['pad']} pads + {counts['joint']} joints = {sum(counts.values())} parts "
          f"over {len(names)} tiles; {total / 4.182937 / 1000:.1f} km of street")
    print(f"road area (slabs, pads, joint boxes) over a ground floor: {on / max(tot, 1):.2%}  (plain OSM was 11.2%)")
    print("slabs dropped:", dict(dropped))


if __name__ == "__main__":
    main()
