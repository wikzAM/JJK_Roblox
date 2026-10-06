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
JRAMP = 0.15         # grade at which a street end ramps down to its junction's height
JDROP_MAX = 24.0     # ... but never by more than this
JPICK = 10.0         # a junction's height: its lowest end within this of its highest
CLASH_H = 1.0        # studs: two streets' slabs may overlap only this close in height
CLASH_NEAR = 3.0     # ... and lie within 4 studs of each other only this close
CAP_GRADE = 0.2      # rise per stud at which a street's cap eases out of a dip
MAX_SLAB_GRADE = 0.2  # rise per stud: steeper streets are stairs, left as ground
CENTRE_ITER = 2      # small streets: centring passes
CENTRE_MAX = 24.0    # ... studs a segment may move in one pass
LANE_SMALL_M = 3.25  # metres per lane on a small street
SHOULDER_M = 1.0     # ... plus this (2 lanes = 7.5 m, one-way 1 lane = 4.25 m)
SIDE_TARGET_M = 3.0  # metres of sidewalk kept off a building face when only one side has buildings
SCAN_C = 120.0       # studs: how far across a small street the building faces are looked for
SIDE_MIN_M = 1.0     # metres: narrower than lanes + two of these, a small street is wall to wall
SIDE_MAX = 40.0      # studs: the widest sidewalk slab (~9.5 m)
SIDE_MIN_W = 3.0     # ... and the narrowest
MOUTH = 8.0          # studs: another road this close beside a street is a mouth, no sidewalk
SIDE_MIN_L = 16.0    # studs: shorter sidewalk pieces are left out
SIDE_STEP = 3.0      # studs the face reach may vary within one sidewalk slab
SIDE_OPEN_M = 3.0    # metres of sidewalk where no building face is within SIDE_MAX
CURB = 0.5           # studs a sidewalk stands above its street (at least)
SIDE_RISE = 4.0      # ... and at most
SIDE_BELOW = 1.0     # studs a sidewalk stays under the floor it runs along
ALLEY_KINDS = {"service", "footway"}
ALLEY_M = 4.0        # metres: an alley's nominal width
ALLEY_MAX = 48.0     # studs: an alley's corridor (wall to wall) is at most this
ALLEY_SHARE = 0.6    # ... over this share of its readings
ALLEY_MIN_L = 30.0   # studs: shorter alley stretches are left out
INF_HALF = (5.0, 24.0)  # studs from a building face an inferred alley's centre lies
INF_CLEAR = 12.0     # studs an inferred alley keeps from the streets
INF_MIN_L = 40.0     # studs: shorter ridge runs are left out
INF_ASPECT = 3.0     # an inferred alley is at least this many times longer than wide
INF_STRAIGHT = 2.0   # studs: a run wobbling more than this is not one straight alley
SPLIT_DEV = 1.0      # studs a slab may ride over its street's capped profile before it is split
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
        # ALLEYS (Oct 6): service / footway ways become candidate alleys -- kept only
        # where they run between buildings (pass A), coloured orange for checking
        alley = kind in ALLEY_KINDS and tags.get("footway") not in ("sidewalk", "crossing")             and tags.get("service") not in ("parking_aisle", "drive-through", "parking")
        if not w.get("geometry") or ((kind not in RP.KIND or kind in DROP_KINDS) and not alley):
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
        road_m, _, prio = (ALLEY_M, 0.0, -1) if alley else RP.KIND[kind]
        oneway = tags.get("oneway") in ("yes", "-1")
        if tags.get("lanes", "").isdigit():
            # on a one-way way, lanes counts only its own direction
            road_m = int(tags["lanes"]) * RP.LANE_M + 1.0 if oneway else max(road_m, int(tags["lanes"]) * RP.LANE_M + 1.0)
        elif oneway and kind in ("trunk", "primary", "secondary", "tertiary"):
            # one half of a dual carriageway: OSM draws each direction as its own
            # way, and both at the full road width stacked into each other
            road_m /= 2
        pts = [to_studs(p["lat"], p["lon"]) for p in w["geometry"]]
        lanes_tag = int(tags["lanes"]) if tags.get("lanes", "").isdigit() else None
        ways.append(dict(id=w["id"], kind=kind, prio=prio, width=road_m * s, nodes=w["nodes"], pts=pts,
                         lanes=lanes_tag, oneway=oneway, alley=alley))
    uses = defaultdict(int)
    for w in ways:
        if w["alley"]:
            continue          # alleys never split the streets into more pieces
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

    def emit(kind, x, y, z, yaw, pitch, length, thick, width, cls, wid, small=False, tag=None):
        if not in_city(x, z):
            dropped["outside the city"] += 1
            return False
        key = (int(math.floor(x / RP.TILE)), int(math.floor(z / RP.TILE)))
        tiles[key].append([kind, round(x, 2), round(y, 2), round(z, 2), round(yaw, 5), round(pitch, 5),
                           round(length, 2), round(thick, 2), round(width, 2), cls, wid]
                          + ([0, True] if small else []) + ([tag] if small and tag else []))
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

    # SMALL streets (2 lanes or fewer; owner, Oct 6: "so many of the roads lean to one
    # way or the other ... the roads need to be in the center of the buildings,
    # properly sized, and then have properly sized sidewalks"). Each straight
    # segment is moved to the middle of the open run between the building faces on
    # its two sides (median over samples every 4 studs, both sides bounded within
    # SCAN), the vertices rebuilt as the meeting points of the moved segments.
    def is_small(way):
        if way.get("alley"):
            return True
        if way["kind"] in ("residential", "unclassified", "living_street", "pedestrian"):
            return True
        return way["kind"] == "tertiary" and (way["lanes"] or 2) <= 2

    CSTAT = defaultdict(int)

    # the faces a small street is centred between: the live buildings AND the
    # PLATEAU FBX ones (tools/fbx_mask.py) -- a real building missing from the map
    # still marks where the street's edge is (owner: verify against the FBX)
    fbm = np.load(DATA / "fbx_footprints.npz")["mask"] if (DATA / "fbx_footprints.npz").exists() else None
    face_mask = blocked | fbm if fbm is not None and fbm.shape == blocked.shape else blocked

    def is_face(x, z):
        i, j = int((x - bx0) / bcell), int((z - bz0) / bcell)
        return not (0 <= i < bnx and 0 <= j < bnz) or bool(face_mask[i, j])

    def reach_c(x, z, nxv, nzv):
        r_ = 0.0
        while r_ < SCAN_C and not is_face(x + nxv * (r_ + 1), z + nzv * (r_ + 1)):
            r_ += 1.0
        return r_

    def seg_readings(a, b):
        seg = float(np.hypot(*(b - a)))
        if seg < 1.0:
            return [], None
        u = (b - a) / seg
        nrm = np.array([-u[1], u[0]])
        out = []
        for s_ in np.arange(2.0, seg - 1.9, 4.0):
            q = a + u * s_
            base = 0.0
            if is_face(q[0], q[1]):
                # the OSM line runs through a building (OSM is up to ~11 m off):
                # the nearest open ground across it, within CENTRE_MAX
                base = None
                for d_ in np.arange(1.0, CENTRE_MAX + 0.1, 1.0):
                    for sg in (1.0, -1.0):
                        if not is_face(q[0] + nrm[0] * d_ * sg, q[1] + nrm[1] * d_ * sg):
                            base = d_ * sg
                            break
                    if base is not None:
                        break
                if base is None:
                    continue
                q = q + nrm * base
            out.append((reach_c(q[0], q[1], nrm[0], nrm[1]) + base, reach_c(q[0], q[1], -nrm[0], -nrm[1]) - base))
        return out, nrm

    def sample_offset(L, R, w):
        """Sideways move (toward the L side) that centres the street at this reading."""
        if L < SCAN_C and R < SCAN_C:
            return (L - R) / 2                      # buildings both sides: the middle
        want = w / 2 + SIDE_TARGET_M * s           # one side only: a sidewalk off that face
        if L < SCAN_C:
            return min(L - want, 0.0)               # only ever AWAY from the building
        if R < SCAN_C:
            return max(want - R, 0.0)
        return None

    def centre_line(pts, w):
        P = [np.array(q, float) for q in pts]
        for _ in range(CENTRE_ITER):
            offs, nrms = [], []
            for k in range(len(P) - 1):
                rd, nrm = seg_readings(P[k], P[k + 1])
                if nrm is None:
                    nrm = nrms[-1] if nrms else np.array([0.0, 1.0])
                os_ = [o_ for o_ in (sample_offset(L, R, w) for L, R in rd) if o_ is not None]
                o = float(np.median(os_)) if len(os_) >= 3 else 0.0
                CSTAT['few' if len(rd) < 3 else ('open' if len(os_) < 3 else ('moved' if abs(o) > 0.5 else 'centred'))] += 1
                offs.append(max(-CENTRE_MAX, min(CENTRE_MAX, o)))
                nrms.append(nrm)
            Q = [P[0] + nrms[0] * offs[0]]
            for j in range(1, len(P) - 1):
                a1, d1 = P[j - 1] + nrms[j - 1] * offs[j - 1], P[j] - P[j - 1]
                a2, d2 = P[j] + nrms[j] * offs[j], P[j + 1] - P[j]
                cr = d1[0] * d2[1] - d1[1] * d2[0]
                if abs(cr) < 1e-3 * np.hypot(*d1) * np.hypot(*d2):
                    Q.append(P[j] + (nrms[j - 1] * offs[j - 1] + nrms[j] * offs[j]) / 2)
                else:
                    tt = ((a2 - a1)[0] * d2[1] - (a2 - a1)[1] * d2[0]) / cr
                    Q.append(a1 + d1 * tt)
            Q.append(P[-1] + nrms[-1] * offs[-1])
            P = Q
        widths = []
        for k in range(len(P) - 1):
            rd, _ = seg_readings(P[k], P[k + 1])
            widths += [L + R for L, R in rd if L < SCAN_C and R < SCAN_C]
        return P, widths

    def lanes_width(way):
        lanes = way["lanes"] or (1 if way["oneway"] else 2)
        return (min(lanes, 2) * LANE_SMALL_M + SHOULDER_M) * s

    def small_width(way, widths):
        lanes_w = lanes_width(way)
        if not widths:
            return math.floor(lanes_w / 2) * 2
        c = float(np.percentile(widths, 25))
        if way["kind"] == "pedestrian":
            w = c - 2 * MARGIN                      # a pedestrian street is wall to wall
        elif c >= lanes_w + 2 * SIDE_MIN_M * s:
            # room for the lanes and both sidewalks: the street takes what a 3 m
            # sidewalk each side leaves, at least its lanes, at most two lanes (a
            # one-way 14-stud lane in a 60-stud corridor left 23-stud sidewalks)
            two = (2 * LANE_SMALL_M + SHOULDER_M) * s
            w = min(max(c - 2 * SIDE_TARGET_M * s, lanes_w), max(two, lanes_w))
        else:
            w = c - 2 * MARGIN                      # an alley: the street is the whole gap
        return math.floor(max(w, 0.0) / 2) * 2

    # pass A: every street's straightened line and its one width
    streets = []
    centred = []
    narrow_dbg = []
    for f in fitted:
        way = f["way"]
        pts = [np.array(q, float) for q in RP.simplify([tuple(q) for q in f["pts"]], STRAIGHTEN)]
        if len(pts) < 2:
            continue
        if is_small(way):
            pts0 = [q.copy() for q in pts]
            pts, widths = centre_line(pts, lanes_width(way))
            w = small_width(way, widths)
            if way.get("alley"):
                n_rd = sum(len(seg_readings(np.array(pts[k_], float), np.array(pts[k_ + 1], float))[0])
                           for k_ in range(len(pts) - 1))
                tight = [c_ for c_ in widths if c_ <= ALLEY_MAX]
                if n_rd == 0 or len(tight) < ALLEY_SHARE * n_rd:
                    dropped["alley not between buildings"] += 1
                    continue
                w = math.floor(min(float(np.percentile(tight, 25)) - 2 * MARGIN, (2 * LANE_SMALL_M + SHOULDER_M) * s) / 2) * 2
            if w < MIN_W:
                dropped["street too narrow"] += 1
                narrow_dbg.append([[round(float(q[0]), 1), round(float(q[1]), 1)] for q in pts0])
                continue
            centred.append(max(float(np.hypot(*(a_ - b_))) for a_, b_ in zip(pts, pts0)))
            streets.append(dict(f=f, way=way, pts=pts, w=w, small=True, raw0=pts[0].copy(), raw1=pts[-1].copy()))
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
        streets.append(dict(f=f, way=way, pts=pts, w=w, small=False, raw0=pts[0].copy(), raw1=pts[-1].copy()))
    (DATA / "narrow_dropped.json").write_text(json.dumps(narrow_dbg))
    if centred:
        print("centring segments:", dict(CSTAT))
        print(f"{len(centred)} small streets centred: moved median {np.median(centred):.1f}, p90 {np.percentile(centred, 90):.1f} studs")

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
    cov_h = np.zeros((bnx, bnz), np.float32)         # ... its surface height
    cov_way = np.zeros((bnx, bnz), np.int64)         # ... and its OSM way

    def height_clash(cx, cz, ux, uz, L, W, ymid, grade, wid):
        # overlapping at a different height, or right BESIDE another street's
        # slab at a very different one (a 16-stud cliff between two slabs let the
        # high one's ground spill over the low one)
        return height_clash1(cx, cz, ux, uz, L, W, ymid, grade, wid, CLASH_H) or             height_clash1(cx, cz, ux, uz, L + 8, W + 8, ymid, grade, wid, CLASH_NEAR)

    def height_clash1(cx, cz, ux, uz, L, W, ymid, grade, wid, tol):
        # another street's slab already covers part of this one at a different
        # height: overlapping, the lower one showed terrain through it (steps of 8)
        for a in np.arange(-L / 2, L / 2 + 0.01, 2.0):
            for b in np.arange(-W / 2, W / 2 + 0.01, 2.0):
                i, j = int((cx + ux * a - uz * b - bx0) / bcell), int((cz + uz * a + ux * b - bz0) / bcell)
                if 0 <= i < bnx and 0 <= j < bnz and covered[i, j] and cov_way[i, j] != wid                         and abs(float(cov_h[i, j]) - (ymid + a * grade)) > tol:
                    return True
        return False

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
        # a low floor beside the street pulls its cap down sharply (the floors
        # within 8 studs apply exactly): the cap eases into such a dip at CAP_GRADE
        # so the road starts down in time instead of a slab riding over the dip
        for i_ in range(1, len(caps_)):
            caps_[i_] = min(caps_[i_], caps_[i_ - 1] + CAP_GRADE * 4.0)
        for i_ in range(len(caps_) - 2, -1, -1):
            caps_[i_] = min(caps_[i_], caps_[i_ + 1] + CAP_GRADE * 4.0)
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
        for nid, h_, e_ in ((st["f"]["a"], hs[0], st["pts"][0]), (st["f"]["b"], hs[-1], st["pts"][-1])):
            if nid in node_cluster:
                cl_end[node_cluster[nid][0]].append((float(h_), float(e_[0]), float(e_[1])))
    # the lowest end, but no lower than JDROP_MAX under the highest: a valley
    # street 42 under a hill junction (a stair) pulled it into a hole
    def pick_j(v):
        # the lowest end every higher end can ramp down to (ends under it: cliffs)
        hs_ = sorted(e[0] for e in v)
        # (within JPICK of the highest: a stray end 24 under pulled hill junctions
        # down into trenches)
        return next(h for h in hs_ if hs_[-1] - h <= JPICK)
    j_h = {cid: pick_j(v) for cid, v in cl_end.items() if len(v) >= 2}
    # ...and never above the road cap on the junction's own surface -- the lines
    # from its centre to the street ends that join it (not cliff ends): a corner
    # building lower than the streets arriving left a pit between road ends over
    # its floor (owner: roads under every floor around). Sampling the whole circle
    # reached down the hill to the valley street's buildings.
    for cid in list(j_h):
        if cid in cl_info:
            (jx, jz), _R = cl_info[cid]
            caps_j = [road_cap(jx, jz)]
            for eh, ex, ez in cl_end[cid]:
                if eh >= j_h[cid] - JPICK:      # the ends that join it, not the cliff ones
                    caps_j += [road_cap(jx + (ex - jx) * f, jz + (ez - jz) * f) for f in (0.25, 0.5, 0.75, 1.0)]
            j_h[cid] = min(j_h[cid], min(caps_j))

    jdata = defaultdict(lambda: {"pts": [], "h": [], "ends": []})
    order = sorted([s_ for s_ in streets if s_["pts"] is not None], key=lambda s_: (-s_["way"]["prio"], -s_["w"]))
    for st in order:
        pts, w, way = st["pts"], st["w"], st["way"]
        if way.get("alley"):
            # an alley stops where it meets a street: its longest stretch clear of
            # the roads already built (they come first), 3 studs short of them
            P_ = [np.array(q, float) for q in pts]
            dens = []
            for k_ in range(len(P_) - 1):
                seg_ = float(np.hypot(*(P_[k_ + 1] - P_[k_])))
                if seg_ < 1e-6:
                    continue
                u_ = (P_[k_ + 1] - P_[k_]) / seg_
                nrm_ = np.array([-u_[1], u_[0]])
                for s_ in np.arange(0.0, seg_, 2.0):
                    q_ = P_[k_] + u_ * s_
                    hit_ = False
                    for b_ in np.arange(-w / 2 - 3, w / 2 + 3.01, 2.0):
                        i_, j_ = int((q_[0] + nrm_[0] * b_ - bx0) / bcell), int((q_[1] + nrm_[1] * b_ - bz0) / bcell)
                        if 0 <= i_ < bnx and 0 <= j_ < bnz and covered[i_, j_]:
                            hit_ = True
                            break
                    dens.append((q_, hit_))
            best_, cur_ = [], []
            for q_, h_ in dens:
                if h_:
                    if len(cur_) > len(best_): best_ = cur_
                    cur_ = []
                else:
                    cur_.append(q_)
            if len(cur_) > len(best_): best_ = cur_
            if len(best_) * 2.0 < ALLEY_MIN_L:
                dropped["alley too short between streets"] += 1
                continue
            pts = [best_[0]] + [q_ for q_ in P_ if any(np.hypot(*(q_ - b2_)) < 1.0 for b2_ in best_[1:-1])] + [best_[-1]]
            pts = [np.array(q, float) for q in RP.simplify([tuple(q) for q in pts], STRAIGHTEN)]
            if len(pts) < 2:
                continue
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
                    # heights at the bend VERTICES, extrapolated along the slab's grade
                    # into the corner extensions: both slabs meeting at a bend pass
                    # through the same height there (ends taken at the extended
                    # stations stepped by up to 8 studs on hills)
                    se0 = s0_ + (ext0 if (t_ == 0 and s0_ == s0) else 0.0)
                    se1 = s1_ - (ext1 if (t_ == n - 1 and s1_ == s1) else 0.0)
                    ya_, yb_ = height(max(se0, 0)), height(min(se1, tl))
                    gr_ = (yb_ - ya_) / max(se1 - se0, 1e-6)
                    y0_, y1_ = ya_ - gr_ * (se0 - s0_), yb_ + gr_ * (s1_ - se1)
                    # a straight slab cannot follow a dip in the (capped) profile:
                    # where the profile falls more than SPLIT_DEV under the slab's
                    # line it is split at the worst point (a 190-stud slab rode 11
                    # studs over a low building's floor in its middle)
                    st_ = np.arange(max(se0, 0.0), min(se1, tl) + 0.01, 4.0)
                    if len(st_) > 2:
                        dev_ = (ya_ + gr_ * (st_ - se0)) - np.interp(st_, ss, hs)
                        piece = 30.0
                        okm = (st_ - s0_ >= piece) & (s1_ - st_ >= piece)
                        if dev_.max() > SPLIT_DEV and okm.any() and depth < 4:
                            sm_ = float(st_[okm][np.argmax(np.where(okm, dev_, -1e9)[okm])])
                            stack.append((sm_, s1_, depth + 1))
                            stack.append((s0_, sm_, depth + 1))
                            continue
                    ymid_ = (y0_ + y1_) / 2 + ROAD_LIFT
                    sw_ = w
                    while sw_ >= MIN_W and (not rect_clear(mx_, mz_, ux, uz, L_, sw_)
                                            or height_clash(mx_, mz_, ux, uz, L_, sw_, ymid_, gr_, way["id"])):
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
                    # a steep slab (a stair street: 0.18 rise per stud) sits on a ground the
                    # terrain cannot render under it -- the hillside poked through its top
                    if abs(gr_) > MAX_SLAB_GRADE:
                        dropped["too steep for a slab (stairs)"] += 1
                        continue
                    lift = 0.04 * (k % 2)     # slabs overlapping at a bend never z-fight
                    if emit("roadway", mx_, (y0_ + y1_) / 2 + ROAD_LIFT + lift, mz_, math.atan2(uz, ux),
                            math.atan2(y1_ - y0_, L_), L_, RP.THICKNESS, sw_, way["kind"], way["id"], st["small"],
                            "alley" if way.get("alley") else None):
                        for c_ in cells_:
                            covered[c_] = True
                            cov_yaw[c_] = math.atan2(uz, ux)
                            cov_way[c_] = way["id"]
                            # surface height at this cell (its station along the slab)
                            a_c = (bx0 + (c_[0] + 0.5) * bcell - mx_) * ux + (bz0 + (c_[1] + 0.5) * bcell - mz_) * uz
                            cov_h[c_] = ymid_ + a_c * gr_
                        total += L_
        if counts["roadway"] > built_before:
            for nid, rawp, s_end in ((st["f"]["a"], st["raw0"], 0.0), (st["f"]["b"], st["raw1"], tl)):
                if nid in junction:
                    jdata[nid]["pts"].append(rawp)
                    jdata[nid]["h"].append(height(s_end) + ROAD_LIFT)
                    e_ = pts[0] if s_end == 0.0 else pts[-1]
                    d_ = (pts[0] - pts[1]) if s_end == 0.0 else (pts[-1] - pts[-2])   # into the junction
                    d_ = d_ / (np.hypot(*d_) or 1.0)
                    jdata[nid]["ends"].append([round(float(e_[0]), 1), round(float(e_[1]), 1),
                                               round(height(s_end) + ROAD_LIFT, 2),
                                               round(float(d_[0]), 4), round(float(d_[1]), 4), w])

    # ---- a lone slab not much longer than it is wide (what is left of a street between
    # a junction circle and a blocked stretch) reads as a stray rectangle in the
    # asphalt, not a road (Scramble Crossing): dropped, the asphalt ground covers it
    ends_by_way = defaultdict(list)
    for rows in tiles.values():
        for r in rows:
            _, cx_, _, cz_, yaw_, _, L, _, W = r[:9]
            for sg in (-1, 1):
                ends_by_way[r[10]].append((cx_ + sg * math.cos(yaw_) * L / 2, cz_ + sg * math.sin(yaw_) * L / 2, id(r)))
    for key in list(tiles):
        keep = []
        for r in tiles[key]:
            _, cx_, _, cz_, yaw_, _, L, _, W = r[:9]
            if L < 1.5 * W:
                mine = [(cx_ + sg * math.cos(yaw_) * L / 2, cz_ + sg * math.sin(yaw_) * L / 2) for sg in (-1, 1)]
                # an end is joined when a slab of its street or a junction circle
                # is there; a short slab joining two junctions is a real street
                def joined(m):
                    return any(e[2] != id(r) and math.hypot(e[0] - m[0], e[1] - m[1]) < W / 2
                               for e in ends_by_way[r[10]]) or                         any(math.hypot(c_[0] - m[0], c_[1] - m[1]) < R_ + 6 for c_, R_ in cl_info.values())
                if not (joined(mine[0]) and joined(mine[1])):
                    dropped["lone slab under 1.5x its width"] += 1
                    counts["roadway"] -= 1
                    continue
            keep.append(r)
        tiles[key] = keep

    # ---- JUNCTION PLATES: one flat part per junction at its height, the rectangle
    # (along the widest street) bounding the end edges of the streets that arrive
    # at that height; shrunk off buildings and other streets' slabs
    plates = 0
    pl_ends = defaultdict(list)
    for nid, jd in jdata.items():
        if nid in node_cluster:
            pl_ends[node_cluster[nid][0]].extend(jd["ends"])
    for cid, ends in pl_ends.items():
        if cid not in j_h or cid not in cl_info:
            continue
        centre, _R = cl_info[cid]
        if not in_city(float(centre[0]), float(centre[1])):
            continue
        top = math.floor(j_h[cid] / SNAP) * SNAP + ROAD_LIFT
        ends = [e for e in ends if abs(e[2] - top) <= 1.0]
        if len(ends) < 2:
            continue
        wide = max(ends, key=lambda e: e[5])
        ux, uz = wide[3], wide[4]
        nx_, nz_ = -uz, ux
        A, B = [], []
        for ex, ez, _eh, tx, tz, ew in ends:
            for sg in (-1, 1):
                qx, qz = ex - tz * ew / 2 * sg, ez + tx * ew / 2 * sg
                A.append((qx - centre[0]) * ux + (qz - centre[1]) * uz)
                B.append((qx - centre[0]) * nx_ + (qz - centre[1]) * nz_)
        a0, a1, b0, b1 = min(A), max(A), min(B), max(B)
        area0 = (a1 - a0) * (b1 - b0)
        if area0 < 16:
            continue

        def rect(a0, a1, b0, b1):
            ca, cb = (a0 + a1) / 2, (b0 + b1) / 2
            return (centre[0] + ux * ca + nx_ * cb, centre[1] + uz * ca + nz_ * cb, a1 - a0, b1 - b0)
        # the starting rectangle sampled once (1 stud): a building, or another
        # street's slab at a different height, is BAD; then the side whose trim
        # removes the most bad points is trimmed, until none is left
        GA, GB = np.meshgrid(np.arange(a0 - 1, a1 + 1.01, 1.0), np.arange(b0 - 1, b1 + 1.01, 1.0), indexing="ij")
        I_ = ((centre[0] + ux * GA + nx_ * GB - bx0) / bcell).astype(int)
        J_ = ((centre[1] + uz * GA + nz_ * GB - bz0) / bcell).astype(int)
        in_ = (I_ >= 0) & (I_ < bnx) & (J_ >= 0) & (J_ < bnz)
        Ic, Jc = np.clip(I_, 0, bnx - 1), np.clip(J_, 0, bnz - 1)
        bad = ~in_ | blocked[Ic, Jc] | (covered[Ic, Jc] & (np.abs(cov_h[Ic, Jc] - top) > CLASH_H))
        # ...or under the road cap (a floor nearby lower than the plate)
        Ri = np.clip(((centre[0] + ux * GA + nx_ * GB - gx0_) / gcell).astype(int), 0, RCg.shape[0] - 1)
        Rk = np.clip(((centre[1] + uz * GA + nz_ * GB - gz0_) / gcell).astype(int), 0, RCg.shape[1] - 1)
        bad |= RCg[Ri, Rk] < top - 0.25
        BA, BB = GA[bad], GB[bad]

        def nbad(r_):
            return int(np.count_nonzero((BA >= r_[0] - 1) & (BA <= r_[1] + 1) & (BB >= r_[2] - 1) & (BB <= r_[3] + 1)))
        r_ = (a0, a1, b0, b1)
        while nbad(r_) and r_[1] - r_[0] >= 8 and r_[3] - r_[2] >= 8:
            opts = [(r_[0] + 2, r_[1], r_[2], r_[3]), (r_[0], r_[1] - 2, r_[2], r_[3]),
                    (r_[0], r_[1], r_[2] + 2, r_[3]), (r_[0], r_[1], r_[2], r_[3] - 2)]
            r_ = min(opts, key=lambda o: (nbad(o), -(o[1] - o[0]) * (o[3] - o[2])))
        a0, a1, b0, b1 = r_
        cx_, cz_, L_, W_ = rect(a0, a1, b0, b1)
        if L_ * W_ < 0.5 * area0 or not rect_clear(cx_, cz_, ux, uz, L_, W_):
            dropped["junction plate blocked"] += 1
            continue
        if emit("pad", cx_, top - 0.02, cz_, math.atan2(uz, ux), 0.0, L_, RP.THICKNESS, W_, "junction", 0):
            plates += 1
    print(f"{plates} junction plates")

    # ---- INFERRED ALLEYS (Oct 6): straight gaps between buildings with no OSM way at
    # all. The open ground's ridge (cells at least as far from a building face as
    # their neighbours across it), 10..48 studs wide, away from the streets; each
    # straight ridge run >= INF_MIN_L becomes one alley slab
    dface = ndimage.distance_transform_edt(~face_mask) * bcell
    # ridge = 3x3 local maxima of the distance to a face (the per-axis test made
    # ticks across axis-aligned corridors)
    ridge = dface >= ndimage.maximum_filter(dface, size=3) - 0.6 * bcell
    near_road = ndimage.binary_dilation(covered, iterations=int(INF_CLEAR / bcell))
    ridge &= (dface >= INF_HALF[0]) & (dface <= INF_HALF[1]) & ~face_mask & ~near_road & live_city
    nb_ = ndimage.convolve(ridge.astype(np.int16), np.ones((3, 3), np.int16), mode="constant") - ridge
    ridge &= nb_ <= 4                                   # branch cells split the ridge
    lab, nlab = ndimage.label(ridge, structure=np.ones((3, 3)))
    n_inf = 0

    def pieces(XY, depth=0):
        """Recursively split points (ordered along their main axis) into straight runs."""
        if len(XY) * bcell < INF_MIN_L * 0.8:
            return []
        m_ = XY.mean(0)
        _, _, Vt = np.linalg.svd(XY - m_, full_matrices=False)
        ax_ = Vt[0]
        proj = (XY - m_) @ ax_
        perp = (XY - m_) @ np.array([-ax_[1], ax_[0]])
        if np.abs(perp).max() <= INF_STRAIGHT * 1.5 or depth >= 4:
            return [(m_, ax_, proj, perp)]
        cut = proj[np.argmax(np.abs(perp))]
        lo, hi = XY[proj < cut], XY[proj >= cut]
        if len(lo) < 3 or len(hi) < 3:
            return [(m_, ax_, proj, perp)]
        return pieces(lo, depth + 1) + pieces(hi, depth + 1)

    for li, sl in enumerate(ndimage.find_objects(lab), start=1):
        if sl is None:
            continue
        cells = np.argwhere(lab[sl] == li) + np.array([sl[0].start, sl[1].start])
        if len(cells) * bcell < INF_MIN_L * 0.8:
            continue
        XYall = np.stack([bx0 + (cells[:, 0] + 0.5) * bcell, bz0 + (cells[:, 1] + 0.5) * bcell], 1)
        for m_, ax_, proj, perp in pieces(XYall):
            L_ = float(proj.max() - proj.min())
            if L_ < INF_MIN_L or float(np.std(perp)) > INF_STRAIGHT:
                continue
            cx_ = m_ + ax_ * (proj.max() + proj.min()) / 2 + np.array([-ax_[1], ax_[0]]) * float(np.median(perp))
            ii = np.clip(((m_[0] + ax_[0] * proj - bx0) / bcell).astype(int), 0, bnx - 1)
            kk = np.clip(((m_[1] + ax_[1] * proj - bz0) / bcell).astype(int), 0, bnz - 1)
            hw = float(np.median(dface[ii, kk]))
            W_ = math.floor(min(2 * hw - 2 * MARGIN, (2 * LANE_SMALL_M + SHOULDER_M) * s) / 2) * 2
            if W_ < MIN_W or L_ < INF_ASPECT * W_:
                continue                          # a plaza corner, not an alley
            ux_, uz_ = float(ax_[0]), float(ax_[1])
            while W_ >= MIN_W and not rect_clear(cx_[0], cx_[1], ux_, uz_, L_, W_):
                W_ -= 2.0
            if W_ < MIN_W:
                continue
            ends_ = [cx_ - ax_ * L_ / 2, cx_ + ax_ * L_ / 2]
            hs_ = [min(ground(*e_), road_cap(*e_)) for e_ in ends_]
            y0_, y1_ = (math.floor(h_ / SNAP) * SNAP for h_ in hs_)
            if abs(y1_ - y0_) / max(L_, 1.0) > MAX_SLAB_GRADE:
                continue
            if emit("roadway", cx_[0], (y0_ + y1_) / 2 + ROAD_LIFT, cx_[1], math.atan2(uz_, ux_),
                    math.atan2(y1_ - y0_, L_), L_, RP.THICKNESS, W_, "inferred", 0, True, "alley"):
                for c_ in footprint_cells(cx_[0], cx_[1], ux_, uz_, L_, W_):
                    covered[c_] = True
                n_inf += 1
                total += L_
    print(f"{n_inf} inferred alley slabs (gaps between buildings with no OSM way)")

    # ---- SIDEWALKS (owner, Oct 6: "if we can set the roads properly, then we can make
    # the sidewalks properly"): beside every small street slab, flat slabs from the
    # road edge out to the building face (live footprints; at most SIDE_MAX),
    # CURB above the road, broken wherever another road or plate is in the way
    occ = np.zeros((bnx, bnz), bool)

    def raster(rx, rz, ux, uz, L, W, into):
        for a in np.arange(-L / 2, L / 2 + 0.01, 1.0):
            for b in np.arange(-W / 2, W / 2 + 0.01, 1.0):
                i, j = int((rx + ux * a - uz * b - bx0) / bcell), int((rz + uz * a + ux * b - bz0) / bcell)
                if 0 <= i < bnx and 0 <= j < bnz:
                    into[i, j] = True
    for rows in tiles.values():
        for r in rows:
            if r[0] in ("roadway", "pad"):
                raster(r[1], r[3], math.cos(r[4]), math.sin(r[4]), r[6], r[8], occ)
    # the floor of the nearest building at any point (tools/floor_cap.py grid):
    # a sidewalk rises toward the floor of the buildings it runs along
    fcz = np.load(DATA / "floor_cap.npz")
    FLz, BMz, fx0, fz0 = fcz["FL"].astype(float), fcz["BM"], float(fcz["x0"]), float(fcz["z0"])
    _, fidx = ndimage.distance_transform_edt(~BMz, return_indices=True)
    FLn = FLz[tuple(fidx)]

    def floor_near(x, z):
        i = min(max(int((x - fx0) / 4.0), 0), FLn.shape[0] - 1)
        k = min(max(int((z - fz0) / 4.0), 0), FLn.shape[1] - 1)
        return float(FLn[i, k])
    jc_list = [(float(c_[0]), float(c_[1]), float(R_)) for c_, R_ in cl_info.values()]

    def in_junction(x, z):
        return any((x - jx) ** 2 + (z - jz) ** 2 <= (jr + 2.0) ** 2 for jx, jz, jr in jc_list
                   if abs(x - jx) <= jr + 2 and abs(z - jz) <= jr + 2)
    n_side = 0
    side_rows = [r for rows in tiles.values() for r in rows if r[0] == "roadway" and len(r) > 12 and r[12]
                 and not (len(r) > 13 and r[13] == "alley")]
    for r in side_rows:
        _, rx, top, rz, yaw, pitch, L, _, W = r[:9]
        ux, uz = math.cos(yaw), math.sin(yaw)
        nx_, nz_ = -uz, ux
        for sg in (1, -1):
            st_, rc_ = [], []
            for a in np.arange(-L / 2 + 1.0, L / 2 - 0.99, 2.0):
                ex, ez = rx + ux * a + nx_ * sg * W / 2, rz + uz * a + nz_ * sg * W / 2
                if in_junction(ex + nx_ * sg * 2.0, ez + nz_ * sg * 2.0):
                    st_.append(a); rc_.append(0.0)       # a side street's mouth: no sidewalk across it
                    continue
                # (the first 2 studs share 2-stud cells with this street's own slab)
                d_ = 2.0 if not blocked[min(max(int((ex + nx_ * sg * 2 - bx0) / bcell), 0), bnx - 1),
                                       min(max(int((ez + nz_ * sg * 2 - bz0) / bcell), 0), bnz - 1)] else 0.0
                hit_road = False
                while d_ < SIDE_MAX:
                    qx, qz = ex + nx_ * sg * (d_ + 1.0), ez + nz_ * sg * (d_ + 1.0)
                    i, j = int((qx - bx0) / bcell), int((qz - bz0) / bcell)
                    if not (0 <= i < bnx and 0 <= j < bnz) or face_mask[i, j]:
                        break
                    if occ[i, j]:
                        hit_road = True
                        break
                    d_ += 1.0
                if hit_road and d_ < MOUTH:
                    d_ = 0.0                              # another road right there: a street mouth
                # no building face within reach: a standard sidewalk, not the whole lot
                st_.append(a); rc_.append(SIDE_OPEN_M * s if d_ >= SIDE_MAX else d_)
            # runs of stations with room for a sidewalk
            # runs of stations with room for a sidewalk, split where the reach to
            # the building face changes (one width per run left gaps of terrain
            # between a narrow sidewalk and a set-back building)
            runs, cur = [], []
            for a, d_ in zip(st_, rc_):
                if d_ >= SIDE_MIN_W and (not cur or abs(d_ - float(np.median([q[1] for q in cur]))) <= SIDE_STEP):
                    cur.append((a, d_))
                else:
                    if cur:
                        runs.append(cur)
                    cur = [(a, d_)] if d_ >= SIDE_MIN_W else []
            if cur:
                runs.append(cur)
            # short runs merge into a neighbour (take the narrower width)
            merged = []
            for run in runs:
                if merged and (run[-1][0] - run[0][0] < 10.0 or merged[-1][-1][0] - merged[-1][0][0] < 10.0)                         and abs(run[0][0] - merged[-1][-1][0]) <= 2.01:
                    merged[-1] = merged[-1] + run
                else:
                    merged.append(run)
            runs = merged
            side_fl = min([floor_near(rx + ux * a + nx_ * sg * (W / 2 + d_ + 2.0), rz + uz * a + nz_ * sg * (W / 2 + d_ + 2.0))
                           for run in runs for a, d_ in run] or [1e9])
            for run in runs:
                a0, a1 = run[0][0] - 1.0, run[-1][0] + 1.0
                if a1 - a0 < SIDE_MIN_L:
                    continue
                sw = min(max(SIDE_MIN_W, float(np.percentile([d_ for _, d_ in run], 10)) - 0.5), SIDE_MAX)
                am = (a0 + a1) / 2
                off = sg * (W / 2 + sw / 2)
                sx, sz = rx + ux * am + nx_ * off, rz + uz * am + nz_ * off
                # height: just under the LOWEST floor along its outer edge, between a
                # CURB and SIDE_RISE above the road (owner: terrain within the floor slab;
                # the road itself stays under every floor around it)
                fl_ = side_fl                      # one height for the whole side of the street
                road_at = top + am * math.tan(pitch)
                y_side = min(max(fl_ - SIDE_BELOW - abs(math.tan(pitch)) * (a1 - a0) / 2, road_at + CURB), road_at + SIDE_RISE)
                if emit("sidewalk", sx, y_side, sz, yaw, pitch, a1 - a0,
                        RP.THICKNESS, sw, r[9], r[10], True):
                    raster(sx, sz, ux, uz, a1 - a0, sw, occ)
                    n_side += 1
    print(f"{n_side} sidewalk slabs beside {len(side_rows)} small street slabs")

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
