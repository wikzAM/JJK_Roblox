"""Road and pavement slabs from OpenStreetMap, laid on the map's ground.

OSM gives the real street network (classes, lanes, one-ways, pedestrian
streets); `tile_georef.json` puts it in stud coordinates -- an exact
georeference through JGD2011 CS IX, not a fit (see jgd_cs9.py, and the handoff
doc's "THE STUD SIZE" for why fitting it failed three times). Roads are clipped
to CITY_MARGIN studs past the outermost building, because OSM's bbox is wider
than the FBX and the rest would hang over nothing. Each way is cut into
segments of at most SEGMENT studs, and each segment becomes:

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
APRON = 64.0        # studs: the grid of plaza/apron slabs that cover open ground
APRON_MIN = 0.12    # emit an apron where at least this much of its square is open ground
APRON_SINK = 0.15   # studs below the surface, so roads and pavements read on top
CITY_MARGIN = 150.0 # studs past the outermost building that the map still covers
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
    # EXACT georeference: lat/lon -> JGD2011 CS IX metres (the projection the
    # PLATEAU tiles use) -> studs, from tools/tile_georef.py. Fitting OSM to the
    # map by eye-less scoring produced confident nonsense three times; the tiles
    # settle it, and they also show the map is 0.2391 m/stud, not the 0.28 in
    # CLAUDE.md -- a 17% error that alone threw roads hundreds of studs out.
    import jgd_cs9
    georef = json.loads((DATA / "tile_georef.json").read_text())
    s, rot = georef["studs_per_m"], math.radians(georef["rotation_deg"])
    mirror = -1.0 if georef["mirror_y"] else 1.0
    toff = georef["t"]
    c, sn = math.cos(rot), math.sin(rot)

    def latlon_to_studs(lat, lon):
        e, n = jgd_cs9.to_xy(lat, lon)
        x, y = e * s, mirror * n * s
        return x * c - y * sn + toff[0], x * sn + y * c + toff[1]
    S, x0, z0, cell = surface()
    inside = np.load(DATA / "heights.npz")["known"]      # building footprints
    # OSM covers a wider area than the FBX does, so a third of the slabs landed
    # past the edge of the ground we actually built and would hang over nothing.
    # The map ends where the buildings end: keep roads inside the same margin the
    # aprons use, so the roadway and the ground under it run out together.
    city = ndimage.binary_dilation(inside, iterations=int(CITY_MARGIN / cell))

    def in_city(x, z):
        i = int(round((x - x0) / cell))
        j = int(round((z - z0) / cell))
        return 0 <= i < city.shape[0] and 0 <= j < city.shape[1] and bool(city[i, j])

    def in_building(x, z):
        i = int(round((x - x0) / cell))
        j = int(round((z - z0) / cell))
        return 0 <= i < inside.shape[0] and 0 <= j < inside.shape[1] and bool(inside[i, j])

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
        pts = [latlon_to_studs(p["lat"], p["lon"]) for p in g]
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
                cx_, cz_ = (px + qx) / 2, (pz + qz) / 2
                # a roadway inside a footprint is buried under that building's
                # floor: OSM and PLATEAU disagree by ~11 m (their building
                # outlines differ), so some slabs land there. Skip them.
                if in_building(cx_, cz_):
                    continue
                if not in_city(cx_, cz_):
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
                    for side in (-1, 1):   # pavements MAY run under buildings: that is what hides their outer edge
                        ox = -math.sin(yaw) * side * (road_w + walk_w) / 2
                        oz = math.cos(yaw) * side * (road_w + walk_w) / 2
                        wx, wz = cx + ox, cz + oz
                        rows.append(["pavement", round(wx, 2), round(ground(wx, wz) + CURB + priority * 0.05, 2),
                                     round(wz, 2), round(yaw, 5), round(pitch, 5),
                                     round(length, 2), round(THICKNESS, 2), round(walk_w, 2), kind, w["id"]])
                        counts["pavement"] += 1
    # APRONS: the ground between the roads. Terrain alone terraces on gentle
    # slopes (it rebuilds its surface from voxel occupancy), so the open space
    # gets flat slabs too -- they may overlap buildings and roads, exactly as the
    # pavements do, which is what keeps them to one part per 64-stud square.
    covered = np.zeros(inside.shape, bool)
    for rows in tiles.values():
        for r in rows:
            _, cx_, _, cz_, yaw_, _, length_, _, width_ = r[:9]
            cc, ss = math.cos(yaw_), math.sin(yaw_)
            for a in np.linspace(-length_ / 2, length_ / 2, max(2, int(length_ / cell) + 1)):
                for b in np.linspace(-width_ / 2, width_ / 2, max(2, int(width_ / cell) + 1)):
                    i = int(round((cx_ + a * cc - b * ss - x0) / cell))
                    j = int(round((cz_ + a * ss + b * cc - z0) / cell))
                    if 0 <= i < inside.shape[0] and 0 <= j < inside.shape[1]:
                        covered[i, j] = True
    bare = (~inside) & city & (~covered)
    n_apron = 0
    steps = int(APRON / cell)
    for i0 in range(0, inside.shape[0] - steps, steps):
        for j0 in range(0, inside.shape[1] - steps, steps):
            block = bare[i0:i0 + steps, j0:j0 + steps]
            if block.mean() < APRON_MIN:
                continue
            cx_ = x0 + (i0 + steps / 2) * cell
            cz_ = z0 + (j0 + steps / 2) * cell
            h00, h10 = ground(cx_ - APRON / 2, cz_ - APRON / 2), ground(cx_ + APRON / 2, cz_ - APRON / 2)
            h01, h11 = ground(cx_ - APRON / 2, cz_ + APRON / 2), ground(cx_ + APRON / 2, cz_ + APRON / 2)
            # one plane through the square: yaw 0, pitched along x, rolled along z
            pitch = math.atan2(((h10 + h11) - (h00 + h01)) / 2, APRON)
            roll = math.atan2(((h01 + h11) - (h00 + h10)) / 2, APRON)
            y = (h00 + h10 + h01 + h11) / 4 - APRON_SINK
            key = (int(math.floor(cx_ / TILE)), int(math.floor(cz_ / TILE)))
            tiles.setdefault(key, []).append(
                ["apron", round(cx_, 2), round(y, 2), round(cz_, 2), round(roll, 5), round(pitch, 5),
                 round(APRON + 2, 2), round(THICKNESS, 2), round(APRON + 2, 2), "apron", 0])
            n_apron += 1
    counts["apron"] = n_apron

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
    print(f"{counts['roadway']} roadway + {counts['pavement']} pavement + {counts['apron']} apron slabs = "
          f"{counts['roadway'] + counts['pavement'] + counts['apron']} parts over {len(names)} tiles; "
          f"{total_len:,.0f} studs of roadway ({total_len * 0.28 / 1000:.1f} km)")
    print(f"largest tile {max(n for _, n in names)} parts -> {out}")


if __name__ == "__main__":
    main()
