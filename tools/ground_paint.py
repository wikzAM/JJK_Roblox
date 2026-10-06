"""Paint map for the ground: which terrain columns are street, pavement or
under a building, from the LIVE ground-floor footprints.

In Shibuya almost all open ground between buildings is paved street, so open
ground is Asphalt, a SIDEWALK-wide band along every building is Pavement, and
columns under a footprint are left alone. The road PARTS sit on top of this;
wherever they cannot go (a pinch, a plaza, a gap) the ground is still road.

One file per GroundTerrain chunk (same 512-stud grid), 128 rows of 128 chars:
  a = asphalt, s = pavement, b = under a building, - = outside the city
  python tools/ground_paint.py   -> source_slices/ground/paint/chunk_i_k.txt
"""
import json
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from scipy import ndimage  # noqa: E402

D = ROOT / "source_slices" / "ground"
SIDEWALK = 8.0      # studs of pavement along every building (road_fit keeps MARGIN 2 + SIDEWALK_BAND 6 clear)
SIDE_MAX = 24.0     # studs: the most sidewalk painted beside a street slab (to the building face)
CITY_MARGIN = 400.0   # the station plaza is >150 studs from any building; it showed as bare concrete


def main():
    lf = np.load(D / "live_footprints.npz")
    M, x0, z0, c = lf["mask"], float(lf["x0"]), float(lf["z0"]), float(lf["cell"])
    dist = ndimage.distance_transform_edt(~M) * c
    city = dist <= CITY_MARGIN
    # SIDEWALKS (owner, Oct 6: "properly sized sidewalks"): beside every street
    # slab, the strip from its edge out to the building face (at most SIDE_MAX)
    # is pavement; the slab's own footprint stays asphalt
    import math
    side = np.zeros_like(M)
    road = np.zeros_like(M)
    NXm, NZm = M.shape
    for t_ in json.loads((D / "roads" / "index.json").read_text()):
        for r in json.loads((D / "roads" / f"{t_[0]}.json").read_text())["slabs"]:
            if r[0] not in ("roadway", "pad"):
                continue
            _, rx, _, rz, yaw, _, Ln, _, W = r[:9]
            ux, uz = math.cos(yaw), math.sin(yaw)
            ext = math.hypot(Ln, W) / 2 + SIDE_MAX + 2
            i0 = max(int((rx - ext - x0) / c), 0); i1 = min(int((rx + ext - x0) / c) + 1, NXm)
            k0 = max(int((rz - ext - z0) / c), 0); k1 = min(int((rz + ext - z0) / c) + 1, NZm)
            if i1 <= i0 or k1 <= k0:
                continue
            I, K = np.meshgrid(np.arange(i0, i1), np.arange(k0, k1), indexing="ij")
            X = x0 + (I + 0.5) * c - rx; Z = z0 + (K + 0.5) * c - rz
            a = X * ux + Z * uz; b = -X * uz + Z * ux
            along = np.abs(a) <= Ln / 2
            road[i0:i1, k0:k1] |= along & (np.abs(b) <= W / 2)
            if r[0] == "roadway":
                side[i0:i1, k0:k1] |= along & (np.abs(b) > W / 2) & (np.abs(b) <= W / 2 + SIDE_MAX)
    side &= ~road & ~M
    # junction gaps stay asphalt (the streets meet across them); everything else
    # open is pavement (owner, Oct 6: verify the roads -- open lots painted asphalt
    # read as road)
    jroad = np.zeros_like(M)
    for jn in json.loads((D / "roads" / "junctions.json").read_text()):
        jx, jz, jr = jn[0], jn[1], jn[2]
        i0 = max(int((jx - jr - x0) / c), 0); i1 = min(int((jx + jr - x0) / c) + 1, NXm)
        k0 = max(int((jz - jr - z0) / c), 0); k1 = min(int((jz + jr - z0) / c) + 1, NZm)
        if i1 <= i0 or k1 <= k0:
            continue
        I, K = np.meshgrid(np.arange(i0, i1), np.arange(k0, k1), indexing="ij")
        jroad[i0:i1, k0:k1] |= (x0 + (I + 0.5) * c - jx) ** 2 + (z0 + (K + 0.5) * c - jz) ** 2 <= jr * jr
    road |= jroad & ~M
    # every drivable OSM street at its OSM width, built or not: the main roads are
    # to be laid by hand, and the Scramble Crossing read as a pavement plaza
    import math as _m
    sys.path.insert(0, str(ROOT))
    import jgd_cs9
    import road_parts as RP
    g = json.loads((D / "tile_georef.json").read_text())
    s_, rot = g["studs_per_m"], _m.radians(g["rotation_deg"])
    mir = -1.0 if g["mirror_y"] else 1.0
    cr, sr = _m.cos(rot), _m.sin(rot)

    def to_studs(lat, lon):
        e, n = jgd_cs9.to_xy(lat, lon)
        x, y = e * s_, mir * n * s_
        return x * cr - y * sr + g["t"][0], x * sr + y * cr + g["t"][1]
    osm = json.loads((D / "osm_roads.json").read_text(encoding="utf-8"))
    drive = {"trunk", "primary", "secondary", "tertiary", "residential", "unclassified", "living_street"}
    for w in osm["elements"]:
        tg = w.get("tags", {})
        k = tg.get("highway")
        if k not in drive or not w.get("geometry") or tg.get("tunnel") or tg.get("bridge")                 or tg.get("layer", "0") not in ("0", ""):
            continue
        wm = RP.KIND[k][0]
        if tg.get("lanes", "").isdigit():
            wm = int(tg["lanes"]) * RP.LANE_M + 1.0
        half = wm * s_ / 2
        P = [to_studs(q["lat"], q["lon"]) for q in w["geometry"]]
        for (ax, az), (bx, bz) in zip(P, P[1:]):
            L = _m.hypot(bx - ax, bz - az)
            if L < 1e-6:
                continue
            for a in np.arange(0, L + 0.01, c):
                px, pz = ax + (bx - ax) * a / L, az + (bz - az) * a / L
                i0 = max(int((px - half - x0) / c), 0); i1 = min(int((px + half - x0) / c) + 1, NXm)
                k0 = max(int((pz - half - z0) / c), 0); k1 = min(int((pz + half - z0) / c) + 1, NZm)
                if i1 <= i0 or k1 <= k0:
                    continue
                I, K = np.meshgrid(np.arange(i0, i1), np.arange(k0, k1), indexing="ij")
                road[i0:i1, k0:k1] |= ((x0 + (I + 0.5) * c - px) ** 2 + (z0 + (K + 0.5) * c - pz) ** 2 <= half * half)                     & ~M[i0:i1, k0:k1] & ~side[i0:i1, k0:k1]
    out = D / "paint"
    out.mkdir(exist_ok=True)
    index = json.loads((D / "terrain" / "index.json").read_text())
    counts = {"a": 0, "s": 0, "b": 0, "-": 0}
    for name in index:
        ch = json.loads((D / "terrain" / f"{name}.json").read_text())
        rows = []
        for i in range(ch["nx"]):
            x = ch["x0"] + (i + 0.5) * 4
            row = []
            for k in range(ch["nz"]):
                z = ch["z0"] + (k + 0.5) * 4
                mi, mj = int((x - x0) / c), int((z - z0) / c)
                if not (0 <= mi < M.shape[0] and 0 <= mj < M.shape[1]) or not city[mi, mj]:
                    v = "-"
                elif M[mi, mj]:
                    v = "s"      # under a building: pavement, flush with the sidewalk beside it
                elif road[mi, mj]:
                    v = "a"
                else:
                    v = "s"          # sidewalks, plazas, lots: pavement
                row.append(v)
                counts[v] += 1
            rows.append("".join(row))
        (out / f"{name}.txt").write_text("\n".join(rows))
    tot = sum(counts.values())
    print(f"{len(index)} chunks: asphalt {counts['a']/tot:.0%}, pavement {counts['s']/tot:.0%}, "
          f"under buildings {counts['b']/tot:.0%}, outside {counts['-']/tot:.0%}")


if __name__ == "__main__":
    main()
