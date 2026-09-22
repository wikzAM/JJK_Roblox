"""Fill storeys missing mid-building in the plans the map holds.

A level that failed to convert was once skipped, leaving floors below and a
roof slab above with bare core between them -- the "I-beam". Each missing
storey becomes a copy of the next level ABOVE the gap: level curves only shrink
going up, so that copy lies inside every floor beneath it and around the core.

  python tools/source_slice_gapfill.py --tag gapfill
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parent
CHUNKS = ROOT / "source_slices" / "sweep" / "chunks"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
import source_slice_orphans as O  # noqa: E402
import source_slice_plan_builder as B  # noqa: E402

GAP = 1.5 * B.PITCH


def fill(plan):
    levels = plan["levels"]
    out = [levels[0]]
    for lv in levels[1:]:
        y = out[-1]["y"] + B.PITCH
        while lv["y"] - y >= B.SLAB + B.MIN_CLEAR and lv["y"] - out[-1]["y"] > GAP:
            out.append(dict(y=round(y, 4), thickness=lv["thickness"],
                            pieces=json.loads(json.dumps(lv["pieces"]))))
            y += B.PITCH
        out.append(lv)
    if len(out) == len(levels):
        return None
    new = json.loads(json.dumps(plan))
    new["levels"] = out
    new.setdefault("sourceInfo", {})["gapFilled"] = len(out) - len(levels)
    return new


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    prefix = f"rebuild_{args.tag}_"
    if any(CHUNKS.glob(prefix + "*.json")):
        raise SystemExit(f"{prefix}* already exists -- pick a new --tag")
    out = []
    for plan in O.current_plans().values():
        new = fill(plan)
        if new is None:
            continue
        problems = B.validate(new)
        if problems:
            print(f"  {plan['id']}: still invalid -- {problems[0]}")
            continue
        out.append(new)
        print(f"  {plan['id']:24s} +{new['sourceInfo']['gapFilled']} storeys")
    if out:
        name = f"{prefix}01"
        (CHUNKS / f"{name}.json").write_text(json.dumps(
            {"name": name, "plans": out, "parapets": {}, "crowns": {}}))
    print(f"{len(out)} plans gap-filled -> {prefix}01")


if __name__ == "__main__":
    main()
