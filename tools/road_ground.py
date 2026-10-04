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
MEET = 0.6        # open ground aimed this far above the road surface it continues
EDGE = 4.0        # under a slab within this of its edge, the ground stays just below it
DEEP = 2.2        # ... and this far below it deeper in (isolated voxels render as peaks)
FAR = 60.0        # beyond this from any road the ground blends back to natural
SMOOTH_PASSES = 6
BAND = 8.0        # studs beside a building where the ground comes up under its ground floor
FLUSH_GAP = 0.5   # ... to this far under the visible cap (cap = slab top - 1)
ROAD_CLEAR = 8.0  # ... fully only this far from a road
MAX_RAISE = 10.0  # ... and by no more than this


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
    for name, _ in json.loads((roads / "index.json").read_text()):
        for r in json.loads((roads / f"{name}.json").read_text())["slabs"]:
            if r[0] != "roadway":
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
    for x, z, rad, h in json.loads((roads / "junctions.json").read_text()):
        i0 = max(int((x - rad - gx0) / CELL), 0); i1 = min(int((x + rad - gx0) / CELL) + 1, NX)
        k0 = max(int((z - rad - gz0) / CELL), 0); k1 = min(int((z + rad - gz0) / CELL) + 1, NZ)
        X, Z = np.meshgrid(XC[i0:i1], ZC[k0:k1], indexing="ij")
        disc = (X - x) ** 2 + (Z - z) ** 2 <= rad * rad
        sub = known[i0:i1, k0:k1]
        sub[disc & np.isnan(sub)] = h + MEET
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
    wnat = np.clip((dist - FAR / 2) / FAR, 0, 1)
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
    want = np.minimum(cap_vis - FLUSH_GAP, vis + MAX_RAISE)
    vis = np.where(near_b & ~under, np.maximum(vis, vis + (want - vis) * w_road * (want > vis)), vis)
    vis = np.minimum(vis, cap_vis)
    vis = np.where(bld, natural_vis, vis)
    vis = np.where(np.isnan(H), np.nan, vis)

    # 6. encode: on open ground use the typical render offset, under roads the worst
    delta = np.where(under, DELTA_MAX, DELTA_MED)
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
