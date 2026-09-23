"""Align OSM to the map by ICP over BUILDING FOOTPRINTS (the honest fit).

Three hand-picked landmarks (Scramble Square, PARCO, Cerulean) give the
starting transform; this refines it against ~900-1,300 matched building
centroids. Scale is pinned to the project's 0.28 m/stud, which the free fit
independently recovered (0.2855). Median residual settles at ~11.5 m: that is
OSM and PLATEAU disagreeing about where a building is (podiums, merged
towers), not transform error -- a full affine fit only reached 11.4 m while
distorting the scale, so there is no skew to correct.

  python tools/osm_icp.py   -> updates source_slices/ground/osm_fit.json
"""
import sys, json, math
sys.path.insert(0, r"D:\GameDownloads\JJK_Roblox\tools")
import source_slice_pipeline
import numpy as np
from scipy.spatial import cKDTree
import ground_heightfield as G, osm_align as A

fit = json.loads((A.DATA/"osm_fit.json").read_text())
lat0, lon0, mlat, mlon = fit["lat0"], fit["lon0"], fit["m_per_deg_lat"], fit["m_per_deg_lon"]
S = 1/0.28   # pinned: the project's stud size

dd = json.loads((A.DATA/"osm_buildings.json").read_text())
P, Pa = [], []
for w in dd["elements"]:
    g = w.get("geometry")
    if not g or len(g) < 4: continue
    pts = np.array([[(p["lon"]-lon0)*mlon, (p["lat"]-lat0)*mlat] for p in g])
    x, y = pts[:,0], pts[:,1]
    a = 0.5*abs(np.dot(x, np.roll(y,-1)) - np.dot(y, np.roll(x,-1)))
    if a < 40: continue
    P.append(pts.mean(0)); Pa.append(a)
P = np.array(P); Pa = np.array(Pa)
ours, _ = G.grounded(G.pins())
Q = np.array([[p.centroid.x, p.centroid.y] for p, _ in ours]); Qa = np.array([p.area for p, _ in ours])
tree = cKDTree(Q)
rot, tx, tz = math.radians(174.629), 2450.0, -428.0

def apply(P, rot, tx, tz):
    c, sn = math.cos(rot), math.sin(rot)
    x = P[:,0]*S; y = -P[:,1]*S
    return np.stack([x*c - y*sn + tx, x*sn + y*c + tz], axis=1)

for it in range(60):
    T = apply(P, rot, tx, tz)
    d, idx = tree.query(T, k=1)
    ratio = np.maximum(Pa*S*S, Qa[idx]) / np.maximum(np.minimum(Pa*S*S, Qa[idx]), 1)
    keep = (d < 90) & (ratio < 2.5)
    if keep.sum() < 50: break
    src = np.stack([P[keep][:,0], -P[keep][:,1]], axis=1) * S
    dst = Q[idx[keep]]
    mp, mq = src.mean(0), dst.mean(0)
    X, Y = src-mp, dst-mq
    U, s_, Vt = np.linalg.svd(X.T @ Y)
    D = np.eye(2)
    if np.linalg.det(U@Vt) < 0: D[1,1] = -1
    R = (U @ D @ Vt).T                      # rotation only: scale stays pinned
    t = mq - (R @ mp)
    rot = math.atan2(R[1,0], R[0,0]); tx, tz = t[0], t[1]
    resid = np.linalg.norm(dst - (src @ R.T + t), axis=1)
    if it % 15 == 0 or it == 59:
        print(f"  iter {it}: {keep.sum()} matches, median residual {np.median(resid):.1f} studs ({np.median(resid)*0.28:.1f} m), rot {math.degrees(rot):+.3f}")
print(f"final: scale {S:.4f} studs/m (0.28 m/stud), rotation {math.degrees(rot):+.3f}, offset ({tx:.1f}, {tz:.1f})")
fit.update({"studs_per_m": S, "rotation_deg": math.degrees(rot), "tx": float(tx), "tz": float(tz), "mirror_y": True,
            "fit": "ICP over OSM vs map building centroids, scale pinned to 0.28 m/stud"})
json.dump(fit, open(A.DATA/"osm_fit.json","w"))
