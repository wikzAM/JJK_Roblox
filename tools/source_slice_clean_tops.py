"""Put every building's top floor back on its storey grid -- no extra roof slab.

The top-slab snap (plan builder, orphans) added or lifted a last floor onto the
FBX roof. It fixed height on paper and made ugly geometry in the map: a small
added slab hangs above the building like a floating box, its rim walls make it
a box, and the core walls stretch from the last real floor up to it -- the tall
block spanning two towers the map owner photographed. The owner's rule for the
ordinary buildings: floors properly generated, and the roof parapet as a ledge
straight on top of the final floor. Nothing above it.

Per plan, only where the last floor is OFF the storey grid:
  * last floor under SMALL_SHARE of the one below -> dropped (the floating box);
  * last floor lifted into a TALL top storey       -> moved back onto the grid;
  * a last floor slightly under a storey above its neighbour stays: it is a
    normal-looking roof floor, just a shorter storey, and moving it up could
    put it above the real roof.

The core already lies inside every remaining level, so no plan is re-derived.

  python tools/source_slice_clean_tops.py --tag cleantops
"""
from pathlib import Path
import argparse
import glob
import json
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
CHUNKS = DATA / "sweep" / "chunks"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
from shapely.geometry import Polygon  # noqa: E402
from shapely.ops import unary_union  # noqa: E402
import source_slice_orphans as O  # noqa: E402
import source_slice_plan_builder as B  # noqa: E402

SMALL_SHARE = 0.6
GRID_TOLERANCE = 0.5


def live_plans():
    """What the map holds now (see source_slice_orphans.current_plans)."""
    return O.current_plans()


def area(level):
    return unary_union([Polygon(pc).buffer(0) for pc in level["pieces"]]).area


def clean(plan):
    """Return (changed plan or None, what was done)."""
    levels = plan["levels"]
    if len(levels) < 2:
        return None, None
    gap = levels[-1]["y"] - levels[-2]["y"]
    if abs(gap - B.PITCH) < GRID_TOLERANCE:
        return None, None
    new = json.loads(json.dumps(plan))
    # A two-floor building cannot lose its top (the contract needs two levels),
    # but a lifted roof still goes back on the grid: the first pass skipped every
    # two-floor building and left 158 orphans with a tall top storey.
    if len(levels) >= 3 and area(levels[-1]) < SMALL_SHARE * area(levels[-2]):
        new["levels"].pop()
        how = "dropped small top slab"
    elif gap > B.PITCH:
        new["levels"][-1]["y"] = round(levels[-2]["y"] + B.PITCH, 4)
        how = "top storey back on the grid"
    else:
        return None, None
    new.setdefault("sourceInfo", {})["topCleaned"] = how
    return new, how


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--size", type=int, default=25)
    args = parser.parse_args()
    prefix = f"rebuild_{args.tag}_"
    if any(CHUNKS.glob(prefix + "*.json")):
        raise SystemExit(f"{prefix}* already exists -- pick a new --tag")
    changed, counts, invalid = [], {}, 0
    for plan in live_plans().values():
        new, how = clean(plan)
        if new is None:
            continue
        if B.validate(new):
            invalid += 1
            continue
        counts[how] = counts.get(how, 0) + 1
        changed.append(new)
    for n in range(0, len(changed), args.size):
        name = f"{prefix}{n // args.size + 1:02d}"
        (CHUNKS / f"{name}.json").write_text(json.dumps(
            {"name": name, "plans": changed[n:n + args.size], "parapets": {}, "crowns": {}}))
    print(f"{len(changed)} plans cleaned: " + ", ".join(f"{v} {k}" for k, v in counts.items())
          + f"; {invalid} left alone (would break the contract)")
    print(f"-> {(len(changed) + args.size - 1) // args.size} chunks {prefix}NN")


if __name__ == "__main__":
    main()
