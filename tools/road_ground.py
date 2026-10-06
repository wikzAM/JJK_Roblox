"""The final ground: one smooth surface built from the roads.

Grading only a band around each road left the open asphalt between streets as
the original lumpy ground, with rims where round junction patches met it. Here
the whole open ground is computed at once, so the road slabs, the junction gaps
and the open asphalt lie in one even surface:

  * known heights: every road slab's top (from roads/tile_*.json) and every
    junction patch (roads/junctions.json);
  * open ground: those heights spread smoothly outward (nearest-value fill,
    then repeated smoothing with the known cells pinned), blending back into
    the natural ground beyond FAR studs from any road;
  * under a road: just below the slab within EDGE of its edge, deep in the middle;
  * never above `cap` (tools/ground_clamp.py: buildings are never sunk);
  * under a building: the clamped natural ground, untouched.

Heights here are VISIBLE heights; written chunk heights are visible - DELTA -
FILE_TO_STUDIO (smooth terrain renders DELTA above what it encodes).

  python tools/road_ground.py   (after road_fit.py)  -> source_slices/ground/terrain/
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
MEET = -0.4       # open ground aimed this far relative to the road surface it continues:
                  # BELOW it (owner: terrain sat above the roads -- 51% of samples)
EDGE = 4.0        # under a slab within this of its edge, the ground stays just below it
DEEP = 2.2        # ... and this far below it deeper in (isolated voxels render as peaks)
FAR = 40.0        # (unused since Oct 6: see JOIN)
FS_RING = 8.0     # studs round a building where the ground is its floor surface
SIDE_RISE_OK = 6.0  # studs: ground behind a sidewalk up to this above it is left alone (a building's floor)
SIDE_BANK = 1.0   # rise per stud of the ground behind a sidewalk
SIDE_SINK = 3.0   # studs the ground stays under a sidewalk slab's top
JOIN = 8.0        # studs from a road over which the ground goes from the road's level to the floor surface
SMOOTH_PASSES = 12
BAND = 8.0        # studs beside a building where the ground comes up under its ground floor
FLUSH_GAP = 0.5   # ... to this far under the visible cap (cap = slab top - 1)
ROAD_CLEAR = 8.0  # ... fully only this far from a road
MAX_RAISE = 1.5
APRON_IN = 4.0    # studs from a building: the apron is full this close,
APRON_OUT = 14.0  # ... gone this far out
APRON_MAX = 2.0   # ... and raises the ground by at most this (more rose as jagged mounds)
FLAT_SPAN = 20.0  # studs: the open ground away from roads is taken to its low over this span
FLAT_SIGMA = 1.5  # cells: ... then smoothed
FLAT_NEAR = 1e9   # (flattening off: the floor surface is already flat and pinned to the floors)
FLAT_BLEND = 14.0 # ... and over which it comes in fully
JDROP_MAX = 24.0  # as tools/road_fit.py: street ends further off a junction's height are cliffs
UNDER_FLOOR = 4.6 # studs under the cap (slab top - 1) the ground stays beneath a building:
                  # just under the slab BOTTOM (top - 5.36); 6 left a dark void under floors
BANK_FLAT = 4.0   # beside a slab the ground stays at most at its top for this far out,
BANK_SLOPE = 1.0  # ... then rises no steeper than this: a hillside wall right at the
                  # edge of a road cut rendered leaning over the slab (pokes up to 12)


def main():
    src = D / "terrain_clamped"
    index = json.loads((src / "index.json").read_text())
    chunks = {n: json.loads((src / f"{n}.json").read_text()) for n in index}
    gx0 = min(c["x0"] for c in chunks.values())
    gz0 = min(c["z0"] for c in chunks.values())
    gx1 = max(c["x0"] + c["nx"] * CELL for c in chunks.values())
    gz1 = max(c["z0"] + c["nz"] * CELL for c in chunks.values())
    NX, NZ = int(round((gx1 - gx0) / CELL)), int(round((gz1 - gz0) / CELL))
    H = np.full((NX, NZ), np.nan)
    CAP = np.full((NX, NZ), np.inf)
    for c in chunks.values():
        i0, k0 = int(round((c["x0"] - gx0) / CELL)), int(round((c["z0"] - gz0) / CELL))
        H[i0:i0 + c["nx"], k0:k0 + c["nz"]] = np.array(c["h"]).reshape(c["nx"], c["nz"])
        cap = np.array(c["cap"], float).reshape(c["nx"], c["nz"])
        CAP[i0:i0 + c["nx"], k0:k0 + c["nz"]] = np.where(cap >= 99999, np.inf, cap)
    natural_vis = H + FILE_TO_STUDIO + DELTA_MED
    cap_vis = CAP + FILE_TO_STUDIO + DELTA_MAX          # the visible ceiling ground_clamp intended

    # cell centres
    XC = gx0 + (np.arange(NX) + 0.5) * CELL
    ZC = gz0 + (np.arange(NZ) + 0.5) * CELL

    # 1. road slabs: top height on the cells they cover, and depth from their edge
    road_top = np.full((NX, NZ), np.nan)
    road_depth = np.full((NX, NZ), -np.inf)
    roads = D / "roads"
    side_rows = []
    for name, _ in json.loads((roads / "index.json").read_text()):
        for r in json.loads((roads / f"{name}.json").read_text())["slabs"]:
            if r[0] == "sidewalk":
                side_rows.append(r)
                continue
            if r[0] not in ("roadway", "pad"):    # pads: the junction plates
                continue
            _, cx, ytop, cz, yaw, pitch, L, _, W = r[:9]
            ux, uz = math.cos(yaw), math.sin(yaw)
            ext = math.hypot(L, W) / 2 + CELL
            i0 = max(int((cx - ext - gx0) / CELL), 0); i1 = min(int((cx + ext - gx0) / CELL) + 1, NX)
            k0 = max(int((cz - ext - gz0) / CELL), 0); k1 = min(int((cz + ext - gz0) / CELL) + 1, NZ)
            if i1 <= i0 or k1 <= k0:
                continue
            X, Z = np.meshgrid(XC[i0:i1], ZC[k0:k1], indexing="ij")
            a = (X - cx) * ux + (Z - cz) * uz
            b = -(X - cx) * uz + (Z - cz) * ux
            depth = np.minimum(L / 2 - np.abs(a), W / 2 - np.abs(b))
            inside = depth > 0
            top = ytop + a * math.tan(pitch)
            sub_t, sub_d = road_top[i0:i1, k0:k1], road_depth[i0:i1, k0:k1]
            take = inside & (depth > sub_d)
            sub_t[take] = top[take]
            sub_d[take] = depth[take]
    under = np.isfinite(road_depth) & (road_depth > 0)

    # 2. known visible heights: road tops (slightly above, at their edges) and junctions
    known = np.full((NX, NZ), np.nan)
    known[under] = road_top[under] + MEET
    for jn in json.loads((roads / "junctions.json").read_text()):
        x, z, rad, h = jn[:4]
        ends = jn[4] if len(jn) > 4 else []
        # ends far off the junction height are cliffs (stairs): not part of its ground
        ends = [e for e in ends if abs(e[2] - h) <= JDROP_MAX]
        i0 = max(int((x - rad - gx0) / CELL), 0); i1 = min(int((x + rad - gx0) / CELL) + 1, NX)
        k0 = max(int((z - rad - gz0) / CELL), 0); k1 = min(int((z + rad - gz0) / CELL) + 1, NZ)
        X, Z = np.meshgrid(XC[i0:i1], ZC[k0:k1], indexing="ij")
        disc = (X - x) ** 2 + (Z - z) ** 2 <= rad * rad
        if ends:
            # sloping between the street ends (inverse-distance weights): a FLAT
            # patch at one height left steps of up to 18 studs at hill junctions
            wsum = np.zeros_like(X); hsum = np.zeros_like(X)
            for ex, ez, eh in (e[:3] for e in ends):
                wgt = 1.0 / np.maximum((X - ex) ** 2 + (Z - ez) ** 2, 16.0)
                wsum += wgt; hsum += wgt * eh
            hp = hsum / wsum
        else:
            hp = np.full_like(X, h)
        sub = known[i0:i1, k0:k1]
        sub[disc & np.isnan(sub)] = hp[disc & np.isnan(sub)] + MEET
    K = ~np.isnan(known)
    print(f"{int(under.sum())} cells under road slabs, {int(K.sum())} known cells")

    # 3. spread smoothly over the open ground (normalised convolution, pinned)
    dist, idx = ndimage.distance_transform_edt(~K, return_indices=True)
    dist *= CELL
    F = known[tuple(idx)]
    for _ in range(SMOOTH_PASSES):
        F = ndimage.gaussian_filter(F, 2.0, mode="nearest")
        F[K] = known[K]
    # blend back to the natural ground far from roads
    # the floor surface everywhere but the last JOIN studs at a road's edge
    # (Oct 6: blending over 40 studs held the ground a median 3.2, p90 13 under the floors)
    # Across the open ground between a road and a building the ground goes from the
    # road's level to the building's floor surface in proportion to the distances
    # (a fixed JOIN made plazas next to a lower road a bank right at its edge)
    lf0 = np.load(D / "live_footprints.npz")
    M0, mx00, mz00, mc0 = lf0["mask"], float(lf0["x0"]), float(lf0["z0"]), float(lf0["cell"])
    bld0 = M0[np.ix_(np.clip(((XC - mx00) / mc0).astype(int), 0, M0.shape[0] - 1),
                     np.clip(((ZC - mz00) / mc0).astype(int), 0, M0.shape[1] - 1))]
    db0 = np.maximum(ndimage.distance_transform_edt(~bld0) * CELL - FS_RING, 0.0)
    wnat = np.clip((dist - 2.0) / np.maximum(dist - 2.0 + db0, 1e-6), 0, 1)
    # (capping this at the road surface F was tried: it cut the slopes hillside
    # buildings stand on, leaving ground floors up to 21 studs in the air)
    vis = (1 - wnat) * F + wnat * natural_vis

    # 4. under the slabs themselves: just below the surface at the edges, deeper in
    under_vis = np.where(road_depth <= EDGE, road_top - 0.2, road_top - DEEP)
    vis = np.where(under, under_vis, vis)

    # 5. the building cap, and buildings' own footprints untouched
    lf = np.load(D / "live_footprints.npz")
    M, mx0, mz0, mc = lf["mask"], float(lf["x0"]), float(lf["z0"]), float(lf["cell"])
    mi = np.clip(((XC - mx0) / mc).astype(int), 0, M.shape[0] - 1)
    mk = np.clip(((ZC - mz0) / mc).astype(int), 0, M.shape[1] - 1)
    bld = M[np.ix_(mi, mk)]
    # ...and UP to the ground floor beside a building: "at or below" alone left
    # ground floors hovering over a dark void. Within BAND of a footprint the
    # ground rises to FLUSH under the slab top (= cap_vis - FLUSH_GAP), but only
    # away from roads (full effect beyond ROAD_CLEAR studs of one) and by at most
    # MAX_RAISE, so a street beside a high-set building is never left in a trench
    dist_b = ndimage.distance_transform_edt(~bld) * CELL
    near_b = (dist_b > 0) & (dist_b <= BAND) & np.isfinite(cap_vis)
    w_road = np.clip((dist - 2.0) / (ROAD_CLEAR - 2.0), 0, 1)
    # (the ground used to be raised up to FLUSH_GAP under the floor here; owner,
    # Oct 5: ground beside buildings must stay BELOW the floor -- no raise now)
    vis = np.minimum(vis, cap_vis)
    # FLATTER (owner, Oct 5): away from the roads the open ground is taken down to
    # its local low (grey erosion over FLAT_SPAN) and smoothed -- courtyards were
    # mounds and pits between floors of different heights. Blends back in over
    # FLAT_BLEND studs from a road so slab edges still meet the ground.
    span = int(FLAT_SPAN / CELL) | 1
    big = np.where(np.isfinite(vis), vis, 1e4)
    E = ndimage.grey_erosion(big, size=(span, span))
    E = ndimage.gaussian_filter(np.where(E > 9e3, np.nan_to_num(vis, nan=0.0), E), FLAT_SIGMA)
    E = np.minimum(E, cap_vis)
    w_flat = np.clip((dist - FLAT_NEAR) / FLAT_BLEND, 0, 1)
    vis = np.where(~under & np.isfinite(vis), (1 - w_flat) * vis + w_flat * np.minimum(E, vis + 0.0), vis)
    # APRON: right beside a building (away from the roads) the ground comes back up
    # toward its floor -- to the capped original ground there, never above it and
    # never over the floor (cap_vis = floor - 1). The road-driven spread and the
    # flattening had left buildings a median 6.5 (p90 20) studs over the ground.
    w_b = np.clip((APRON_OUT - dist_b) / (APRON_OUT - APRON_IN), 0, 1) * (dist_b > 0)
    want = np.minimum(cap_vis - FLUSH_GAP, natural_vis)
    rise = np.clip(want - vis, 0, APRON_MAX) * w_b * w_road
    vis = np.where(~under & np.isfinite(rise), vis + np.nan_to_num(rise), vis)
    vis = np.minimum(vis, cap_vis)
    # embankment: no ground wall right at a slab edge
    dr, ridx = ndimage.distance_transform_edt(~under, return_indices=True)
    dr *= CELL
    # (held MEET under the road top and encoded with the worst-case offset below,
    # so it never renders over the slab edge)
    bank = road_top[tuple(ridx)] + MEET + BANK_SLOPE * np.maximum(dr - BANK_FLAT, 0)
    at_bank = ~under & (vis >= bank - 0.3)
    vis = np.where(~under, np.minimum(vis, bank), vis)
    # under a building: below its ground-floor slab BOTTOM (cap_vis = top - 1,
    # the slab is 5.36 deep): ground held just under the floor top rounded out
    # past the slab edges as pale jagged ridges along every building base
    # ...and no higher than the ground just outside it (nearest open cell): a
    # base standing above a lowered street rounded out past the floor edges as
    # jagged facets (Oct 5) -- the ground runs flat in under the building instead
    _, oidx = ndimage.distance_transform_edt(bld, return_indices=True)
    outside_vis = vis[tuple(oidx)]
    vis = np.where(bld, np.minimum(np.minimum(natural_vis, cap_vis - UNDER_FLOOR), outside_vis), vis)
    # under a SIDEWALK slab (8 studs deep): the ground sunk SIDE_SINK under its top
    # and, within a cell or two of a road, under the road too -- held just under the
    # raised sidewalk it rounded out over the road's edge
    side_top = np.full((NX, NZ), np.inf)
    for r in side_rows:
        _, cx, ytop, cz, yaw, pitch, L, _, W = r[:9]
        ux, uz = math.cos(yaw), math.sin(yaw)
        ext = math.hypot(L, W) / 2 + CELL
        i0 = max(int((cx - ext - gx0) / CELL), 0); i1 = min(int((cx + ext - gx0) / CELL) + 1, NX)
        k0 = max(int((cz - ext - gz0) / CELL), 0); k1 = min(int((cz + ext - gz0) / CELL) + 1, NZ)
        if i1 <= i0 or k1 <= k0:
            continue
        X, Z = np.meshgrid(XC[i0:i1], ZC[k0:k1], indexing="ij")
        a = (X - cx) * ux + (Z - cz) * uz
        b = -(X - cx) * uz + (Z - cz) * ux
        inside = (np.abs(a) <= L / 2 + 1) & (np.abs(b) <= W / 2 + 1)
        top = ytop + a * math.tan(pitch)
        sub = side_top[i0:i1, k0:k1]
        sub[inside] = np.minimum(sub[inside], top[inside])
    onside = np.isfinite(side_top) & ~under & ~bld
    vis = np.where(onside, np.minimum(vis, side_top - SIDE_SINK), vis)
    # ...and in a band just beyond its outer edge, under its top (the ground beside a
    # building with a higher floor than the street side's lowest poked over the edge)
    band_top = ndimage.minimum_filter(np.where(np.isfinite(side_top), side_top, 1e9), size=3)
    # (tried: only on the road side -- terrain then poked over 3x as many sidewalk
    # edges; both sides it is)
    near_side = (band_top < 1e8) & ~np.isfinite(side_top) & ~under & ~bld
    vis = np.where(near_side, np.minimum(vis, band_top - 0.6), vis)
    # beyond that band a hillside rises from the sidewalk no steeper than 1:1 (a wall
    # of ground right behind a sidewalk leaned over it)
    ds_, sidx_ = ndimage.distance_transform_edt(~np.isfinite(side_top), return_indices=True)
    st_n = side_top[tuple(sidx_)]
    slope_cap = st_n - 0.6 + np.maximum(ds_ * CELL - CELL, 0) * SIDE_BANK
    vis = np.where(np.isfinite(st_n) & (ds_ * CELL <= 24) & ~under & ~bld & (vis > st_n + SIDE_RISE_OK),
                   np.minimum(vis, np.maximum(slope_cap, st_n + SIDE_RISE_OK)), vis)
    near_road = (dr <= 2 * CELL) & onside
    vis = np.where(near_road, np.minimum(vis, road_top[tuple(ridx)] - 0.4), vis)
    vis = np.where(np.isnan(H), np.nan, vis)

    # 6. encode: on open ground use the typical render offset, under roads the worst
    # where the cap holds the ground (within 1.5 of it) the worst-case offset is
    # used too, so the rendered surface never rises over a floor
    delta = np.where(under | (vis >= cap_vis - 1.5) | near_side | onside, DELTA_MAX, DELTA_MED)
    # at a slab's bank: halfway (worst case 0.2 over the edge, typically 1 under)
    delta = np.where(at_bank & ~under & (vis < cap_vis - 1.5), (DELTA_MAX + DELTA_MED) / 2, delta)
    # the offset changes gradually: cells side by side with different offsets
    # encoded steps of up to 1.2 into flat ground (lumps). Only ever raised,
    # so the ground only renders lower than it would
    delta = np.maximum(delta, ndimage.gaussian_filter(delta, 1.5, mode="nearest"))
    delta = np.maximum(delta, ndimage.gaussian_filter(delta, 1.5, mode="nearest"))
    h_file = vis - delta - FILE_TO_STUDIO
    out = D / "terrain"
    for name, c in chunks.items():
        i0, k0 = int(round((c["x0"] - gx0) / CELL)), int(round((c["z0"] - gz0) / CELL))
        hc = h_file[i0:i0 + c["nx"], k0:k0 + c["nz"]]
        c2 = dict(c)
        c2["h"] = [round(float(v), 2) if np.isfinite(v) else round(float(h0), 2)
                   for v, h0 in zip(hc.ravel(), np.array(c["h"]))]
        (out / f"{name}.json").write_text(json.dumps(c2))
    (out / "index.json").write_text(json.dumps(index))
    change = (h_file - H)[~np.isnan(H)]
    print(f"terrain written: change vs clamped natural ground median {np.median(change):+.2f}, "
          f"p5 {np.percentile(change, 5):+.1f}, p95 {np.percentile(change, 95):+.1f} studs -> {out}")


if __name__ == "__main__":
    main()
