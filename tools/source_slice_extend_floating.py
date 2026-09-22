"""Extend FLOATING buildings down to the ground they stand on.

A building whose roof is its own mesh piece -- walls not welded to it -- was
generated from that roof alone, as a stub a few floors deep hanging in the air
(the map owner's "I-beam"; the FBX shows the whole building under it). By the
level-curve rule the slice at every height beneath a roof is that roof's
outline, so the missing floors are copies of the stub's first floor, all the
way down.

Only where the FBX has WALLS under the footprint reaching below the stub
(source_slice_diagnose.py: walls_below): a real bridge or elevated deck has
nothing under it and must not become a building. The new base is where those
walls end, not the lowest surface nearby (which on a slope can be a street
below the building).

  python tools/source_slice_extend_floating.py --tag floating
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
import source_slice_orphans as O  # noqa: E402
import source_slice_plan_builder as B  # noqa: E402
from source_slice_referee import Envelope  # noqa: E402

FLOAT_STOREYS = 2
MIN_WALLS = 2
OVERLAP_SHARE = 0.05


def extend(plan, new_base):
    old_base = plan["origin"]["y"]
    drop = old_base - new_base
    if drop < B.PITCH:
        return None
    new = json.loads(json.dumps(plan))
    for lv in new["levels"]:
        lv["y"] = round(lv["y"] + drop, 4)
    first = new["levels"][0]
    # stack down from the stub on its own pitch; the ground storey takes the
    # remainder (never a gap between the added floors and the original ones)
    ys, y = [], first["y"] - B.PITCH
    while y > B.SLAB + B.MIN_CLEAR:
        ys.append(y)
        y -= B.PITCH
    ys.append(0.0)
    if first["y"] < B.SLAB + B.MIN_CLEAR:
        return None
    added = [dict(y=round(v, 4), thickness=first["thickness"],
                  pieces=json.loads(json.dumps(first["pieces"]))) for v in sorted(ys)]
    new["levels"] = added + new["levels"]
    new["origin"]["y"] = round(new_base, 4)
    new.setdefault("sourceInfo", {})["extendedToGround"] = round(drop, 1)
    return new


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--diagnose", default=str(DATA / "sweep" / "diagnose.json"))
    args = parser.parse_args()
    prefix = f"rebuild_{args.tag}_"
    if any(CHUNKS.glob(prefix + "*.json")):
        raise SystemExit(f"{prefix}* already exists -- pick a new --tag")
    rows = json.loads(Path(args.diagnose).read_text())["rows"]
    plans = O.current_plans()
    feet = {}
    for pid, p in plans.items():
        lv = list(O.world_levels(p))
        if lv and not lv[0].is_empty:
            last = p["levels"][-1]
            feet[pid] = (lv[0].buffer(0), p["origin"]["y"],
                         p["origin"]["y"] + last["y"] + last["thickness"])
    env = Envelope()
    out, skipped = [], []
    for r in rows:
        if r["above"] <= FLOAT_STOREYS * B.PITCH or r["walls_below"] < MIN_WALLS:
            continue
        plan = plans.get(r["id"])
        if plan is None:
            continue
        # stand on a building below (a podium) rather than grow through it
        foot, base, _ = feet[r["id"]]
        floor = r["wall_floor"]
        for pid, (f, b, top) in feet.items():
            if pid != r["id"] and top <= base + 1.0 and top > floor \
                    and f.intersection(foot).area > OVERLAP_SHARE * foot.area:
                floor = top
        new = extend(plan, floor)
        if new is not None:
            old_s, new_s = env.score(plan), env.score(new)
            if new_s[1] > old_s[1] + 0.1:
                print(f"  {r['id']:28s} refused: spill {old_s[1]:.0%} -> {new_s[1]:.0%}")
                new = None
        if new is None or B.validate(new):
            skipped.append(r["id"])
            continue
        out.append(new)
        print(f"  {r['id']:28s} +{len(new['levels']) - len(plan['levels'])} floors, base "
              f"{plan['origin']['y']:.0f} -> {new['origin']['y']:.0f}")
    if out:
        name = f"{prefix}01"
        (CHUNKS / f"{name}.json").write_text(json.dumps(
            {"name": name, "plans": out, "parapets": {}, "crowns": {}}))
    print(f"{len(out)} floating buildings extended to the ground -> {prefix}01"
          + (f"; {len(skipped)} skipped: {skipped}" if skipped else ""))


if __name__ == "__main__":
    main()
