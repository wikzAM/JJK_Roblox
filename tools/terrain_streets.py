"""Streets as TERRAIN on the flattened city (owner, Oct 6, option B).

The buildings now sit on one smooth gentle surface (tools/flatten_fit.py), so
the ground is that surface: tools/ground_clamp.py's floor surface, pinned just
under every ground floor. Roads and sidewalks are painted terrain on it, not
parts; the only parts are CURBS along each sidewalk's road edge.

  * every street (road_fit roadway rows) is made perfectly level ACROSS its width:
    its cells take the surface height on its centreline (smoothed along it)
  * sidewalks are the surface itself (+ SIDEWALK_UP), never below the road beside them
  * curbs: one Part per sidewalk row on the edge facing its street, CURB_H above
    the road, CURB_W wide, sunk CURB_DEEP into the ground; written into the road
    tiles as "curb" rows (RoadBuilder builds only curbs while TERRAIN_ROADS)
  * under buildings: below the floor slab, as before

  python tools/terrain_streets.py   (after floor_cap, ground_clamp, road_fit)
      -> source_slices/ground/terrain/ (chunks), curb rows in roads/tile_*.json
"""
import json
import math
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402

D = ROOT / "source_slices" / "ground"
CELL = 4.0
FILE_TO_STUDIO = 2.5
DELTA_MED, DELTA_MAX = 2.8, 4.0
RING = 8.0            # studs round a building where the ground is held to its floor
RING_LO = 4.5         # ... at most this under the floor top (the slab is 5.36 deep)
RING_HI = 2.0         # ... at least this (typical render +0, worst +1.2)
REGEN_PASSES = 25
FAR_CITY = 200.0      # studs from any building before the natural ground comes back
UNDER_FLOOR = 4.6     # studs under the cap the ground stays beneath a building
ALONG = 10            # stations (4 studs) a street's centreline heights are averaged over
SIDE_GRADE = 0.15     # rise per stud of the ground beside a street, from its edge
SIDEWALK_UP = 0.0     # studs a sidewalk's terrain sits above the surface
ROAD_UNDER = 0.6      # studs a street's top stays under the floor cap (itself floor - 1)
SIDEWALK_PARTS = True # sidewalks as thin slabs (their edge is the curb) instead of terrain + curb strips
WALK_SINK = 2.0       # studs the ground under a sidewalk slab stays below its top
WALK_T = 1.5          # their thickness
SKINS = True          # a thin asphalt part over each street: crisp edges (terrain paints in 4-stud blocks)
SKIN_UP = 0.1         # its top above the street level
SKIN_T = 1.5          # its thickness
SKIN_SINK = 2.0       # the terrain under it this far below the street level
CURB_H = 0.8          # studs a curb's top stands above the road
CURB_W = 1.2          # studs wide
CURB_DEEP = 3.0       # studs it reaches below the road


def main():
    src = D / "terrain_clamped"
    index = json.loads((src / "index.json").read_text())
    chunks = {n: json.loads((src / f"{n}.json").read_text()) for n in index}
    orig = {n: json.loads((D / "terrain_orig" / f"{n}.json").read_text()) for n in index}
    gx0 = min(c["x0"] for c in chunks.values()); gz0 = min(c["z0"] for c in chunks.values())
    NX = int(round((max(c["x0"] + c["nx"] * CELL for c in chunks.values()) - gx0) / CELL))
    NZ = int(round((max(c["z0"] + c["nz"] * CELL for c in chunks.values()) - gz0) / CELL))
    H = np.full((NX, NZ), np.nan); CAP = np.full((NX, NZ), np.inf); HO = np.full((NX, NZ), np.nan)
    for n, c in chunks.items():
        i0, k0 = int(round((c["x0"] - gx0) / CELL)), int(round((c["z0"] - gz0) / CELL))
        sl = (slice(i0, i0 + c["nx"]), slice(k0, k0 + c["nz"]))
        H[sl] = np.array(c["h"]).reshape(c["nx"], c["nz"])
        cp = np.array(c["cap"], float).reshape(c["nx"], c["nz"])
        CAP[sl] = np.where(cp >= 99999, np.inf, cp)
        HO[sl] = np.array(orig[n]["h"]).reshape(c["nx"], c["nz"])
    natural = HO + FILE_TO_STUDIO + DELTA_MED
    cap_vis = CAP + FILE_TO_STUDIO + DELTA_MAX
    XC = gx0 + (np.arange(NX) + 0.5) * CELL
    ZC = gz0 + (np.arange(NZ) + 0.5) * CELL
    # REGENERATED ground (owner, Oct 6: "move all the buildings and then regenerate
    # the terrain"): not the old terrain at all -- the smooth surface the buildings
    # were placed on (tools/flatten_fit.py), nudged only in a ring round each
    # building into [floor - RING_LO, floor - RING_HI], smoothed between
    fs = np.load(D / "flat_surface.npz")
    S = fs["S"].astype(float)
    assert S.shape == (NX, NZ), "flat_surface.npz is on another grid"
    fc0 = np.load(D / "floor_cap.npz")
    BM0 = fc0["BM"]; FL0 = np.where(BM0, fc0["FL"].astype(float), np.nan)
    dB, iB = ndimage.distance_transform_edt(~BM0, return_indices=True)
    dB *= CELL
    FLn = FL0[tuple(iB)]
    ring = (dB > 0) & (dB <= RING)
    lo_ = np.where(ring, FLn - RING_LO, -np.inf)
    hi_ = np.where(ring, FLn - RING_HI, np.inf)
    G = np.clip(S, lo_, hi_)
    for _ in range(REGEN_PASSES):
        G = np.clip(ndimage.gaussian_filter(G, 1.5, mode="nearest"), lo_, hi_)
    # far outside the city: back to the natural ground
    wn = np.clip((dB - FAR_CITY) / FAR_CITY, 0, 1)
    FS = np.where(np.isnan(natural), G, (1 - wn) * G + wn * natural)
    FSf = np.where(np.isfinite(FS), FS, np.nanmedian(FS))

    def surf(x, z):
        fi = min(max((x - gx0) / CELL - 0.5, 0), NX - 1.001); fj = min(max((z - gz0) / CELL - 0.5, 0), NZ - 1.001)
        i, j = int(fi), int(fj); u, v = fi - i, fj - j
        return float(FSf[i, j] * (1 - u) * (1 - v) + FSf[i + 1, j] * u * (1 - v) + FSf[i, j + 1] * (1 - u) * v + FSf[i + 1, j + 1] * u * v)

    fcc = np.load(D / "floor_cap.npz")
    C360a = np.where(fcc["CAP"] >= 1e5, 1e9, fcc["CAP"].astype(float))

    def cap360(x, z):
        i, k = int((x - gx0) / CELL), int((z - gz0) / CELL)
        return float(C360a[i, k]) if 0 <= i < NX and 0 <= k < NZ else 1e9
    roads = D / "roads"
    tiles = {name: json.loads((roads / f"{name}.json").read_text()) for name, _ in json.loads((roads / "index.json").read_text())}
    rows = [r for t in tiles.values() for r in t["slabs"]]

    # 1. streets level across: each roadway row's cells take its centreline profile
    road_y = np.full((NX, NZ), np.nan)
    road_d = np.full((NX, NZ), -np.inf)
    profiles = {}
    for r in rows:
        if r[0] != "roadway":
            continue
        _, cx, _, cz, yaw, _, L, _, W = r[:9]
        ux, uz = math.cos(yaw), math.sin(yaw)
        st = np.arange(-L / 2 - 4 * ALONG, L / 2 + 4 * ALONG + 0.1, 4.0)
        ys = np.array([surf(cx + ux * a, cz + uz * a) for a in st])
        ys = np.convolve(np.pad(ys, ALONG // 2, mode="edge"), np.ones(ALONG + 1) / (ALONG + 1), mode="valid")[:len(st)]
        # never above a floor beside it: the 360 floor cap at the centreline and both edges
        nx_, nz_ = -uz, ux
        cy = np.array([min(cap360(cx + ux * a + nx_ * o, cz + uz * a + nz_ * o) for o in (-W / 2 - 2, 0.0, W / 2 + 2))
                       for a in st]) - ROAD_UNDER
        ys = np.minimum(ys, cy)
        # the skin is ONE straight part end to end: the street level is never above
        # that line (a bowed profile put ground up to 12 studs over the skin)
        ya, yb = float(np.interp(-L / 2, st, ys)), float(np.interp(L / 2, st, ys))
        line = ya + (st + L / 2) / L * (yb - ya)
        ys = np.minimum(ys, line)
        profiles[id(r)] = (st, ys)
        ext = math.hypot(L, W) / 2 + CELL
        i0 = max(int((cx - ext - gx0) / CELL), 0); i1 = min(int((cx + ext - gx0) / CELL) + 1, NX)
        k0 = max(int((cz - ext - gz0) / CELL), 0); k1 = min(int((cz + ext - gz0) / CELL) + 1, NZ)
        if i1 <= i0 or k1 <= k0:
            continue
        X, Z = np.meshgrid(XC[i0:i1], ZC[k0:k1], indexing="ij")
        a = (X - cx) * ux + (Z - cz) * uz
        b = -(X - cx) * uz + (Z - cz) * ux
        depth = np.minimum(L / 2 + 1 - np.abs(a), W / 2 + 1 - np.abs(b))
        sub_y, sub_d = road_y[i0:i1, k0:k1], road_d[i0:i1, k0:k1]
        take = (depth > 0) & (depth > sub_d)
        sub_y[take] = np.interp(a[take], st, ys)
        sub_d[take] = depth[take]
    on_road = np.isfinite(road_y)
    vis = np.where(on_road, road_y - (SKIN_SINK if SKINS else 0.0), FS)
    # sidewalks never below the road beside them (+ SIDEWALK_UP)
    _, ridx = ndimage.distance_transform_edt(~on_road, return_indices=True)
    near_road_y = road_y[tuple(ridx)]
    dr = ndimage.distance_transform_edt(~on_road) * CELL
    side_zone = (dr > 0) & (dr <= 24)
    vis = np.where(side_zone, np.maximum(vis, near_road_y + SIDEWALK_UP * (dr <= 24)), vis)
    # ...and no higher than the road at its edge, rising SIDE_GRADE per stud away from it
    # (a road lowered under a floor beside it left the sidewalk ground over its edge)
    vis = np.where(side_zone, np.minimum(vis, near_road_y + 0.2 + SIDE_GRADE * np.maximum(dr - CELL, 0)), vis)
    # under the sidewalk slabs: sunk well under their top (road + CURB_H)
    if SIDEWALK_PARTS:
        on_walk = np.zeros_like(on_road)
        for r in rows:
            if r[0] != "sidewalk":
                continue
            _, sx, _, sz, yaw, _, L, _, W = r[:9]
            ux, uz = math.cos(yaw), math.sin(yaw)
            ext = math.hypot(L, W) / 2 + CELL
            i0 = max(int((sx - ext - gx0) / CELL), 0); i1 = min(int((sx + ext - gx0) / CELL) + 1, NX)
            k0 = max(int((sz - ext - gz0) / CELL), 0); k1 = min(int((sz + ext - gz0) / CELL) + 1, NZ)
            if i1 <= i0 or k1 <= k0:
                continue
            X, Z = np.meshgrid(XC[i0:i1], ZC[k0:k1], indexing="ij")
            a = (X - sx) * ux + (Z - sz) * uz
            b = -(X - sx) * uz + (Z - sz) * ux
            on_walk[i0:i1, k0:k1] |= (np.abs(a) <= L / 2 + 1) & (np.abs(b) <= W / 2 + 1)
        on_walk &= ~on_road
        vis = np.where(on_walk, np.minimum(vis, near_road_y + CURB_H - WALK_SINK), vis)
    # and never above the floor of any building around it (tools/floor_cap.py, 360 deg)
    fc = np.load(D / "floor_cap.npz")
    C360 = np.where(fc["CAP"] >= 1e5, np.inf, fc["CAP"].astype(float))
    if C360.shape == vis.shape:
        vis = np.minimum(vis, C360 - 0.3)
    # 2. under buildings
    lf = np.load(D / "live_footprints.npz")
    M, mx0, mz0, mc = lf["mask"], float(lf["x0"]), float(lf["z0"]), float(lf["cell"])
    bld = M[np.ix_(np.clip(((XC - mx0) / mc).astype(int), 0, M.shape[0] - 1),
                   np.clip(((ZC - mz0) / mc).astype(int), 0, M.shape[1] - 1))]
    _, oidx = ndimage.distance_transform_edt(bld, return_indices=True)
    # the ground runs on FLAT under a building, hidden inside its 5.36-deep floor slab
    # (dropping it under the slab bottom rippled every footprint edge)
    under_floor = np.where(np.isfinite(FL0), FL0 - RING_HI, np.inf)
    vis = np.where(bld, np.minimum(vis[tuple(oidx)], under_floor), vis)
    vis = np.where(np.isnan(H), np.nan, vis)
    # 3. encode: one render offset everywhere (flat stays flat), the worst-case one
    # where the ground is close under a floor, changed gradually
    delta = np.full_like(vis, DELTA_MED)          # one render offset: flat renders flat
    h_file = vis - delta - FILE_TO_STUDIO
    out = D / "terrain"
    for name, c in chunks.items():
        i0, k0 = int(round((c["x0"] - gx0) / CELL)), int(round((c["z0"] - gz0) / CELL))
        hc = h_file[i0:i0 + c["nx"], k0:k0 + c["nz"]]
        c2 = dict(c)
        c2["h"] = [round(float(v), 2) if np.isfinite(v) else round(float(h0), 2) for v, h0 in zip(hc.ravel(), np.array(c["h"]))]
        (out / f"{name}.json").write_text(json.dumps(c2))
    (out / "index.json").write_text(json.dumps(index))

    # 4. curbs along each sidewalk's road edge
    by_way = {}
    for r in rows:
        if r[0] == "roadway":
            by_way.setdefault(r[10], []).append(r)
    n_curb = 0
    walk_top = []
    for name, t in tiles.items():
        t["slabs"] = [r for r in t["slabs"] if r[0] not in ("curb", "skin", "walk")]
    new_rows = {}
    for r in rows:
        if r[0] != "sidewalk":
            continue
        _, sx, _, sz, yaw, _, L, _, W = r[:9]
        ux, uz = math.cos(yaw), math.sin(yaw)
        nx, nz = -uz, ux
        best = None
        for q in by_way.get(r[10], []):
            d = abs((sx - q[1]) * -math.sin(q[4]) + (sz - q[3]) * math.cos(q[4]))
            along = abs((sx - q[1]) * math.cos(q[4]) + (sz - q[3]) * math.sin(q[4]))
            if along <= q[6] / 2 + L / 2 and (best is None or d < best[0]):
                best = (d, q)
        if best is None:
            continue
        q = best[1]
        sg = 1.0 if ((q[1] - sx) * nx + (q[3] - sz) * nz) > 0 else -1.0     # toward the road
        ex, ez = sx + nx * sg * (W / 2 - CURB_W / 2), sz + nz * sg * (W / 2 - CURB_W / 2)
        st, ys = profiles[id(q)]
        qa = lambda x, z: (x - q[1]) * math.cos(q[4]) + (z - q[3]) * math.sin(q[4])
        e0 = (ex - ux * L / 2, ez - uz * L / 2); e1 = (ex + ux * L / 2, ez + uz * L / 2)
        y0 = float(np.interp(qa(*e0), st, ys)) + CURB_H
        y1 = float(np.interp(qa(*e1), st, ys)) + CURB_H
        thick = CURB_H + CURB_DEEP
        if SIDEWALK_PARTS:
            # the whole sidewalk as one slab, its top a curb's height over the road:
            # its road-side edge IS the curb
            s0 = (sx - ux * L / 2, sz - uz * L / 2); s1 = (sx + ux * L / 2, sz + uz * L / 2)
            w0 = float(np.interp(qa(*s0), st, ys)) + CURB_H
            w1 = float(np.interp(qa(*s1), st, ys)) + CURB_H
            keyw = f"tile_{int(math.floor(sx / 512)):+d}_{int(math.floor(sz / 512)):+d}".replace("+", "p").replace("-", "m")
            new_rows.setdefault(keyw, []).append(["walk", round(sx, 2), round((w0 + w1) / 2, 2), round(sz, 2), round(yaw, 5),
                                                  round(math.atan2(w1 - w0, L), 5), round(L, 2), WALK_T, round(W, 2), r[9], r[10]])
            walk_top.append((sx, sz, yaw, L, W, (w0 + w1) / 2, math.atan2(w1 - w0, L)))
            n_curb += 1
            continue
        key = f"tile_{int(math.floor(ex / 512)):+d}_{int(math.floor(ez / 512)):+d}".replace("+", "p").replace("-", "m")
        new_rows.setdefault(key, []).append(["curb", round(ex, 2), round((y0 + y1) / 2, 2), round(ez, 2), round(yaw, 5),
                                             round(math.atan2(y1 - y0, L), 5), round(L, 2), round(thick, 2), CURB_W, r[9], r[10]])
        n_curb += 1
    n_skin = 0
    if SKINS:
        for name, t_ in tiles.items():
            t_["slabs"] = [r for r in t_["slabs"] if r[0] != "skin"]
        for r in rows:
            if r[0] != "roadway":
                continue
            _, cx, _, cz, yaw, _, L, _, W = r[:9]
            st, ys = profiles[id(r)]
            y0 = float(np.interp(-L / 2, st, ys)) + SKIN_UP
            y1 = float(np.interp(L / 2, st, ys)) + SKIN_UP
            key = f"tile_{int(math.floor(cx / 512)):+d}_{int(math.floor(cz / 512)):+d}".replace("+", "p").replace("-", "m")
            new_rows.setdefault(key, []).append(["skin", round(cx, 2), round((y0 + y1) / 2, 2), round(cz, 2), round(yaw, 5),
                                                 round(math.atan2(y1 - y0, L), 5), round(L, 2), SKIN_T, round(W, 2), r[9], r[10]]
                                                + (r[11:] if len(r) > 11 else []))
            n_skin += 1
    names = json.loads((roads / "index.json").read_text())
    for key, rs in new_rows.items():
        if key not in tiles:
            tiles[key] = {"name": key, "slabs": []}
            names.append([key, 0])
        tiles[key]["slabs"].extend(rs)
    for key, t in tiles.items():
        (roads / f"{key}.json").write_text(json.dumps(t))
    names = [[k, len(tiles[k]["slabs"])] for k, _ in names]
    (roads / "index.json").write_text(json.dumps(names))
    flat = vis[on_road]
    print(f"terrain written ({int(on_road.sum())} street cells levelled across); {n_curb} curbs, {n_skin} road skins")


if __name__ == "__main__":
    main()
