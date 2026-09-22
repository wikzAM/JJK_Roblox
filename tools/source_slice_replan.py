"""Re-plan named live buildings from their FBX building with level curves.

For buildings an automatic pass will not touch -- the protected crowns in
sweep/protected_live.txt, whose floors can still be wrong. The first:
fbx_6_15630_3432_-8769, a solid FBX block whose section-built floors came out
as two towers with nothing between them, capped by grey crown slabs floating
across the gap (the map owner's "arch").

The FBX building is the mesh-identity group (source_slice_orphans) whose
footprint covers the live building's centroid; neighbours are kept clear. The
result keeps the live id, so SourceSliceSweepApply.Rebuild replaces it in place
and carries CrownNeedsManualDesign / CrownInteresting across.

  python tools/source_slice_replan.py --tag replan ID [ID ...]
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
CHUNKS = DATA / "sweep" / "chunks"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from shapely import union_all  # noqa: E402
from shapely.strtree import STRtree  # noqa: E402
import source_slice_orphans as O  # noqa: E402
from source_slice_referee import Envelope  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("ids", nargs="+")
    args = parser.parse_args()
    prefix = f"rebuild_{args.tag}_"
    if any(CHUNKS.glob(prefix + "*.json")):
        raise SystemExit(f"{prefix}* already exists -- pick a new --tag")

    env = Envelope()
    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    comps, ordered = O.building_groups(triangles)
    planner = O.Planner(triangles, comps)
    cur = O.current_plans()
    feet = {pid: union_all([p for p in O.world_levels(pl) if not p.is_empty], grid_size=0.01)
            for pid, pl in cur.items()}
    ids = list(feet)
    tree = STRtree([feet[i] for i in ids])
    group_fp = [(members, planner.footprint(members)) for members in ordered]
    gtree = STRtree([fp for _, fp in group_fp])

    out = []
    for pid in args.ids:
        old = cur[pid]
        foot = feet[pid]
        # the FBX building: the group covering most of the live footprint
        best, best_share = None, 0.0
        for k in gtree.query(foot):
            members, fp = group_fp[k]
            share = fp.intersection(foot, grid_size=0.01).area / foot.area
            if share > best_share:
                best, best_share = members, share
        if best is None:
            print(f"  {pid}: no FBX building under it")
            continue
        outline = planner.outline(best)
        others = [feet[ids[k]] for k in tree.query(outline) if ids[k] != pid
                  and feet[ids[k]].intersects(outline)]
        blocked = union_all([f.buffer(O.LIVE_CLEARANCE) for f in others], grid_size=0.01) if others else None
        plan, plates, why = planner.plan(best, blocked, prefix="replan")
        if plan is None:
            print(f"  {pid}: planner refused -- {why}")
            continue
        plan["id"] = pid
        plan["sourceInfo"]["replannedFrom"] = "level curves over the FBX building (source_slice_replan.py)"
        (dh_o, sp_o), (dh_n, sp_n) = env.score(old), env.score(plan)
        new_area = union_all([p for _, p in plates], grid_size=0.01).area
        print(f"  {pid}: FBX group covers {best_share:.0%} of it; floors {len(old['levels'])} -> "
              f"{len(plan['levels'])}, footprint {foot.area:.0f} -> {new_area:.0f}, "
              f"height {dh_o:+.0f} -> {dh_n:+.0f}, spill {sp_o:.0%} -> {sp_n:.0%}")
        out.append(plan)
    if out:
        name = f"{prefix}01"
        (CHUNKS / f"{name}.json").write_text(json.dumps(
            {"name": name, "plans": out, "parapets": {}, "crowns": {}}))
        print(f"-> {name}")


if __name__ == "__main__":
    main()
