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
GROUND_TOL = 8.0      # studs a floor may sit above the surface and still count as a ground floor
RING = 8.0            # studs round a building where the ground is held to its floor
RING_LO = 4.5         # ... at most this under the floor top (the slab is 5.36 deep)
RING_HI = 2.0         # ... at least this (typical render +0, worst +1.2)
REGEN_PASSES = 25
GRADE_MAX = 0.12      # the steepest the open ground may change, per stud
FAR_CITY = 1e9        # studs from any building before the natural ground comes back
UNDER_FLOOR = 4.6     # studs under the cap the ground stays beneath a building
ALONG = 10            # stations (4 studs) a street's centreline heights are averaged over
SIDE_GRADE = 0.15     # rise per stud of the ground beside a street, from its edge
SIDEWALK_UP = 0.0     # studs a sidewalk's terrain sits above the surface
ROAD_UNDER = 0.6      # studs a street's top stays under the floor cap (itself floor - 1)
SIDEWALK_PARTS = True # sidewalks as thin slabs (their edge is the curb) instead of terrain + curb strips
WALK_SINK = 2.0       # studs the ground under a sidewalk slab stays below its top
WALK_T = 1.5          # their thickness
SKINS = True          # a thin asphalt part over each street: crisp edges (terrain paints in 4-stud blocks)
PART_LIFT = 1.0       # studs a part's underside-top margin over the highest ground under it
SKIN_UP = 0.0         # its top above the street level
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
    # only GROUND floors shape the ground: a tower body standing on a podium has its
    # own Floor1 high up, and where it overhangs the podium it pulled the ground up
    # to 434 (cliffs of 280 studs within a block)
    high = np.isfinite(FL0) & (FL0 > S + 2.0 + GROUND_TOL)
    FL0 = np.where(high, np.nan, FL0); BM0 = BM0 & ~high
    dB, iB = ndimage.distance_transform_edt(~BM0, return_indices=True)
    dB *= CELL
    FLn = FL0[tuple(iB)]
    ring = (dB > 0) & (dB <= RING)
    lo_ = np.where(ring, FLn - RING_LO, -np.inf)
    hi_ = np.where(ring, FLn - RING_HI, np.inf)
    G = np.clip(S, lo_, hi_)
    for _ in range(REGEN_PASSES):
        G = np.clip(ndimage.gaussian_filter(G, 1.5, mode="nearest"), lo_, hi_)
    # GRADUAL: the ground changes at most GRADE_MAX per stud anywhere, so where a
    # building's floor sits far off the surface the dip / rise round it is spread
    # wide instead of a 30-stud cliff within a block. Lower and upper envelopes
    # from the ring constraints, then the surface clamped between them.
    step, diag = GRADE_MAX * CELL, GRADE_MAX * CELL * 2 ** 0.5

    def envelope(A, lower):
        for _ in range(400):
            p = np.pad(A, 1, mode="edge")
            nb = [p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:], p[:-2, :-2], p[:-2, 2:], p[2:, :-2], p[2:, 2:]]
            ds = [step] * 4 + [diag] * 4
            if lower:
                new = np.minimum.reduce([A] + [n_ + d_ for n_, d_ in zip(nb, ds)])
            else:
                new = np.maximum.reduce([A] + [n_ - d_ for n_, d_ in zip(nb, ds)])
            if np.allclose(new, A, atol=1e-3):
                break
            A = new
        return A
    up_lim = envelope(np.where(ring, hi_, np.inf), True)      # never above what a ring allows, eased
    lo_lim = envelope(np.where(ring, lo_, -np.inf), False)    # never below what a ring needs, eased
    G = np.minimum(np.maximum(G, lo_lim), up_lim)
    for _ in range(8):
        G = np.minimum(np.maximum(ndimage.gaussian_filter(G, 1.0, mode="nearest"), lo_lim), up_lim)
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

    # 1. THE GROUND IS ROAD-AGNOSTIC (owner, Oct 6: "the parts of the roads and
    # sidewalks are affecting the terrain"): nothing here looks at a road or a
    # sidewalk. The parts are fitted onto this finished ground afterwards (step 4).
    vis = FS.copy()
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

    # 4. PARTS ON TOP of the finished ground: a road skin is one straight part lying
    # above the highest ground anywhere under it (+ PART_LIFT, the terrain renders up
    # to ~1.2 over what it encodes); a sidewalk slab a curb's height over its road
    # and above the ground under it
    VG = np.where(np.isfinite(vis), vis, np.nanmedian(vis))

    def ground_at(x, z):
        i, k = int((x - gx0) / CELL), int((z - gz0) / CELL)
        i0, i1 = max(i - 1, 0), min(i + 2, NX); k0, k1 = max(k - 1, 0), min(k + 2, NZ)
        return float(VG[i0:i1, k0:k1].max()) if i1 > i0 and k1 > k0 else float(np.nanmedian(VG))

    def top_over(cx, cz, ux, uz, L, W, cap_road=False):
        # the straight line (ya at -L/2, yb at +L/2) above all ground under the rect
        st = np.arange(-L / 2, L / 2 + 0.01, 2.0)
        nx_, nz_ = -uz, ux
        gmax = np.array([max(ground_at(cx + ux * a + nx_ * o, cz + uz * a + nz_ * o)
                             for o in np.linspace(-W / 2, W / 2, max(2, int(W / 4) + 1))) for a in st])
        A = np.vstack([st, np.ones_like(st)]).T
        k_, c_ = np.linalg.lstsq(A, gmax, rcond=None)[0]
        c_ += max(0.0, float((gmax - (k_ * st + c_)).max()))
        y = k_ * st + c_ + PART_LIFT
        if cap_road:
            # never above the floor of a building beside it (360 floor cap at both edges)
            cmin = np.array([min(cap360(cx + ux * a + nx_ * o, cz + uz * a + nz_ * o) for o in (-W / 2 - 2, W / 2 + 2))
                             for a in st]) - ROAD_UNDER
            y = y - max(0.0, float((y - cmin).max()))
        return st, y, k_
    profiles = {}
    for r in rows:
        if r[0] == "roadway":
            _, cx, _, cz, yaw, _, L, _, W = r[:9]
            profiles[id(r)] = top_over(cx, cz, math.cos(yaw), math.sin(yaw), L, W, cap_road=False)[:2]
    on_road = np.zeros((NX, NZ), bool)

    # 4b. curbs / sidewalk slabs along each sidewalk's road edge
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
            _, gl, _ = top_over(sx, sz, ux, uz, L, W)     # the ground under the slab
            up_ = max(0.0, float(gl[0] - w0), float(gl[-1] - w1))
            w0 += up_; w1 += up_
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
