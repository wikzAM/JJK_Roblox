"""Road and pavement slabs from OpenStreetMap, laid on the map's ground.

OSM gives the real street network (classes, lanes, one-ways, pedestrian
streets); `osm_fit.json` puts it in stud coordinates (fitted from three landmark
buildings: Shibuya Scramble Square, PARCO, the Cerulean Tower). Each way is cut
into segments of at most SEGMENT studs, and each segment becomes:

  * one ROADWAY slab, tilted to the ground's slope, its top at the ground
    surface, THICKNESS studs deep so it covers the terrain's voxel steps;
  * one PAVEMENT strip per side, raised CURB studs. The strips are deliberately
    wide and simply run under the buildings' ground-floor slabs, which hides
    their outer edge -- so they never have to follow a building outline.

Slabs of a higher class sit a hair above lower ones so crossings do not
z-fight. Output is grouped into 512-stud tiles, matching the ground tiles, so
roads stream and regenerate a neighbourhood at a time.

  python tools/road_parts.py    -> source_slices/ground/roads/tile_*.json + index.json
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

SEGMENT = 200.0     # studs: longest road slab (straight runs merge first, so most are this long)
SIMPLIFY = 2.0      # studs: way simplification before segmenting
THICKNESS = 8.0     # studs: slab depth, covering terrain steps under it
CURB = 1.0          # studs the pavement stands above the roadway
TILE = 512.0
LANE_M = 3.25       # metres per lane when a way tags lanes

# metres: roadway width, pavement width each side, and draw priority
KIND = {
    "motorway":     (20.0, 0.0, 6),
    "trunk":        (18.0, 4.0, 5),
    "primary":      (16.0, 5.0, 4),
    "secondary":    (13.0, 4.5, 3),
    "tertiary":     (10.0, 4.0, 2),
    "residential":  (8.0, 3.0, 1),
    "unclassified": (7.0, 3.0, 1),
    "living_street": (6.0, 2.0, 1),
    "service":      (5.0, 0.0, 0),
    "pedestrian":   (9.0, 0.0, 1),
    # footways are left out: 1,899 of them in the bbox, and the pavement strips
    # beside every street already cover walking space.
}


def simplify(pts, tol):
    """Douglas-Peucker: OSM ways carry a vertex every few metres; straight runs
    become one long slab instead of a dozen."""
    if len(pts) < 3:
        return pts
    a, b = np.array(pts[0]), np.array(pts[-1])
    ab = b - a
    n = float(np.hypot(*ab))
    arr = np.array(pts)
    rel = arr - a
    d = np.abs(rel[:, 0] * ab[1] - rel[:, 1] * ab[0]) / n if n > 1e-9 else np.hypot(rel[:, 0], rel[:, 1])
    k = int(np.argmax(d))
    if d[k] <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[:k + 1], tol)[:-1] + simplify(pts[k:], tol)


def surface():
    """The ground surface the roads sit on: the same field the terrain uses."""
    d = np.load(DATA / "heights.npz")
    H, known, x0, z0, cell = d["H"], d["known"], float(d["x0"]), float(d["z0"]), float(d["cell"])
    import ground_terrain as G
    floors = np.where(known, H, np.inf)
    street = ndimage.gaussian_filter(H, G.STREET_SIGMA / cell, mode="nearest")
    U = floors - G.FACE_DROP
    step, diag = G.CONE * cell, G.CONE * cell * 2 ** 0.5
    for _ in range(400):
        p = np.pad(U, 1, mode="edge")
        new = np.minimum.reduce([U, p[:-2, 1:-1] + step, p[2:, 1:-1] + step, p[1:-1, :-2] + step, p[1:-1, 2:] + step,
                                 p[:-2, :-2] + diag, p[:-2, 2:] + diag, p[2:, :-2] + diag, p[2:, 2:] + diag])
        if np.array_equal(new, U):
            break
        U = new
    street = np.minimum(street, U)
    street = np.minimum(ndimage.gaussian_filter(street, 2.0, mode="nearest"), U)
    S = np.where(known, H - 0.9, street)
    return S, x0, z0, cell


def main():
    fit = json.loads((DATA / "osm_fit.json").read_text())
    s, rot, tx, tz = fit["studs_per_m"], math.radians(fit["rotation_deg"]), fit["tx"], fit["tz"]
    lat0, lon0, mlat, mlon = fit["lat0"], fit["lon0"], fit["m_per_deg_lat"], fit["m_per_deg_lon"]
    c, sn = math.cos(rot), math.sin(rot)
    S, x0, z0, cell = surface()

    def ground(x, z):
        fi = min(max((x - x0) / cell, 0), S.shape[0] - 1.001)
        fj = min(max((z - z0) / cell, 0), S.shape[1] - 1.001)
        i, j = int(fi), int(fj)
        u, v = fi - i, fj - j
        return float(S[i, j] * (1 - u) * (1 - v) + S[i + 1, j] * u * (1 - v)
                     + S[i, j + 1] * (1 - u) * v + S[i + 1, j + 1] * u * v)

    d = json.loads((DATA / "osm_roads.json").read_text())
    x1, z1 = x0 + (S.shape[0] - 1) * cell, z0 + (S.shape[1] - 1) * cell
    tiles, counts, total_len = {}, {"roadway": 0, "pavement": 0}, 0.0
    for w in d["elements"]:
        g = w.get("geometry")
        tags = w.get("tags", {})
        kind = tags.get("highway")
        if not g or kind not in KIND:
            continue
        road_m, walk_m, priority = KIND[kind]
        if tags.get("lanes", "").isdigit():
            road_m = max(road_m, int(tags["lanes"]) * LANE_M + 1.0)
        road_w, walk_w = road_m * s, walk_m * s
        pts = []
        for p in g:
            mx, my = (p["lon"] - lon0) * mlon, (p["lat"] - lat0) * mlat
            ax, ay = mx * s, -my * s                      # the fit mirrors north
            pts.append((ax * c - ay * sn + tx, ax * sn + ay * c + tz))
        pts = simplify(pts, SIMPLIFY)
        for k in range(len(pts) - 1):
            ax, az = pts[k]
            bx, bz = pts[k + 1]
            seg = math.hypot(bx - ax, bz - az)
            if seg < 1.0:
                continue
            n = max(1, int(math.ceil(seg / SEGMENT)))
            for t in range(n):
                t0, t1 = t / n, (t + 1) / n
                px, pz = ax + (bx - ax) * t0, az + (bz - az) * t0
                qx, qz = ax + (bx - ax) * t1, az + (bz - az) * t1
                if not (x0 < px < x1 and z0 < pz < z1):
                    continue
                length = math.hypot(qx - px, qz - pz) + 2.0      # overlap the next slab
                cx, cz = (px + qx) / 2, (pz + qz) / 2
                yaw = math.atan2(qz - pz, qx - px)
                y0, y1 = ground(px, pz), ground(qx, qz)
                pitch = math.atan2(y1 - y0, max(math.hypot(qx - px, qz - pz), 1e-6))
                y = (y0 + y1) / 2 + priority * 0.05
                total_len += length
                key = (int(math.floor(cx / TILE)), int(math.floor(cz / TILE)))
                rows = tiles.setdefault(key, [])
                rows.append(["roadway", round(cx, 2), round(y, 2), round(cz, 2), round(yaw, 5), round(pitch, 5),
                             round(length, 2), round(THICKNESS, 2), round(road_w, 2), kind, w["id"]])
                counts["roadway"] += 1
                if walk_w >= 2.0:
                    for side in (-1, 1):
                        ox = -math.sin(yaw) * side * (road_w + walk_w) / 2
                        oz = math.cos(yaw) * side * (road_w + walk_w) / 2
                        wx, wz = cx + ox, cz + oz
                        rows.append(["pavement", round(wx, 2), round(ground(wx, wz) + CURB + priority * 0.05, 2),
                                     round(wz, 2), round(yaw, 5), round(pitch, 5),
                                     round(length, 2), round(THICKNESS, 2), round(walk_w, 2), kind, w["id"]])
                        counts["pavement"] += 1
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
    print(f"{counts['roadway']} roadway + {counts['pavement']} pavement slabs = "
          f"{counts['roadway'] + counts['pavement']} parts over {len(names)} tiles; "
          f"{total_len:,.0f} studs of roadway ({total_len * 0.28 / 1000:.1f} km)")
    print(f"largest tile {max(n for _, n in names)} parts -> {out}")


if __name__ == "__main__":
    main()
