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
BEND_DEG = 8.0
SIDEWALK_BAND = 6.0  # studs of pavement kept between a street slab and the buildings
WIDE_MAX = 110.0     # studs: no street slab wider than this
STRAIGHTEN = 6.0     # studs: a street's polyline is simplified this hard -> long straight slabs
EVEN_SPAN = 40.0     # studs: heights are averaged over this span along a street
BLEND = 20.0         # studs over which a street's height eases into its junction pad      # a turn sharper than this inside an edge gets a round joint
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
    # Streets take their height from the STREET surface only. RP.surface() puts
    # building floor heights on every cell heights.npz marks as a building, and
    # that mask is stale: roads fitted to the live footprints now cross some of
    # those cells and climbed to a floor (one street pitched 24 degrees).
    d_ = np.load(DATA / "heights.npz")
    known_ = d_["known"]
    street_only = np.where(known_, np.nan, S)
    # fill the holes from the nearest street cells, then smooth lightly
    idx = ndimage.distance_transform_edt(np.isnan(street_only), return_distances=False, return_indices=True)
    S = ndimage.gaussian_filter(street_only[tuple(idx)], 1.5, mode="nearest")
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

    # the map's extent: within CITY_MARGIN (true distance) of a LIVE building.
    # The old test dilated the stale heights.npz mask with a diamond kernel and
    # called streets in the middle of town "outside the city" (dropped slabs).
    live_city = ndimage.distance_transform_edt(~blocked) * bcell <= RP.CITY_MARGIN

    def in_city(x, z):
        i, j = int((x - bx0) / bcell), int((z - bz0) / bcell)
        return 0 <= i < bnx and 0 <= j < bnz and bool(live_city[i, j])

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
        tried = []
        for o in np.arange(-SHIFT_MAX, SHIFT_MAX + 0.1, 2.0):
            moved = offset_line(pts, o)
            if moved is None: break
            bad, n = band_blocked(moved, min(w, MIN_W + 4))   # does a minimal street fit? (full OSM width collides in narrow alleys)
            tried.append((bad, o, moved))
        if not tried:
            continue
        # among the offsets that are equally clear, take the MIDDLE of the run
        # containing the one nearest the OSM line: that centres the street in
        # its corridor (taking the smallest shift left it hugging one side,
        # and narrowed to fit)
        least = min(b for b, _, _ in tried)
        ok = [i for i, (b, _, _) in enumerate(tried) if b <= least]
        near_i = min(ok, key=lambda i: abs(tried[i][1]))
        lo_i = hi_i = near_i
        while lo_i - 1 in ok: lo_i -= 1
        while hi_i + 1 in ok: hi_i += 1
        _, o, moved = tried[(lo_i + hi_i) // 2]
        shifts.append(o)
        fitted.append(dict(e, pts=moved, width=w))
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
        widest, wk = max(touching, key=lambda t: t[0]["width"])
        side = max(f["width"] for f, _ in touching) + 2 * spread + PAD_OVER
        # aligned to the widest street WHERE IT ARRIVES (its last stretch into
        # the node), not its overall direction -- a curving street left the pad
        # visibly twisted against it
        P = widest["pts"]
        if wk == 0:
            a_, b_ = np.array(P[0], float), np.array(P[min(len(P) - 1, 1)], float)
        else:
            a_, b_ = np.array(P[max(0, len(P) - 2)], float), np.array(P[-1], float)
        if np.hypot(*(b_ - a_)) < 1e-6:
            a_, b_ = np.array(P[0], float), np.array(P[-1], float)
        yaw = math.atan2(b_[1] - a_[1], b_[0] - a_[0])
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
    narrow_log = []
    blocked_log = []
    def total_len_edge(P):
        return sum(float(np.hypot(*(P[i + 1] - P[i]))) for i in range(len(P) - 1))

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
        way = f["way"]
        # SIMPLE STREETS (Sept 30, owner: "straight roads aligned, slight curves
        # simple, the road middle flat and even"):
        #  * straight runs: the polyline simplified hard, one slab per run
        #  * ONE width for the whole street: its narrowest clear point
        #  * heights smoothed ALONG the street, and neighbouring slabs share
        #    their end heights, so the surface is one even ribbon
        pts = [np.array(q, float) for q in RP.simplify([tuple(q) for q in pts], STRAIGHTEN)]
        if len(pts) < 2:
            continue
        # width: clearance measured every 4 studs along the whole street
        clear = []
        for k in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[k], pts[k + 1]
            seg = math.hypot(bx - ax, bz - az)
            if seg < 1.0: continue
            ux, uz = (bx - ax) / seg, (bz - az) / seg
            for a in np.arange(2.0, seg - 1.9, 4.0):
                sx, sz = ax + ux * a, az + uz * a
                clear.append(2 * min(side_clear(sx, sz, -uz, ux), side_clear(sx, sz, uz, -ux)) - 2 * MARGIN)
        if not clear:
            continue
        # from the stretches that are open at all: a covered passage or arcade
        # part-way along must not narrow (or drop) the whole street -- its
        # slabs are skipped one by one below and the asphalt terrain shows there
        open_ = [c_ for c_ in clear if c_ >= MIN_W]
        if len(open_) < max(2, 0.3 * len(clear)):
            dropped["street mostly under buildings"] += 1
            blocked_log.append((way["kind"], total_len_edge(pts), len(open_) / max(1, len(clear)), [round(v) for v in pts[len(pts) // 2]]))
            continue
        # FILL THE STREET: the slab spans building to building less a sidewalk
        # each side, not just OSM's carriageway -- the uncovered rest was bare
        # terrain, which terraces on slopes (the owner's "uneven road"). The
        # sidewalk band is pavement-painted terrain (tools/ground_paint.py).
        corridor = float(np.percentile(open_, 15)) - 2 * SIDEWALK_BAND
        w = min(max(f["width"], corridor), WIDE_MAX, float(np.percentile(open_, 15)))
        w = math.floor(w / 2) * 2
        if w < MIN_W:
            dropped["street too narrow"] += 1
            narrow_log.append((len(clear), float(np.median(clear)), float(np.percentile(clear, 15)), f["width"]))
            continue
        # heights: the street surface sampled along the street, then smoothed
        # along it (a running mean over EVEN_SPAN studs): the road rides the
        # hill, not every bump of the ground under it
        cum = [0.0]
        for k in range(len(pts) - 1):
            cum.append(cum[-1] + float(np.hypot(*(pts[k + 1] - pts[k]))))
        total_len_e = cum[-1]
        ss = np.arange(0, total_len_e + 0.1, 4.0)
        def at(s_):
            k = max(0, min(len(pts) - 2, int(np.searchsorted(cum, s_, side="right") - 1)))
            L_ = max(cum[k + 1] - cum[k], 1e-6)
            q = pts[k] + (pts[k + 1] - pts[k]) * ((s_ - cum[k]) / L_)
            return q
        hs = np.array([ground(*at(s_)) for s_ in ss])
        win = max(1, int(EVEN_SPAN / 4.0))
        if len(hs) > 2:
            kern = np.ones(2 * win + 1) / (2 * win + 1)
            hs = np.convolve(np.pad(hs, win, mode="edge"), kern, mode="valid")
        def h_at(s_):
            y = float(np.interp(s_, ss, hs))
            return y
        # ends that meet a pad take the pad's plane there
        def on_plane(pad, x, z):
            cx_, cz_, yc_, gx_, gz_, cy_, sy_ = pad["plane"]
            dx_, dz_ = x - cx_, z - cz_
            return yc_ + gx_ * (dx_ * cy_ + dz_ * sy_) + gz_ * (-dx_ * sy_ + dz_ * cy_) + 0.1
        y_start = on_plane(end_pad[0], *pts[0]) if end_pad[0] is not None and "plane" in end_pad[0] else None
        y_end = on_plane(end_pad[-1], *pts[-1]) if end_pad[-1] is not None and "plane" in end_pad[-1] else None
        def height(s_):
            y = h_at(s_)
            # blend into the pad plane over the first/last BLEND studs
            if y_start is not None and s_ < BLEND: y = y_start + (y - y_start) * (s_ / BLEND)
            if y_end is not None and total_len_e - s_ < BLEND: y = y_end + (y - y_end) * ((total_len_e - s_) / BLEND)
            return y
        for k in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[k], pts[k + 1]
            seg = math.hypot(bx - ax, bz - az)
            if seg < 1.0: continue
            ux, uz = (bx - ax) / seg, (bz - az) / seg
            n = max(1, int(math.ceil(seg / RP.SEGMENT)))
            for t_ in range(n):
                a0, a1 = seg * t_ / n, seg * (t_ + 1) / n
                s0, s1 = cum[k] + a0, cum[k] + a1
                px, pz = ax + ux * a0, az + uz * a0
                qx, qz = ax + ux * a1, az + uz * a1
                # a building edge the width check missed: salvage the slab --
                # narrow it, else slide it sideways, else split it in half and
                # retry each half (a whole 136-stud slab was dropped for one corner)
                def place(s0_, s1_, depth):
                    nonlocal total
                    L_ = s1_ - s0_
                    ax_, az_ = ax + ux * (s0_ - cum[k]), az + uz * (s0_ - cum[k])
                    bx_, bz_ = ax + ux * (s1_ - cum[k]), az + uz * (s1_ - cum[k])
                    mx_, mz_ = (ax_ + bx_) / 2, (az_ + bz_) / 2
                    best_ = None
                    for sh in (0.0, 4.0, -4.0, 8.0, -8.0, 12.0, -12.0):
                        ox_, oz_ = -uz * sh, ux * sh
                        sw_ = w
                        while sw_ >= MIN_W and not rect_clear(mx_ + ox_, mz_ + oz_, ux, uz, L_, sw_):
                            sw_ -= 2.0
                        if sw_ >= MIN_W and (best_ is None or sw_ > best_[0] + 4):
                            best_ = (sw_, ox_, oz_)
                        if best_ and best_[0] >= w:
                            break
                    if best_ is None or best_[0] < 0.5 * w and L_ > 24 and depth < 3:
                        if L_ > 24 and depth < 3:
                            mid_ = (s0_ + s1_) / 2
                            place(s0_, mid_ + 0.3, depth + 1)
                            place(mid_ - 0.3, s1_, depth + 1)
                            return
                        if best_ is None:
                            dropped["slab blocked (asphalt terrain shows there)"] += 1
                            return
                    sw_, ox_, oz_ = best_
                    y0_, y1_ = height(s0_), height(s1_)
                    emit("roadway", mx_ + ox_, (y0_ + y1_) / 2 + way["prio"] * 0.05, mz_ + oz_,
                         math.atan2(uz, ux), math.atan2(y1_ - y0_, L_), L_ + 0.6, RP.THICKNESS, sw_, way["kind"], way["id"])
                    total += L_
                place(s0, s1, 0)
            # a bend: one round joint, at the bend's own height, as wide as the street
            if k + 1 < len(pts) - 1:
                (cx2, cz2) = pts[k + 2]
                turn = math.atan2(cz2 - bz, cx2 - bx) - math.atan2(bz - az, bx - ax)
                if abs((turn + math.pi) % (2 * math.pi) - math.pi) >= math.radians(BEND_DEG):
                    dia = min(w, 2 * (clear_radius(bx, bz, w / 2 + MARGIN) - MARGIN))
                    if dia >= MIN_W:
                        emit("joint", bx, height(cum[k + 1]) + way["prio"] * 0.05 - 0.03, bz, 0.0, 0.0, dia,
                             RP.THICKNESS, dia, way["kind"], way["id"])

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
    if blocked_log:
        from collections import Counter
        blocked_log = [b for b in blocked_log if in_city(*b[3])]
        print("IN-CITY mostly-blocked streets:", len(blocked_log), Counter(b[0] for b in blocked_log).most_common())
        L = sorted(b[1] for b in blocked_log)
        print("  length median %.0f, p90 %.0f; examples:" % (L[len(L) // 2], L[int(len(L) * .9)]), [b for b in blocked_log if b[1] > 80][:6])
    if narrow_log:
        a = np.array(narrow_log)
        print("too-narrow streets: samples median %.0f | clearance median-of-medians %.1f | p15 median %.1f | share with median clearance >= MIN_W: %.0f%%"
              % (np.median(a[:, 0]), np.median(a[:, 1]), np.median(a[:, 2]), 100 * np.mean(a[:, 1] >= MIN_W)))


if __name__ == "__main__":
    main()
