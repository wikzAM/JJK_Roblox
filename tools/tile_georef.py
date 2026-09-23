"""Georeference the map from the PLATEAU source tiles (exact, not fitted).

The per-tile FBX files under the PLATEAU download are named by Japanese mesh
code and are in JGD2011 Plane Rectangular CS IX (EPSG:6677), 100 m per unit --
tile 53393586 covers Shibuya station and its tallest building measures 184 m,
which is Hikarie. The map's own geometry came from a combined Shibuya.fbx that
was recentred on export, so the link between them has to be recovered once:

  * a candidate pairing of one tall building in each set fixes SCALE (its height
    in studs against its height in metres);
  * a second pairing fixes ROTATION and the offset;
  * the score is the fraction of the TILE's buildings that land on one of ours,
    which cannot be inflated by spreading the template out (the trap that made
    plain correlation and ICP produce confident nonsense).

  python tools/tile_georef.py <tile_buildings.json> [--code 53393586]
"""
from pathlib import Path
import argparse
import itertools
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402


def our_buildings(min_height=90.0):
    d = np.load(DATA / "world_triangles.npz")
    tri, comp = d["triangles"], d["component"]
    order = np.argsort(comp)
    tri, comp = tri[order], comp[order]
    rows = []
    for g in np.split(np.arange(len(comp)), np.flatnonzero(np.diff(comp)) + 1):
        if len(g) < 6:
            continue
        t = tri[g]
        h = float(t[:, :, 1].max() - t[:, :, 1].min())
        if h < min_height:
            continue
        w = float(t[:, :, 0].max() - t[:, :, 0].min())
        dd = float(t[:, :, 2].max() - t[:, :, 2].min())
        rows.append([float(t[:, :, 0].mean()), float(t[:, :, 2].mean()), h, max(w, dd)])
    return np.array(rows)


def tile_buildings(path, min_height_m=25.0):
    rows = []
    for r in json.loads(Path(path).read_text()):
        h = (r["zhi"] - r["zlo"]) * 100.0
        if h < min_height_m:
            continue
        rows.append([r["cx"] * 100.0, r["cy"] * 100.0, h, max(r["w"], r["d"]) * 100.0])
    return np.array(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tile")
    ap.add_argument("--code", default="53393586")
    ap.add_argument("--tol", type=float, default=45.0, help="studs a tile building may miss ours by")
    args = ap.parse_args()
    O = our_buildings()
    T = tile_buildings(args.tile)
    print(f"ours {len(O)} tall components, tile {len(T)} buildings over 25 m")
    tree = cKDTree(O[:, :2])
    # candidates: the tallest in each set, pairs whose height ratio agrees
    oi = np.argsort(-O[:, 2])[:40]
    ti = np.argsort(-T[:, 2])[:40]
    best = None
    for a, b in itertools.combinations(oi, 2):
        da = O[b, :2] - O[a, :2]
        la = float(np.hypot(*da))
        if la < 200:
            continue
        for c, e in itertools.permutations(ti, 2):
            s1 = O[a, 2] / T[c, 2]
            s2 = O[b, 2] / T[e, 2]
            if abs(s1 / s2 - 1) > 0.10:          # both pairings must imply one scale
                continue
            s = (s1 + s2) / 2
            if not 2.5 <= s <= 5.5:               # studs per metre, sanity
                continue
            dc = T[e, :2] - T[c, :2]
            if abs(la / (s * float(np.hypot(*dc)) + 1e-9) - 1) > 0.08:
                continue
            for flip in (1, -1):
                v = np.array([dc[0], flip * dc[1]])
                ang = math.atan2(da[1], da[0]) - math.atan2(v[1], v[0])
                R = np.array([[math.cos(ang), -math.sin(ang)], [math.sin(ang), math.cos(ang)]])
                P = np.stack([T[:, 0], flip * T[:, 1]], axis=1)
                mapped = s * (P @ R.T)
                mapped += O[a, :2] - (s * (R @ np.array([T[c, 0], flip * T[c, 1]])))
                dist, idx = tree.query(mapped, k=1)
                # a tile building counts only if OUR building is a similar height
                ok = (dist < args.tol) & (np.abs(O[idx, 2] / (T[:, 2] * s) - 1) < 0.25)
                frac = ok.mean()
                if best is None or frac > best[0]:
                    best = (frac, s, math.degrees(ang), flip,
                            (O[a, :2] - (s * (R @ np.array([T[c, 0], flip * T[c, 1]])))).tolist(), int(ok.sum()))
                    print(f"  matched {ok.sum():4d}/{len(T)} ({frac:.1%}) scale {s:.3f} studs/m "
                          f"({1 / s:.4f} m/stud) rot {math.degrees(ang):+.2f} flip {flip}", flush=True)
    frac, s, rot, flip, t, n = best
    print(f"\nBEST: {n}/{len(T)} tile buildings matched ({frac:.1%})")
    print(f"  scale {s:.4f} studs/m = {1 / s:.4f} m per stud")
    print(f"  rotation {rot:+.3f} deg, mirror {'yes' if flip < 0 else 'no'}, offset ({t[0]:.1f}, {t[1]:.1f})")
    # the tile's mesh code gives its true corner, so studs -> lat/lon follows
    code = args.code
    lat = (int(code[0:2]) / 1.5) + int(code[4]) * (1 / 12) + int(code[6]) * (1 / 120)
    lon = (int(code[2:4]) + 100) + int(code[5]) * 0.125 + int(code[7]) * 0.0125
    print(f"  tile {code} south-west corner: {lat:.6f} N, {lon:.6f} E")
    (DATA / "ground" / "tile_georef.json").write_text(json.dumps(
        {"studs_per_m": s, "rotation_deg": rot, "mirror_y": flip < 0, "t": t,
         "tile_code": code, "tile_sw_lat": lat, "tile_sw_lon": lon,
         "matched": n, "of": len(T), "source": "PLATEAU tile in EPSG:6677, 100 m units"}, indent=1))


if __name__ == "__main__":
    main()
