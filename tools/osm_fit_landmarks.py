"""Fit OSM to the map from LANDMARK BUILDINGS, then polish locally.

ICP over building centroids was tried and is a trap: in a dense, repetitive
city it converged to an internally consistent fit that was 2,400 studs (670 m)
out, because its residual measures self-consistency, not correctness. Three
landmarks whose position is known in BOTH frames pin the fit absolutely; the
polish that follows is deliberately limited to +/-80 studs, +/-1.5 degrees and
+/-2% so it can never slide to another neighbourhood.

  python tools/osm_fit_landmarks.py   -> source_slices/ground/osm_fit.json
"""
from pathlib import Path
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices" / "ground"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402

# (name, studs x, studs z, lat, lon) -- the map positions come from the plans:
# Shibuya Sky is orphans.PROTECTED, PARCO is orph_703_1736, the Cerulean is
# fbx_6_4510_4915_-8852 (its crown is one of the 22 hand-approved ones).
LANDMARKS = [
    ("Shibuya Scramble Square / Shibuya Sky", -630.0, 48.0, 35.65800, 139.70160),
    ("Shibuya PARCO", 705.0, 1720.0, 35.66258, 139.69867),
    ("Cerulean Tower", 451.0, -885.0, 35.65600, 139.69790),
]


def main():
    lat0 = float(np.mean([l[3] for l in LANDMARKS]))
    lon0 = float(np.mean([l[4] for l in LANDMARKS]))
    mlat = 111132.92 - 559.82 * math.cos(2 * math.radians(lat0)) + 1.175 * math.cos(4 * math.radians(lat0))
    mlon = 111412.84 * math.cos(math.radians(lat0)) - 93.5 * math.cos(3 * math.radians(lat0))
    P = np.array([[(l[4] - lon0) * mlon, (l[3] - lat0) * mlat] for l in LANDMARKS])
    Q = np.array([[l[1], l[2]] for l in LANDMARKS])
    # mirror north (the map's Z runs opposite), then a plain similarity fit
    Pm = np.stack([P[:, 0], -P[:, 1]], axis=1)
    mp, mq = Pm.mean(0), Q.mean(0)
    X, Y = Pm - mp, Q - mq
    U, S, Vt = np.linalg.svd(X.T @ Y / len(Pm))
    D = np.eye(2)
    if np.linalg.det(U @ Vt) < 0:
        D[1, 1] = -1
    R = (U @ D @ Vt).T
    scale = float((S @ np.diag(D)).sum() / (X ** 2).sum() * len(Pm))
    t = mq - scale * (R @ mp)
    rot = math.degrees(math.atan2(R[1, 0], R[0, 0]))
    err = np.linalg.norm(Q - (scale * (Pm @ R.T) + t), axis=1)
    print(f"landmarks: {scale:.4f} studs/m ({1 / scale:.4f} m/stud), rotation {rot:+.2f}, "
          f"offset ({t[0]:.0f}, {t[1]:.0f}); residuals {np.round(err).tolist()} studs")

    # polish: keep roads off buildings, but only within a short leash
    d = np.load(DATA / "heights.npz")
    known, hx0, hz0, hcell = d["known"], float(d["x0"]), float(d["z0"]), float(d["cell"])
    CELL = 8.0
    step = int(CELL / hcell)
    kn = known[::step, ::step]
    shape = kn.shape
    city = ndimage.binary_dilation(kn, iterations=int(150 / CELL))
    dd = json.loads((DATA / "osm_roads.json").read_text())
    import osm_align as A
    ways = [np.array([[(p["lon"] - lon0) * mlon, (p["lat"] - lat0) * mlat] for p in w["geometry"]])
            for w in dd["elements"] if w.get("geometry") and w.get("tags", {}).get("highway") in A.FIT_KINDS]

    def score(s, rotdeg, tx, tz, half=4.0):
        c, sn = math.cos(math.radians(rotdeg)), math.sin(math.radians(rotdeg))
        m = np.zeros(shape, bool)
        r = max(1, int(round(half * s / CELL)))
        for pts in ways:
            x, y = pts[:, 0] * s, -pts[:, 1] * s
            X_, Z_ = x * c - y * sn + tx, x * sn + y * c + tz
            gi, gj = (X_ - hx0) / CELL, (Z_ - hz0) / CELL
            for k in range(len(gi) - 1):
                n = int(max(abs(gi[k + 1] - gi[k]), abs(gj[k + 1] - gj[k]))) + 1
                ii = np.linspace(gi[k], gi[k + 1], n).astype(int)
                jj = np.linspace(gj[k], gj[k + 1], n).astype(int)
                ok = (ii >= 0) & (ii < shape[0]) & (jj >= 0) & (jj < shape[1])
                m[ii[ok], jj[ok]] = True
        m = ndimage.binary_dilation(m, np.ones((2 * r + 1, 2 * r + 1))) if r > 1 else m
        inside = m & city
        tot = max(inside.sum(), 1)
        return (inside & ~kn).sum() / tot - (inside & kn).sum() / tot

    def landmark_error(s, rotdeg, tx, tz):
        c, sn = math.cos(math.radians(rotdeg)), math.sin(math.radians(rotdeg))
        worst = 0.0
        for _, ex, ez, la, lo in LANDMARKS:
            mx, my = (lo - lon0) * mlon, (la - lat0) * mlat
            x, y = mx * s, -my * s
            worst = max(worst, math.hypot(x * c - y * sn + tx - ex, x * sn + y * c + tz - ez))
        return worst

    # the polish may not move a landmark further than this: chasing the road
    # score alone walked them 145 studs off, which is how ICP got lost
    MAX_LANDMARK_ERROR = 60.0
    best = (score(scale, rot, t[0], t[1]), scale, rot, float(t[0]), float(t[1]))
    print(f"  landmark fit scores {best[0]:+.3f} (open minus buildings)")
    for drot in (-1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5):
        for ds in (0.98, 0.99, 1.0, 1.01, 1.02):
            for dx in range(-80, 81, 20):
                for dz in range(-80, 81, 20):
                    if landmark_error(scale * ds, rot + drot, t[0] + dx, t[1] + dz) > MAX_LANDMARK_ERROR:
                        continue
                    v = score(scale * ds, rot + drot, t[0] + dx, t[1] + dz)
                    if v > best[0]:
                        best = (v, scale * ds, rot + drot, float(t[0] + dx), float(t[1] + dz))
    v, s, r, tx, tz = best
    print(f"polished: {s:.4f} studs/m, rotation {r:+.2f}, offset ({tx:.0f}, {tz:.0f}), score {v:+.3f}")
    for name, ex, ez, la, lo in LANDMARKS:
        c, sn = math.cos(math.radians(r)), math.sin(math.radians(r))
        mx, my = (lo - lon0) * mlon, (la - lat0) * mlat
        x, y = mx * s, -my * s
        gx, gz = x * c - y * sn + tx, x * sn + y * c + tz
        print(f"  {name:38s} off by {math.hypot(gx - ex, gz - ez):.0f} studs")
    (DATA / "osm_fit.json").write_text(json.dumps({
        "studs_per_m": s, "rotation_deg": r, "tx": tx, "tz": tz, "mirror_y": True,
        "lat0": lat0, "lon0": lon0, "m_per_deg_lat": mlat, "m_per_deg_lon": mlon,
        "fit": "3 landmark buildings + local polish (ICP over centroids drifts 2,400 studs)"}))
    print(f"-> {DATA / 'osm_fit.json'}")


if __name__ == "__main__":
    main()
