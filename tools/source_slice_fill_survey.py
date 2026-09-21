"""Measure how well the live grey buildings match the actual FBX envelope.

Reads only offline data (world_triangles.npz + live_buildings.json); touches no
Studio session. Produces the two lists that should drive seed selection:

  fill      - FBX section area / grey footprint bbox area, per live building.
              fill << 1 means the grey box is much larger than the real envelope.
              fill >> 1 means one FBX polygon spans several greys.
  multi     - FBX polygons covering >= MIN_MEMBERS grey centres, i.e. one
              physical building that the residual/body passes split apart.

Usage:  python tools/source_slice_fill_survey.py [out.json]
"""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections  # also fixes up the deps path
import numpy as np
from shapely.geometry import Point
from shapely.strtree import STRtree

DATA = ROOT / "source_slices"
LEVELS = np.arange(130.0, 560.0, 40.0)
MIN_AREA = 200.0
MIN_MEMBERS = 3


def load():
    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    live = [b for b in json.loads((DATA / "live_buildings.json").read_text())
            if b["name"].startswith("BuildingSmooth")]
    for b in live:
        cf, size = b["cf"], b["size"]
        b["base"] = cf[1] - size[1] / 2
        b["top"] = cf[1] + size[1] / 2
        b["footprint"] = size[0] * size[2]
        b["point"] = Point(cf[0], cf[2])
    return triangles, live


def survey(triangles, live):
    """One section per level covers every building crossing that level."""
    areas, multi = {}, {}
    for y in LEVELS:
        polygons = [p for p in sections(triangles, float(y))[0] if p.area > MIN_AREA]
        if not polygons:
            continue
        tree = STRtree(polygons)
        owners = {}
        for b in live:
            if not (b["base"] + 3 < y < b["top"] - 3):
                continue
            # predicate is evaluated as point.within(polygon), not the reverse.
            found = tree.query(b["point"], predicate="within")
            if len(found) == 0:
                continue
            index = max(found, key=lambda k: polygons[k].area)
            areas.setdefault(b["name"], []).append(float(polygons[index].area))
            owners.setdefault(index, []).append(b)
        for index, members in owners.items():
            if len(members) < MIN_MEMBERS:
                continue
            polygon = polygons[index]
            key = (round(polygon.centroid.x, 1), round(polygon.centroid.y, 1))
            if key not in multi or len(members) > len(multi[key]["members"]):
                multi[key] = dict(
                    y=float(y), area=float(polygon.area),
                    vertices=len(polygon.exterior.coords) - 1,
                    members=sorted(b["name"] for b in members),
                    summedGreyFootprint=sum(b["footprint"] for b in members))
        print(f"y={y:.0f} polygons={len(polygons)} matched={sum(len(v) for v in owners.values())}",
              flush=True)
    return areas, sorted(multi.values(), key=lambda r: -len(r["members"]))


def main():
    triangles, live = load()
    print(f"smooth buildings: {len(live)}")
    areas, multi = survey(triangles, live)
    by_name = {b["name"]: b for b in live}
    fills = sorted((float(np.median(v)) / by_name[n]["footprint"], n) for n, v in areas.items())
    values = np.array([f for f, _ in fills])

    print(f"\nwith an FBX section under their centre: {len(values)} / {len(live)}")
    for q in (5, 10, 25, 50, 75, 90, 95):
        print(f"  p{q:<2} fill = {np.percentile(values, q):.3f}")
    print(f"  oversized grey (fill<0.80): {int((values < 0.80).sum())}")
    print(f"  polygon larger than grey (fill>1.10): {int((values > 1.10).sum())}")
    print(f"\nFBX polygons owning >= {MIN_MEMBERS} greys: {len(multi)}")
    for row in multi[:10]:
        print(f"  greys={len(row['members'])} area={row['area']:.0f} "
              f"vertices={row['vertices']} sumGrey={row['summedGreyFootprint']:.0f}")
        print(f"    {row['members'][0]}")

    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DATA / "fill_survey.json"
    out.write_text(json.dumps(dict(
        levels=LEVELS.tolist(),
        fills=[dict(name=n, fill=f) for f, n in fills],
        multiOwner=multi), indent=1))
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
