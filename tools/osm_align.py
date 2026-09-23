"""Fit OpenStreetMap's Shibuya roads onto the map's stud coordinates.

The FBX arrives in studs with no georeference, so OSM (lat/lon) has to be fitted
to it. The fit is over 4 parameters -- scale, rotation, and the two offsets --
scored by how well OSM's road lines land on the open space between our buildings
(ground_heightfield's `known` mask). Rotation and scale are searched on a grid;
for each pair the best offset comes from an FFT cross-correlation in one step.

  python tools/osm_align.py            -> source_slices/ground/osm_fit.json
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

STUDS_PER_M = 1 / 0.28
CELL = 8.0            # studs per cell for the fit (coarser than the height grid: faster, still sharp)
ROAD_HALF_M = 4.0     # metres: half-width used to paint OSM lines for scoring


FIT_KINDS = {"motorway", "trunk", "primary", "secondary", "tertiary",
             "residential", "unclassified", "living_street"}


def osm_lines(kinds=None):
    d = json.loads((DATA / "osm_roads.json").read_text())
    ways = [w for w in d["elements"] if w.get("geometry")
            and (kinds is None or w.get("tags", {}).get("highway") in kinds)]
    lat0 = np.mean([p["lat"] for w in ways for p in w["geometry"]])
    lon0 = np.mean([p["lon"] for w in ways for p in w["geometry"]])
    mlat = 111132.92 - 559.82 * math.cos(2 * math.radians(lat0)) + 1.175 * math.cos(4 * math.radians(lat0))
    mlon = 111412.84 * math.cos(math.radians(lat0)) - 93.5 * math.cos(3 * math.radians(lat0))
    out = []
    for w in ways:
        pts = [((p["lon"] - lon0) * mlon, (p["lat"] - lat0) * mlat) for p in w["geometry"]]
        out.append((w["tags"].get("highway"), w.get("tags", {}), np.array(pts)))
    return out, (lat0, lon0, mlat, mlon)


def rasterise(lines, transform, shape, x0, z0, cell, half):
    """Paint OSM segments into a mask of `shape` under (scale, rot, tx, tz)."""
    s, rot, tx, tz = transform
    c, sn = math.cos(rot), math.sin(rot)
    mask = np.zeros(shape, dtype=bool)
    r = max(1, int(round(half * STUDS_PER_M * s / cell)))
    for _, _, pts in lines:
        p = pts * STUDS_PER_M * s
        X = p[:, 0] * c - p[:, 1] * sn + tx
        Z = p[:, 0] * sn + p[:, 1] * c + tz
        gi = (X - x0) / cell
        gj = (Z - z0) / cell
        for k in range(len(gi) - 1):
            n = int(max(abs(gi[k + 1] - gi[k]), abs(gj[k + 1] - gj[k]))) + 1
            ii = np.linspace(gi[k], gi[k + 1], n).astype(int)
            jj = np.linspace(gj[k], gj[k + 1], n).astype(int)
            ok = (ii >= 0) & (ii < shape[0]) & (jj >= 0) & (jj < shape[1])
            mask[ii[ok], jj[ok]] = True
    if r > 1:
        mask = ndimage.binary_dilation(mask, np.ones((2 * r + 1, 2 * r + 1)))
    return mask


def main():
    d = np.load(DATA / "heights.npz")
    known, hx0, hz0, hcell = d["known"], float(d["x0"]), float(d["z0"]), float(d["cell"])
    step = int(CELL / hcell)
    free = (~known)[::step, ::step]
    shape = free.shape
    x0, z0 = hx0, hz0
    # score against open space that is street-like (away from the outskirts)
    city = ndimage.binary_dilation(known[::step, ::step], iterations=int(150 / CELL))
    # score: road area on open space MINUS road area on buildings
    target = (free & city).astype(np.float32) - known[::step, ::step].astype(np.float32)
    target -= target.mean()
    F = np.fft.rfft2(target)
    lines, geo = osm_lines(FIT_KINDS)
    print(f"{len(lines)} major ways used for the fit", flush=True)
    best = None
    for rot_deg in np.arange(-180, 180, 1.0):
        for scale in (0.94, 0.97, 1.0, 1.03, 1.06):
            m = rasterise(lines, (scale, math.radians(rot_deg), 0.0, 0.0), shape, x0, z0, CELL, ROAD_HALF_M)
            if m.sum() < 500:
                continue
            a = m.astype(np.float32)
            a -= a.mean()
            corr = np.fft.irfft2(F * np.conj(np.fft.rfft2(a)), s=shape)
            k = int(np.argmax(corr))
            di, dj = np.unravel_index(k, shape)
            di = di if di < shape[0] // 2 else di - shape[0]
            dj = dj if dj < shape[1] // 2 else dj - shape[1]
            score = float(corr[np.unravel_index(k, shape)])
            if best is None or score > best[0]:
                best = (score, scale, rot_deg, di * CELL, dj * CELL)
                print(f"  rot {rot_deg:+.0f} scale {scale} -> offset ({di * CELL:.0f}, {dj * CELL:.0f}) score {score:.0f}", flush=True)
    score, scale, rot_deg, tx, tz = best
    # refine: finer rotation/scale around the winner, offset by correlation again
    for rot_deg2 in np.arange(rot_deg - 1.5, rot_deg + 1.51, 0.25):
        for scale2 in np.arange(scale - 0.03, scale + 0.031, 0.005):
            m = rasterise(lines, (scale2, math.radians(rot_deg2), 0.0, 0.0), shape, x0, z0, CELL, ROAD_HALF_M)
            if m.sum() < 500:
                continue
            a = m.astype(np.float32)
            a -= a.mean()
            corr = np.fft.irfft2(F * np.conj(np.fft.rfft2(a)), s=shape)
            k = np.unravel_index(int(np.argmax(corr)), shape)
            di = k[0] if k[0] < shape[0] // 2 else k[0] - shape[0]
            dj = k[1] if k[1] < shape[1] // 2 else k[1] - shape[1]
            s2 = float(corr[k])
            if s2 > score:
                score, scale, rot_deg, tx, tz = s2, scale2, rot_deg2, di * CELL, dj * CELL
    print(f"best: scale {scale:.4f} rotation {rot_deg:+.2f} deg offset ({tx:.0f}, {tz:.0f}) score {score:.0f}")
    # how much of the OSM road mask lands on open space?
    m = rasterise(lines, (scale, math.radians(rot_deg), tx, tz), shape, x0, z0, CELL, ROAD_HALF_M)
    on = (m & (free & city)).sum() / max(m.sum(), 1)
    hit = (m & known[::step, ::step]).sum() / max(m.sum(), 1)
    print(f"{hit:.1%} of it lands on buildings (lower is better)")
    print(f"{on:.1%} of the fitted OSM road area lands on open space between buildings")
    (DATA / "osm_fit.json").write_text(json.dumps({
        "scale": scale, "rotation_deg": rot_deg, "tx": tx, "tz": tz,
        "studs_per_m": STUDS_PER_M, "lat0": geo[0], "lon0": geo[1], "m_per_deg_lat": geo[2], "m_per_deg_lon": geo[3],
        "on_open_space": on}))
    print(f"-> {DATA / 'osm_fit.json'}")


if __name__ == "__main__":
    main()
