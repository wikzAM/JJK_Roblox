"""Read-only probe of source polygon faces inside one legacy live footprint."""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections
from source_slice_candidates import live_footprint
import numpy as np
from shapely import get_parts, union_all

DATA = ROOT / "source_slices"


def main():
    name = sys.argv[1]
    heights = [float(value) for value in sys.argv[2:]]
    live = json.loads((DATA / "live_buildings.json").read_text())
    record = next(row for row in live if row["name"] == name)
    footprint = live_footprint(record)
    source = np.load(DATA / "world_triangles.npz")["triangles"]
    min_x, min_z, max_x, max_z = footprint.bounds
    margin = 10
    tri_min = source[:, :, [0, 2]].min(axis=1)
    tri_max = source[:, :, [0, 2]].max(axis=1)
    local = source[
        (tri_max[:, 0] >= min_x - margin) & (tri_min[:, 0] <= max_x + margin)
        & (tri_max[:, 1] >= min_z - margin) & (tri_min[:, 1] <= max_z + margin)
    ]
    result = {"name": name, "liveArea": footprint.area, "localTriangles": len(local), "slices": []}
    for y in heights:
        polygons, stats, _ = sections(local, y, seam=0)
        selected = []
        for polygon in polygons:
            shared = polygon.intersection(footprint).area
            if shared > 1 and shared / polygon.area >= 0.5:
                selected.append(polygon)
        merged = union_all(selected) if selected else None
        parts = list(get_parts(merged)) if merged and not merged.is_empty else []
        result["slices"].append({
            "y": y,
            "faces": len(selected),
            "components": len(parts),
            "area": sum(part.area for part in parts),
            "coverageOfLive": sum(part.intersection(footprint).area for part in parts) / footprint.area,
            "componentRows": [{
                "area": part.area,
                "bounds": list(part.bounds),
                "vertices": len(part.exterior.coords) - 1,
                "holes": len(part.interiors),
            } for part in sorted(parts, key=lambda part: -part.area)],
            "sliceStats": stats,
        })
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
