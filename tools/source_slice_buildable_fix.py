"""Make every ring in a set of plans triangulable by Studio BEFORE Studio sees it.

The plan builder only checks rings of 14+ vertices against polygon_slab_sim (the
Python replica of PolygonSlab's triangulator), on the grounds that small rings
always tile. They do not: degenerate small rings (near-collinear points) fail in
Studio after "6 search states", and ~6% of the orphan pass (36 of 626) was
refused there. This checks EVERY ring against the full 2048-state budget and
repairs the failures -- a coarser simplification first, the ring's minimum
rotated rectangle last -- then re-validates each plan against the contract.

  python tools/source_slice_buildable_fix.py <plansDir-or-chunk.json> ... [--write]

Without --write it only reports.
"""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402
from shapely.geometry import Polygon  # noqa: E402
import source_slice_plan_builder as B  # noqa: E402
from polygon_slab_sim import buildable  # noqa: E402

LADDER = (1.4, 2.0, 3.0, 4.5, 6.0)


def fix_ring(piece):
    ring = [tuple(p) for p in piece]
    if buildable(ring, limit=2048)[0]:
        return piece, None
    poly = Polygon(ring).buffer(0)
    for tol in LADDER:
        simp = poly.simplify(tol, preserve_topology=True).buffer(0)
        if simp.is_empty or simp.geom_type != "Polygon" or simp.area < 40:
            break
        cand = [(round(x, 3), round(z, 3)) for x, z in list(simp.exterior.coords)[:-1]]
        if len(cand) >= 3 and buildable(cand, limit=2048)[0]:
            return [list(p) for p in cand], f"simplified {tol}"
    rect = poly.minimum_rotated_rectangle
    return [[round(x, 3), round(z, 3)] for x, z in list(rect.exterior.coords)[:-1]], "rectangle"


def fix_plan(plan):
    notes = []
    for lv in plan["levels"]:
        pieces = []
        for piece in lv["pieces"]:
            fixed, how = fix_ring(piece)
            if how:
                notes.append(how)
            pieces.append(fixed)
        lv["pieces"] = pieces
    return notes


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    write = "--write" in sys.argv
    total = repaired = invalid = 0
    for arg in args:
        path = Path(arg)
        if path.is_dir():
            items = [(f, None) for f in sorted(path.glob("*.json"))]
        else:
            items = [(path, "chunk")]
        for f, kind in items:
            doc = json.loads(f.read_text())
            plans = doc["plans"] if kind == "chunk" else [doc]
            keep = []
            for plan in plans:
                total += 1
                notes = fix_plan(plan)
                problems = B.validate(plan)
                if problems:
                    invalid += 1
                    print(f"  INVALID after repair: {plan['id']}: {problems[0]}")
                    continue
                if notes:
                    repaired += 1
                    plan.setdefault("sourceInfo", {})["ringsRepaired"] = len(notes)
                keep.append(plan)
            if write:
                if kind == "chunk":
                    doc["plans"] = keep
                    f.write_text(json.dumps(doc))
                elif keep:
                    f.write_text(json.dumps(keep[0]))
                else:
                    f.unlink()
    print(f"{total} plans: {repaired} had rings repaired, {invalid} still invalid "
          f"({'written' if write else 'report only'})")


if __name__ == "__main__":
    main()
