"""Rank conservative high-rise source-slice samples against the live inventory."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections
import numpy as np
from shapely import Polygon

DATA = ROOT / "source_slices"
MIN_AREA = 500.0


def live_footprint(record):
    cf, size = record["cf"], record["size"]
    x, z = cf[0], cf[2]
    right = np.array([cf[3], cf[9]])
    back = np.array([cf[5], cf[11]])
    hx, hz = size[0] / 2, size[2] / 2
    return Polygon([
        np.array([x, z]) + sx * hx * right + sz * hz * back
        for sx, sz in [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    ])


def best_match(shape, choices):
    matches = [(shape.intersection(other).area / shape.union(other).area, other)
               for other in choices if shape.bounds[2] >= other.bounds[0]
               and other.bounds[2] >= shape.bounds[0]
               and shape.bounds[3] >= other.bounds[1]
               and other.bounds[3] >= shape.bounds[1]]
    return max(matches, default=(0.0, None), key=lambda row: row[0])


def main():
    center_y = float(sys.argv[1]) if len(sys.argv) > 1 else 400.123
    heights = [center_y - 100, center_y - 50, center_y, center_y + 50, center_y + 100]
    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    slices = {}
    for y in heights:
        polygons, stats, _ = sections(triangles, y, seam=0)
        slices[y] = [p for p in polygons if p.area >= MIN_AREA]
        print(json.dumps({"y": y, **stats, "large": len(slices[y])}), file=sys.stderr)

    live = json.loads((DATA / "live_buildings.json").read_text())
    live_rows = []
    for record in live:
        low = record["cf"][1] - record["size"][1] / 2
        high = record["cf"][1] + record["size"][1] / 2
        if low <= center_y <= high:
            live_rows.append((record, live_footprint(record)))

    ranked = []
    for index, shape in enumerate(slices[center_y]):
        lower_iou, _ = best_match(shape, slices[heights[1]])
        upper_iou, _ = best_match(shape, slices[heights[3]])
        if max(lower_iou, upper_iou) < 0.05:
            continue
        simplified = shape.simplify(0.35, preserve_topology=True)
        if len(simplified.exterior.coords) - 1 > 24 or len(simplified.interiors) > 1:
            continue
        overlaps = []
        covered = 0.0
        for record, footprint in live_rows:
            shared = shape.intersection(footprint).area
            if shared <= 1:
                continue
            fraction = shared / shape.area
            if fraction >= 0.01:
                overlaps.append({
                    "name": record["name"],
                    "sourceFraction": round(fraction, 4),
                    "liveFraction": round(shared / footprint.area, 4),
                })
                covered += shared
        if not overlaps:
            continue
        ranked.append({
            "sliceIndex": index,
            "centroid": [round(shape.centroid.x, 3), round(shape.centroid.y, 3)],
            "bounds": [round(value, 3) for value in shape.bounds],
            "area": round(shape.area, 3),
            "vertices": len(simplified.exterior.coords) - 1,
            "holes": len(simplified.interiors),
            "lowerIoU": round(lower_iou, 4),
            "upperIoU": round(upper_iou, 4),
            "liveOverlapSum": round(covered / shape.area, 4),
            "liveModels": sorted(overlaps, key=lambda row: -row["sourceFraction"])[:12],
        })
    ranked.sort(key=lambda row: (
        abs(row["liveOverlapSum"] - 1),
        abs(len(row["liveModels"]) - 2),
        -min(row["lowerIoU"], row["upperIoU"]),
    ))
    output = {"height": center_y, "candidateCount": len(ranked), "candidates": ranked[:30]}
    suffix = str(center_y).replace(".", "_")
    (DATA / f"candidate_samples_{suffix}.json").write_text(json.dumps(output, indent=2))
    if abs(center_y - 400.123) < 0.001:
        (DATA / "candidate_samples.json").write_text(json.dumps(output, indent=2))
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
