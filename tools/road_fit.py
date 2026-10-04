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
JGAP = 2.0           # studs between a street's end and the widest street at its junction
DUP_SHARE = 0.5      # a slab more than this share already road is a parallel duplicate
ROAD_LIFT = 0.1      # studs the road top sits above the visible ground
SNAP = 2.0           # studs: road end heights snap to the terrain's render levels
STRAIGHTEN = 6.0     # studs: a street's polyline is simplified this hard -> long straight slabs
EVEN_SPAN = 40.0     # studs: heights are averaged over this span along a street
JRAMP = 0.1          # grade at which a street end ramps down to its junction's height
JDROP_MAX = 8.0      # ... but never by more than this
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

    # Road heights: the VISIBLE ground after tools/ground_clamp.py (buildings
    # never sunk), in world studs -- the same surface the terrain renders.
    gs = np.load(DATA / "ground_surface.npz")
    GS, gx0_, gz0_, gcell = gs["G"].astype(float), float(gs["x0"]), float(gs["z0"]), float(gs["cell"])
    GS = np.where(np.isnan(GS), np.nanmedian(GS), GS)
    # never above the road cap (a curb below the nearby ground floors)
    RCg = gs["RC"].astype(float)
    GS = np.minimum(GS, RCg)

    def road_cap(x, z):
        i = int(min(max((x - gx0_) / gcell, 0), RCg.shape[0] - 1))
        j = int(min(max((z - gz0_) / gcell, 0), RCg.shape[1] - 1))
        return float(RCg[i, j])

    def ground(x, z):
        fi = min(max((x - gx0_) / gcell - 0.5, 0), GS.shape[0] - 1.001)
        fj = min(max((z - gz0_) / gcell - 0.5, 0), GS.shape[1] - 1.001)
        i, j = int(fi), int(fj)
        u, v = fi - i, fj - j
        return float(GS[i, j] * (1 - u) * (1 - v) + GS[i + 1, j] * u * (1 - v)
                     + GS[i, j + 1] * (1 - u) * v + GS[i + 1, j + 1] * u * v)

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
    node_cluster = {}                                # junction node -> (cluster id, centre, spread)
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
        for n in members:
            node_cluster[n] = (id(pad), centre, spread)
        for f, k in touching:
            edge_trim[(id(f), k)] = (centre, pad)     # trimmed to the pad's FINAL size, if it survives
    print(f"{len(jn)} junction nodes -> {len(pads)} pads")

    # ---- 4. emit: ONE slab per straight run, full street width, no pads/joints
    # (owner, Oct 4: "one part per section of the road and only for its length,
    # not for its width"; intersections left as clean gaps for now)
    tiles, counts, total = defaultdict(list), defaultdict(int), 0.0
    dropped = defaultdict(int)

    def emit(kind, x, y, z, yaw, pitch, length, thick, width, cls, wid):
        if not in_city(x, z):
            dropped["outside the city"] += 1
            return False
        key = (int(math.floor(x / RP.TILE)), int(math.floor(z / RP.TILE)))
        tiles[key].append([kind, round(x, 2), round(y, 2), round(z, 2), round(yaw, 5), round(pitch, 5),
                           round(length, 2), round(thick, 2), round(width, 2), cls, wid])
        counts[kind] += 1
        return True

    def rect_clear(cx, cz, ux, uz, L, W, grow=1.0):
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

    # pass A: every street's straightened line and its one width
    streets = []
    for f in fitted:
        way = f["way"]
        pts = [np.array(q, float) for q in RP.simplify([tuple(q) for q in f["pts"]], STRAIGHTEN)]
        if len(pts) < 2:
            continue
        clear = []
        for k in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[k], pts[k + 1]
            seg = math.hypot(bx - ax, bz - az)
            if seg < 1.0:
                continue
            ux, uz = (bx - ax) / seg, (bz - az) / seg
            for a in np.arange(2.0, seg - 1.9, 4.0):
                sx, sz = ax + ux * a, az + uz * a
                clear.append(2 * min(side_clear(sx, sz, -uz, ux), side_clear(sx, sz, uz, -ux)) - 2 * MARGIN)
        open_ = [c_ for c_ in clear if c_ >= MIN_W]
        if not clear or len(open_) < max(2, 0.3 * len(clear)):
            dropped["street mostly under buildings"] += 1
            continue
        corridor = float(np.percentile(open_, 15))
        w = min(max(f["width"], corridor - 2 * SIDEWALK_BAND), WIDE_MAX, corridor)
        w = math.floor(w / 2) * 2
        if w < MIN_W:
            dropped["street too narrow"] += 1
            continue
        streets.append(dict(f=f, way=way, pts=pts, w=w, raw0=pts[0].copy(), raw1=pts[-1].copy()))

    # pass B: intersections are left as GAPS. A junction is a CLUSTER of OSM
    # nodes (a big crossing has many); every street ending in a cluster stops on
    # ONE circle around its centre -- trimming at each node separately left
    # tongues of different lengths side by side (Scramble Crossing)
    cl_w = defaultdict(float)
    for st in streets:
        for k in (0, -1):
            nid = st["f"]["a"] if k == 0 else st["f"]["b"]
            if nid in node_cluster:
                cl_w[node_cluster[nid][0]] = max(cl_w[node_cluster[nid][0]], st["w"])
    cl_info = {}
    for st in streets:
        pts = st["pts"]
        for k in (0, -1):
            if pts is None:
                break
            nid = st["f"]["a"] if k == 0 else st["f"]["b"]
            if nid not in node_cluster:
                continue
            cid, centre, spread = node_cluster[nid]
            R = cl_w[cid] / 2 + spread + JGAP
            cl_info[cid] = (centre, R)
            seq = list(pts) if k == 0 else list(pts[::-1])
            # drop points inside the circle, then cut the first segment at it
            while len(seq) >= 2 and np.hypot(*(seq[1] - centre)) <= R:
                seq = seq[1:]
            if len(seq) >= 2 and np.hypot(*(seq[0] - centre)) < R:
                a_, b_ = seq[0], seq[1]
                d_ = b_ - a_
                A = d_ @ d_; B = 2 * d_ @ (a_ - centre); C = (a_ - centre) @ (a_ - centre) - R * R
                disc = B * B - 4 * A * C
                if A > 1e-9 and disc >= 0:
                    tt = (-B + math.sqrt(disc)) / (2 * A)
                    seq = [a_ + d_ * min(max(tt, 0.0), 1.0)] + seq[1:]
            pts = (seq if k == 0 else seq[::-1]) if len(seq) >= 2 and np.hypot(*(seq[-1] - seq[0])) > 4 else None
        st["pts"] = pts
    node_w = {n: cl_w[node_cluster[n][0]] for n in node_cluster}

    # pass C: emit, most important streets first; a slab whose footprint is
    # already mostly road is a parallel duplicate (OSM draws each direction of
    # a divided road as its own way) and is dropped -> never two side by side
    covered = np.zeros((bnx, bnz), bool)
    cov_yaw = np.zeros((bnx, bnz), np.float32)       # direction of the road covering a cell

    def footprint_cells(cx, cz, ux, uz, L, W):
        out = []
        for a in np.arange(-L / 2, L / 2 + 0.01, 2.0):
            for b in np.arange(-W / 2, W / 2 + 0.01, 2.0):
                i, j = int((cx + ux * a - uz * b - bx0) / bcell), int((cz + uz * a + ux * b - bz0) / bcell)
                if 0 <= i < bnx and 0 <= j < bnz:
                    out.append((i, j))
        return out

    def street_profile(pts, w, cum, tl):
        ss = np.arange(0, tl + 0.1, 4.0)

        def at(s_, pts=pts, cum=cum):
            k_ = max(0, min(len(pts) - 2, int(np.searchsorted(cum, s_, side="right") - 1)))
            L_ = max(cum[k_ + 1] - cum[k_], 1e-6)
            return pts[k_] + (pts[k_ + 1] - pts[k_]) * ((s_ - cum[k_]) / L_)
        hs = np.array([ground(*at(s_)) for s_ in ss])
        # the cap at the centreline AND both slab edges: on a wide street the
        # buildings beside it are w/2 from the centreline
        def cap_at(s_):
            q, q2 = at(s_), at(min(s_ + 2.0, tl))
            q1 = at(max(s_ - 2.0, 0.0))
            tx, tz = q2 - q1
            n_ = math.hypot(tx, tz) or 1.0
            nx_, nz_ = -tz / n_ * w / 2, tx / n_ * w / 2
            return min(road_cap(q[0], q[1]), road_cap(q[0] + nx_, q[1] + nz_), road_cap(q[0] - nx_, q[1] - nz_))
        caps_ = np.array([cap_at(s_) for s_ in ss])
        win = max(1, int(EVEN_SPAN / 4.0))
        if len(hs) > 2:
            hs = np.convolve(np.pad(hs, win, mode="edge"), np.ones(2 * win + 1) / (2 * win + 1), mode="valid")
            # averaging must not lift the road above its cap anywhere along it
            hs = np.minimum(hs, caps_)
        return ss, hs, at

    def street_cum(pts):
        cum = [0.0]
        for k in range(len(pts) - 1):
            cum.append(cum[-1] + float(np.hypot(*(pts[k + 1] - pts[k]))))
        return cum, cum[-1]

    # junction heights: the lowest end arriving at each cluster (street ends
    # at one junction differed by a median 4, p90 10 studs)
    cl_end = defaultdict(list)
    for st in streets:
        if st["pts"] is None:
            continue
        cum, tl = street_cum(st["pts"])
        if tl < max(30.0, 0.8 * st["w"]):
            continue
        ss, hs, _ = street_profile(st["pts"], st["w"], cum, tl)
        for nid, h_ in ((st["f"]["a"], hs[0]), (st["f"]["b"], hs[-1])):
            if nid in node_cluster:
                cl_end[node_cluster[nid][0]].append(float(h_))
    j_h = {cid: min(v) for cid, v in cl_end.items() if len(v) >= 2}

    jdata = defaultdict(lambda: {"pts": [], "h": [], "ends": []})
    order = sorted([s_ for s_ in streets if s_["pts"] is not None], key=lambda s_: (-s_["way"]["prio"], -s_["w"]))
    for st in order:
        pts, w, way = st["pts"], st["w"], st["way"]
        cum = [0.0]
        for k in range(len(pts) - 1):
            cum.append(cum[-1] + float(np.hypot(*(pts[k + 1] - pts[k]))))
        tl = cum[-1]
        if tl < 6:
            dropped["street shorter than its gaps"] += 1
            continue
        # a STUB between two junctions -- shorter than about its own width -- is
        # part of the junction, not a street: the asphalt ground covers it
        if tl < max(30.0, 0.8 * w):
            dropped["stub between junctions"] += 1
            continue
        ss, hs, at = street_profile(pts, w, cum, tl)
        # every street meeting a junction arrives at the junction's ONE height
        # (its lowest arriving end), ramping down to it -- lowering only
        for nid, s_end in ((st["f"]["a"], 0.0), (st["f"]["b"], tl)):
            if nid in node_cluster and node_cluster[nid][0] in j_h:
                jh_ = j_h[node_cluster[nid][0]]
                # a street ending on a cliff above the junction keeps its height
                # (ramping 34 studs down dug a trench up the hill)
                if float(np.interp(s_end, ss, hs)) - jh_ <= JDROP_MAX:
                    hs = np.minimum(hs, jh_ + JRAMP * np.abs(ss - s_end))

        def height(s_, ss=ss, hs=hs):
            # snapped to the terrain's render levels: flat smooth terrain can
            # only render on even heights, so a road end anywhere between met
            # the ground with a 0-2 stud step (median 0.74, p90 2.7)
            return math.floor(float(np.interp(s_, ss, hs)) / SNAP) * SNAP
        built_before = counts["roadway"]
        # a street whose centreline is mostly on road already built is the other
        # half of a dual carriageway (or a parallel OSM duplicate): drop it whole
        on_road = n_samp = 0
        for s_ in np.arange(0, tl, 4.0):
            q = at(s_)
            i_, j_ = int((q[0] - bx0) / bcell), int((q[1] - bz0) / bcell)
            if 0 <= i_ < bnx and 0 <= j_ < bnz:
                n_samp += 1
                on_road += covered[i_, j_]
        if n_samp and on_road > 0.5 * n_samp:
            dropped["parallel duplicate street"] += 1
            continue
        # ALONGSIDE an already built parallel street (a gap of a few studs between
        # two slabs): drop it, the asphalt ground covers the space -- never two
        # slabs side by side
        beside = n_b = 0
        for s_ in np.arange(2.0, tl - 1.9, 6.0):
            q = at(s_)
            q2 = at(min(s_ + 2.0, tl))
            dvec = q2 - q
            if np.hypot(*dvec) < 1e-6:
                continue
            ux_, uz_ = dvec / np.hypot(*dvec)
            yaw_ = math.atan2(uz_, ux_)
            n_b += 1
            hit_ = False
            for side in (1, -1):
                for off in (w / 2 + 3, w / 2 + 8):
                    x_, z_ = q[0] - uz_ * off * side, q[1] + ux_ * off * side
                    i_, j_ = int((x_ - bx0) / bcell), int((z_ - bz0) / bcell)
                    if 0 <= i_ < bnx and 0 <= j_ < bnz and covered[i_, j_] and abs(math.sin(cov_yaw[i_, j_] - yaw_)) < 0.34:
                        hit_ = True
            beside += hit_
        if n_b and beside > 0.6 * n_b:
            dropped["alongside a parallel street"] += 1
            continue

        for k in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[k], pts[k + 1]
            seg = math.hypot(bx - ax, bz - az)
            if seg < 1.0:
                continue
            ux, uz = (bx - ax) / seg, (bz - az) / seg
            # close the outside of a bend: extend into the corner by w/2*tan(turn/2)
            ext0 = ext1 = 0.0
            if k > 0:
                (px_, pz_) = pts[k - 1]
                tn = abs((math.atan2(az - pz_, ax - px_) - math.atan2(uz, ux) + math.pi) % (2 * math.pi) - math.pi)
                ext0 = min(w / 2 * math.tan(tn / 2), w / 2)
            if k + 1 < len(pts) - 1:
                (cx2, cz2) = pts[k + 2]
                tn = abs((math.atan2(cz2 - bz, cx2 - bx) - math.atan2(uz, ux) + math.pi) % (2 * math.pi) - math.pi)
                ext1 = min(w / 2 * math.tan(tn / 2), w / 2)
            n = max(1, int(math.ceil(seg / RP.SEGMENT)))
            for t_ in range(n):
                s0 = cum[k] + seg * t_ / n - (ext0 if t_ == 0 else 0.0)
                s1 = cum[k] + seg * (t_ + 1) / n + (ext1 if t_ == n - 1 else 0.0)
                stack = [(s0, s1, 0)]
                while stack:
                    s0_, s1_, depth = stack.pop()
                    L_ = s1_ - s0_
                    ax_, az_ = ax + ux * (s0_ - cum[k]), az + uz * (s0_ - cum[k])
                    bx_, bz_ = ax + ux * (s1_ - cum[k]), az + uz * (s1_ - cum[k])
                    mx_, mz_ = (ax_ + bx_) / 2, (az_ + bz_) / 2
                    sw_ = w
                    while sw_ >= MIN_W and not rect_clear(mx_, mz_, ux, uz, L_, sw_):
                        sw_ -= 2.0
                    # no splitting into fragments: a slab that cannot keep most of
                    # its width is dropped; the asphalt ground shows there
                    if sw_ < max(MIN_W, 0.6 * w):
                        dropped["slab blocked (asphalt terrain shows there)"] += 1
                        continue
                    cells_ = footprint_cells(mx_, mz_, ux, uz, L_, sw_)
                    if cells_ and sum(covered[c_] for c_ in cells_) > DUP_SHARE * len(cells_):
                        dropped["parallel duplicate"] += 1
                        continue
                    # heights at the bend VERTICES, extrapolated along the slab's grade
                    # into the corner extensions: both slabs meeting at a bend pass
                    # through the same height there (ends taken at the extended
                    # stations stepped by up to 8 studs on hills)
                    se0 = s0_ + (ext0 if t_ == 0 else 0.0)
                    se1 = s1_ - (ext1 if t_ == n - 1 else 0.0)
                    ya_, yb_ = height(max(se0, 0)), height(min(se1, tl))
                    gr_ = (yb_ - ya_) / max(se1 - se0, 1e-6)
                    y0_, y1_ = ya_ - gr_ * (se0 - s0_), yb_ + gr_ * (s1_ - se1)
                    lift = 0.04 * (k % 2)     # slabs overlapping at a bend never z-fight
                    if emit("roadway", mx_, (y0_ + y1_) / 2 + ROAD_LIFT + lift, mz_, math.atan2(uz, ux),
                            math.atan2(y1_ - y0_, L_), L_, RP.THICKNESS, sw_, way["kind"], way["id"]):
                        for c_ in cells_:
                            covered[c_] = True
                            cov_yaw[c_] = math.atan2(uz, ux)
                        total += L_
        if counts["roadway"] > built_before:
            for nid, rawp, s_end in ((st["f"]["a"], st["raw0"], 0.0), (st["f"]["b"], st["raw1"], tl)):
                if nid in junction:
                    jdata[nid]["pts"].append(rawp)
                    jdata[nid]["h"].append(height(s_end) + ROAD_LIFT)
                    e_ = pts[0] if s_end == 0.0 else pts[-1]
                    jdata[nid]["ends"].append([round(float(e_[0]), 1), round(float(e_[1]), 1),
                                               round(height(s_end) + ROAD_LIFT, 2)])

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
    # junctions: no parts -- a flat patch of asphalt TERRAIN at the streets'
    # height, graded by RoadBuilder.GradeCorridors, joins the street ends
    junctions = []
    cl_h = defaultdict(list)
    cl_ends = defaultdict(list)
    for nid, jd in jdata.items():
        if nid in node_cluster:
            cl_h[node_cluster[nid][0]].extend(jd["h"])
            cl_ends[node_cluster[nid][0]].extend(jd["ends"])
    for cid, hs_ in cl_h.items():
        if len(hs_) < 2 or cid not in cl_info:
            continue
        centre, R = cl_info[cid]
        if not in_city(float(centre[0]), float(centre[1])):
            continue
        junctions.append([round(float(centre[0]), 1), round(float(centre[1]), 1), round(R + 3, 1),
                          round(math.floor(j_h[cid] / SNAP) * SNAP + ROAD_LIFT, 2) if cid in j_h else
                          round(round((float(np.mean(hs_)) - ROAD_LIFT) / SNAP) * SNAP + ROAD_LIFT, 2),
                          cl_ends[cid]])   # the street ends: the patch slopes between them
    (out / "junctions.json").write_text(json.dumps(junctions))
    print(f"{len(junctions)} junction patches (terrain, no parts)")
    print(f"{counts['roadway']} road slabs over {len(names)} tiles; {total / 4.182937 / 1000:.1f} km of street")
    print(f"road area over a ground floor: {on / max(tot, 1):.2%}  (plain OSM was 11.2%)")
    print("dropped:", dict(dropped))


if __name__ == "__main__":
    main()
