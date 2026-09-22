"""Find the three kinds of wrong building the map owner photographed.

  FLOATING   a building whose base is far above the ground around it. The FBX
             has walls under it, but its roof is a separate mesh piece from those
             walls, so the roof alone was generated as a two-floor stub hanging in
             the air (the "I-beam"). By the level-curve rule the slice at every
             height below that roof IS the roof's outline, so it should reach the
             ground -- where walls are there to prove the building is.
  ROTATED    floors turned relative to the FBX building: the plan's floors
             spill out of the FBX envelope while a rotated copy would not.
  ROAD       long, narrow, low structures -- elevated roads and rail viaducts.

  python tools/source_slice_diagnose.py [--out FILE]
"""
from pathlib import Path
import argparse
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from shapely import contains_xy, prepare  # noqa: E402
from shapely.affinity import rotate  # noqa: E402
import source_slice_orphans as O  # noqa: E402
import source_slice_plan_builder as B  # noqa: E402
from source_slice_roofs import roof_triangles, roof_plate  # noqa: E402

GROUND_RADIUS = 40.0     # studs around a footprint searched for the ground
FLOAT_STOREYS = 2        # base this many storeys above the ground = floating
ROAD_LENGTH = 800.0      # studs
ROAD_WIDTH = 120.0       # mean width (2 * area / perimeter) under this
ROAD_LEVELS = 6


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(DATA / "sweep" / "diagnose.json"))
    args = parser.parse_args()

    tri = np.load(DATA / "world_triangles.npz")["triangles"]
    lo = tri[:, :, [0, 2]].min(axis=1)
    hi = tri[:, :, [0, 2]].max(axis=1)
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    ny = np.abs(n[:, 1]) / np.maximum(np.linalg.norm(n, axis=1), 1e-12)
    is_wall = ny < 0.3
    ymin = tri[:, :, 1].min(axis=1)
    centres = tri.mean(axis=1)

    plans = O.current_plans()
    rows = []
    for pid, plan in plans.items():
        levels = list(O.world_levels(plan))
        foot = levels[0]
        if foot.is_empty:
            continue
        base = plan["origin"]["y"]
        x0, z0, x1, z1 = foot.buffer(GROUND_RADIUS).bounds
        near = (hi[:, 0] >= x0) & (lo[:, 0] <= x1) & (hi[:, 1] >= z0) & (lo[:, 1] <= z1)
        ground = float(ymin[near].min()) if near.any() else base
        # walls standing under the footprint, reaching below the base
        reach = foot.buffer(2.0)
        prepare(reach)
        inside = near & contains_xy(reach, centres[:, 0], centres[:, 2])
        walls_below = int((inside & is_wall & (ymin < base - B.PITCH)).sum())
        wall_floor = float(ymin[inside & is_wall].min()) if (inside & is_wall).any() else base

        rect = foot.minimum_rotated_rectangle
        xs, zs = rect.exterior.coords.xy
        edges = sorted(math.hypot(xs[i + 1] - xs[i], zs[i + 1] - zs[i]) for i in range(2))
        length, mean_width = edges[-1], 2 * foot.area / max(foot.length, 1e-9)

        # rotation: spill of the lowest floor vs the FBX roofs above it, as built
        # and turned in 5-degree steps about its own centre
        local = tri[near]
        roofs = roof_triangles(local)
        spill_now, best_turn, best_spill = None, 0, None
        env = roof_plate(roofs, base + B.SLAB + 1.0) if len(roofs) else None
        if env is not None and not env.is_empty and foot.area > 0:
            spill_now = foot.difference(env.buffer(2.0)).area / foot.area
            if spill_now > 0.25:
                best_turn, best_spill = 0, spill_now
                for turn in range(-45, 46, 5):
                    if turn == 0:
                        continue
                    t = rotate(foot, turn, origin=foot.centroid)
                    s = t.difference(env.buffer(2.0)).area / t.area
                    if s < best_spill:
                        best_turn, best_spill = turn, s
        rows.append(dict(
            id=pid, levels=len(plan["levels"]), base=round(base, 1), ground=round(ground, 1),
            above=round(base - ground, 1), walls_below=walls_below, wall_floor=round(wall_floor, 1),
            length=round(length, 1), width=round(mean_width, 1), area=round(foot.area, 1),
            spill=None if spill_now is None else round(spill_now, 3),
            best_turn=best_turn, best_spill=None if best_spill is None else round(best_spill, 3),
            x=round(foot.centroid.x, 1), z=round(foot.centroid.y, 1)))

    floating = [r for r in rows if r["above"] > FLOAT_STOREYS * B.PITCH]
    floating_walls = [r for r in floating if r["walls_below"] >= 2]
    roads = [r for r in rows if r["length"] > ROAD_LENGTH and r["width"] < ROAD_WIDTH and r["levels"] <= ROAD_LEVELS]
    rotated = [r for r in rows if r["spill"] is not None and r["spill"] > 0.25
               and r["best_spill"] is not None and r["best_spill"] < 0.5 * r["spill"]]
    Path(args.out).write_text(json.dumps(dict(rows=rows), indent=0))
    print(f"{len(rows)} buildings diagnosed")
    print(f"FLOATING (base > {FLOAT_STOREYS} storeys above ground): {len(floating)}, "
          f"with FBX walls under them: {len(floating_walls)}")
    for r in sorted(floating_walls, key=lambda r: -r['above'])[:8]:
        print(f"   {r['id']:28s} base {r['base']:6.0f} ground {r['ground']:6.0f} (+{r['above']:.0f})  "
              f"{r['walls_below']} walls down to {r['wall_floor']:.0f}  at {r['x']:.0f},{r['z']:.0f}")
    print(f"ROAD candidates (length > {ROAD_LENGTH:.0f}, width < {ROAD_WIDTH:.0f}, <= {ROAD_LEVELS} levels): {len(roads)}")
    for r in sorted(roads, key=lambda r: -r['length'])[:10]:
        print(f"   {r['id']:28s} {r['length']:6.0f} long, {r['width']:5.0f} wide, {r['levels']} levels, "
              f"base +{r['above']:.0f} above ground  at {r['x']:.0f},{r['z']:.0f}")
    print(f"ROTATED (bottom floor spills > 25% and a turn halves it): {len(rotated)}")
    for r in sorted(rotated, key=lambda r: -r['spill'])[:8]:
        print(f"   {r['id']:28s} spill {r['spill']:.0%} -> {r['best_spill']:.0%} turned {r['best_turn']:+d} deg  "
              f"at {r['x']:.0f},{r['z']:.0f}")


if __name__ == "__main__":
    main()
