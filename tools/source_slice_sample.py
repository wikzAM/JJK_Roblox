"""Extract a focused vertical source cross-section track for one reviewed seed."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections
import numpy as np

DATA = ROOT / "source_slices"


def main():
    seam = float(sys.argv[1]) if len(sys.argv) > 1 else 0
    source = np.load(DATA / "world_triangles.npz")["triangles"]
    candidates = json.loads((DATA / "candidate_samples.json").read_text())
    seed_info = candidates["candidates"][0]
    seed_y = candidates["height"]
    min_x, min_z, max_x, max_z = seed_info["bounds"]
    margin = 20
    tri_min = source[:, :, [0, 2]].min(axis=1)
    tri_max = source[:, :, [0, 2]].max(axis=1)
    local = source[
        (tri_max[:, 0] >= min_x - margin) & (tri_min[:, 0] <= max_x + margin)
        & (tri_max[:, 1] >= min_z - margin) & (tri_min[:, 1] <= max_z + margin)
    ]
    seed_polygons, _, _ = sections(local, seed_y, seam=seam)
    target = np.array(seed_info["centroid"])
    seed = min(seed_polygons, key=lambda p: np.linalg.norm(
        np.array([p.centroid.x, p.centroid.y]) - target))

    rows = []
    for y in np.arange(40.123, 620.124, 2.5):
        polygons, stats, _ = sections(local, float(y), seam=seam)
        matches = []
        for polygon in polygons:
            shared = polygon.intersection(seed).area
            if shared > 1:
                matches.append((shared / polygon.union(seed).area, polygon))
        if not matches:
            continue
        iou, polygon = max(matches, key=lambda row: row[0])
        if iou < 0.001:
            continue
        simplified = polygon.simplify(0.15, preserve_topology=True)
        rows.append({
            "y": round(float(y), 3),
            "area": round(polygon.area, 3),
            "seedIoU": round(iou, 5),
            "vertices": len(simplified.exterior.coords) - 1,
            "holes": len(simplified.interiors),
            "centroid": [round(polygon.centroid.x, 3), round(polygon.centroid.y, 3)],
            "bounds": [round(value, 3) for value in polygon.bounds],
            "ring": [[round(x, 3), round(z, 3)] for x, z in simplified.exterior.coords[:-1]],
            "dangleLength": round(stats["dangle_length"], 3),
        })
    output = {
        "candidate": seed_info,
        "seam": seam,
        "localTriangles": len(local),
        "seedRing": [[round(x, 3), round(z, 3)] for x, z in
                     seed.simplify(0.15, preserve_topology=True).exterior.coords[:-1]],
        "rows": rows,
    }
    suffix = str(seam).replace(".", "_")
    (DATA / f"sample_track_seam_{suffix}.json").write_text(json.dumps(output, indent=2))
    print(json.dumps({
        "localTriangles": len(local),
        "trackedSlices": len(rows),
        "minY": rows[0]["y"] if rows else None,
        "maxY": rows[-1]["y"] if rows else None,
        "distinct": sorted(set((row["area"], row["vertices"], row["holes"]) for row in rows)),
    }, indent=2))


if __name__ == "__main__":
    main()
