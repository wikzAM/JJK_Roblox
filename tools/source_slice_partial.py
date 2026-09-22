"""Replace live buildings that only PARTLY cover an FBX building with all of it.

The orphan pass (source_slice_orphans.py) plans FBX buildings the map lacks, and
skips any already more than LIVE_COVER_MAX covered by a live building. That let
a class of wrong building through, the map owner's "missing / rotated" ones: a
small or turned live building standing on one corner of a large FBX building,
the rest of which was never built. From the street the FBX building is missing
and the live one looks rotated against it.

Per FBX building (mesh identity, as the orphan pass) that live buildings cover
partly:
  * live buildings lying mostly INSIDE its outline (REPLACE_SHARE of their own
    footprint) are replaced; ones mostly outside are neighbours and kept clear;
  * the building is planned whole with the orphan planner's level curves;
  * the referee (FBX roof envelope) must agree: the new plan covers clearly more
    of the FBX building, or reaches clearly nearer its roof, and spills no more.

  python tools/source_slice_partial.py --tag partial

Writes sweep/chunks/partial_<tag>_NN.json. Each plan lists the live ids it
replaces in sourceInfo.replacesLive (SourceSliceSweepApply.Replace destroys
those) and open greys in sourceInfo.replaces (archived, as Sweep.Add does).
"""
from pathlib import Path
import argparse
import csv
import json
import math
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
CHUNKS = DATA / "sweep" / "chunks"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import numpy as np  # noqa: E402
from shapely import contains_xy, prepare, union_all  # noqa: E402
from shapely.geometry import box  # noqa: E402
from shapely.strtree import STRtree  # noqa: E402
import source_slice_orphans as O  # noqa: E402
import source_slice_plan_builder as B  # noqa: E402
from source_slice_referee import Envelope, CELL  # noqa: E402

MIN_AREA = 1500.0        # sq studs: FBX buildings smaller than this are left alone
COVER_MIN = O.LIVE_COVER_MAX   # below this the orphan pass already planned it
REPLACE_SHARE = 0.6      # a live building this much inside the outline is replaced
MISSING_MIN = 0.35       # share of the FBX footprint no live building covers
SHORT_MIN = 2 * B.PITCH  # live buildings this far under the FBX roof
GAIN_MIN = 0.15          # new plan must cover this much more of the FBX footprint
SPILL_MAX = 0.3
# Hand-approved shell crowns and crowns left for manual design (Cerulean Tower
# among them). An FBX building with one of these on it is never touched: in the
# first trial run the envelope's 95th-percentile roof, taken over a footprint the
# tower fills only part of, read these towers as 60-85 studs "too tall".
PROTECTED_FILE = DATA / "sweep" / "protected_live.txt"


def protected_ids():
    lines = PROTECTED_FILE.read_text().splitlines()
    return {ln.split()[0] for ln in lines if ln.strip() and not ln.startswith("#")}


def fbx_top(env, poly):
    x0, z0, x1, z1 = poly.bounds
    i0 = max(0, int((x0 - env.x0) / CELL)); i1 = min(env.nx - 1, int((x1 - env.x0) / CELL) + 1)
    j0 = max(0, int((z0 - env.z0) / CELL)); j1 = min(env.nz - 1, int((z1 - env.z0) / CELL) + 1)
    PX, PZ = np.meshgrid(env.x0 + (np.arange(i0, i1 + 1) + .5) * CELL,
                         env.z0 + (np.arange(j0, j1 + 1) + .5) * CELL, indexing="ij")
    sub = env.H[i0:i1 + 1, j0:j1 + 1]
    prepare(poly)
    hs = sub[contains_xy(poly, PX, PZ) & np.isfinite(sub)]
    return float(np.percentile(hs, 95)) if len(hs) else float("nan")


def top_of(plan):
    last = plan["levels"][-1]
    return plan["origin"]["y"] + last["y"] + last["thickness"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--size", type=int, default=20)
    parser.add_argument("--limit", type=int, default=0, help="stop after this many (testing)")
    args = parser.parse_args()
    prefix = f"partial_{args.tag}_"
    if any(CHUNKS.glob(prefix + "*.json")):
        raise SystemExit(f"{prefix}* already exists -- pick a new --tag")

    env = Envelope()
    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    comps, ordered = O.building_groups(triangles)
    planner = O.Planner(triangles, comps)

    cur = O.current_plans()
    ids = [pid for pid in cur]
    feet = {}
    for pid in ids:
        f = union_all([p for p in O.world_levels(cur[pid]) if not p.is_empty], grid_size=0.01)
        if not f.is_empty:
            feet[pid] = f
    ids = [pid for pid in ids if pid in feet]
    tree = STRtree([feet[pid] for pid in ids])

    greys = {}
    with open(DATA / "live_extents.csv", newline="") as fh:
        for row in csv.DictReader(fh):
            greys["BuildingSmooth_" + row["n"]] = box(float(row["x0"]), float(row["z0"]),
                                                      float(row["x1"]), float(row["z1"]))
    claimed = {n.strip() for n in (DATA / "applied_greys.txt").read_text().splitlines() if n.strip()}
    for plan in cur.values():
        claimed.update(plan.get("sourceInfo", {}).get("replaces", []))
    for path in CHUNKS.glob("orphans_lc_*.json"):
        for plan in json.loads(path.read_text())["plans"]:
            claimed.update(plan.get("sourceInfo", {}).get("replaces", []))
    open_greys = {n: g for n, g in greys.items() if n not in claimed}
    grey_names = list(open_greys)
    grey_tree = STRtree([open_greys[n] for n in grey_names])

    protected = protected_ids()
    consumed, planned_fp, out, stats = set(), [], [], {}

    def note(why):
        stats[why] = stats.get(why, 0) + 1

    for members in ordered:
        fp = planner.footprint(members)
        if fp.area < MIN_AREA:
            continue
        c = fp.centroid
        if any((c.x - px) ** 2 + (c.y - pz) ** 2 <= pr * pr for px, pz, pr in O.PROTECTED):
            continue
        near = [ids[k] for k in tree.query(fp) if ids[k] not in consumed]
        near = [pid for pid in near if feet[pid].intersects(fp)]
        if not near:
            continue
        live_union = union_all([feet[pid] for pid in near], grid_size=0.01)
        covered = fp.intersection(live_union, grid_size=0.01).area / fp.area
        if covered < COVER_MIN:
            continue
        outline = planner.outline(members)
        inside = outline.buffer(2.0)
        replace = [pid for pid in near
                   if feet[pid].intersection(inside, grid_size=0.01).area >= REPLACE_SHARE * feet[pid].area]
        if not replace:
            note("only neighbours overlap it")
            continue
        if any(pid in protected for pid in replace):
            note("protected building on it")
            continue
        missing = 1.0 - covered
        roof = fbx_top(env, fp)
        old_top = max(top_of(cur[pid]) for pid in replace)
        short = roof - old_top
        if missing < MISSING_MIN and not short > SHORT_MIN:
            note("already well covered")
            continue
        keep = [feet[pid] for pid in near if pid not in replace]
        others = keep + [f for f in planned_fp if f.intersects(fp)]
        blocked = union_all([f.buffer(O.LIVE_CLEARANCE) for f in others], grid_size=0.01) if others else None
        plan, plates, why = planner.plan(members, blocked, prefix="part")
        if plan is None:
            note("planner: " + why)
            continue

        # referee: coverage of the FBX footprint, height, spill -- old vs new
        new_foot = union_all([p for _, p in plates], grid_size=0.01)
        old_foot = union_all([feet[pid] for pid in replace], grid_size=0.01)
        gain = (fp.intersection(new_foot, grid_size=0.01).area
                - fp.intersection(old_foot, grid_size=0.01).area) / fp.area
        dh_new, sp_new = env.score(plan)
        old_scores = [env.score(cur[pid]) for pid in replace]
        dh_old = min((abs(d) for d, _ in old_scores), default=math.inf)
        sp_old = max((s for _, s in old_scores), default=0.0)
        new_top = top_of(plan)
        if sp_new > max(SPILL_MAX, sp_old + 0.05):
            note("refused: spills")
            continue
        # never lower a building: the tall part of what is there stays
        if new_top < old_top - B.PITCH:
            note("refused: lower than what it replaces")
            continue
        taller = short > SHORT_MIN and new_top >= old_top + B.PITCH and gain >= -0.05
        if not (gain >= GAIN_MIN or taller):
            note("refused: no clear gain")
            continue
        foot = plates[0][1]
        greys_in = [grey_names[k] for k in grey_tree.query(foot)
                    if open_greys[grey_names[k]].intersection(foot).area >= 0.5 * open_greys[grey_names[k]].area]
        plan["sourceInfo"].update(replacesLive=sorted(replace), replaces=sorted(greys_in),
                                  partial=dict(covered=round(covered, 3), gain=round(gain, 3),
                                               heightOld=round(dh_old, 1), heightNew=round(dh_new, 1),
                                               spillOld=round(sp_old, 3), spillNew=round(sp_new, 3)))
        consumed.update(replace)
        planned_fp.append(new_foot)
        out.append(plan)
        note("accepted")
        print(f"  {plan['id']:20s} replaces {len(replace)} ({', '.join(replace[:3])}{'...' if len(replace) > 3 else ''}) "
              f"covered {covered:.0%} gain {gain:+.0%}  height {dh_old:+.0f} -> {dh_new:+.0f}  "
              f"{len(plan['levels'])} floors", flush=True)
        if args.limit and len(out) >= args.limit:
            break

    for n in range(0, len(out), args.size):
        name = f"{prefix}{n // args.size + 1:02d}"
        (CHUNKS / f"{name}.json").write_text(json.dumps(
            {"name": name, "plans": out[n:n + args.size], "parapets": {}, "crowns": {}}))
    print(f"\n{len(out)} partly covered FBX buildings planned whole, replacing {len(consumed)} live buildings")
    for why, n in sorted(stats.items(), key=lambda kv: -kv[1]):
        print(f"  {n:5d}  {why}")
    print(f"-> {(len(out) + args.size - 1) // args.size} chunks {prefix}NN")


if __name__ == "__main__":
    main()
