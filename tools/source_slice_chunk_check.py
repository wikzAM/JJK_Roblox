"""Check every chunk offline, before Studio ever sees one.

`SourceSliceBuilder` and `SourceSliceReplacement` validate hard and fail loudly,
which is right -- but a failure halfway through a 45-chunk session costs a
rebuild, and `Capture` binding a grey that is not there is exactly how the
sector runs nearly replaced the wrong buildings. Everything checkable without a
datamodel is checked here instead.

  python tools/source_slice_chunk_check.py

Per plan (mirroring the Luau contracts):
  * at least 2 levels, each with pieces, ascending y, positive thickness
  * pieces inside a level do not overlap
  * the core lies inside every level's union
  * no ring is self-intersecting, and no level exceeds MAX_PIECE_VERTICES

Across chunks (what a single run cannot see):
  * no grey is claimed by two chunks or two plans
  * no plan id repeats, and none collides with a building that is already live
  * every claimed grey exists in live_buildings.json and is not already replaced
  * every interesting crown carries triangles; every dull one carries a parapet
"""
from pathlib import Path
import json
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
SWEEP = DATA / "sweep"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402  (puts tools/python_deps* on the path)
from shapely.geometry import Polygon, box  # noqa: E402
from shapely.ops import unary_union  # noqa: E402

MAX_PIECE_VERTICES = 512
OVERLAP_TOLERANCE = 0.5      # sq studs; the Luau side raised 0.1 -> 0.5 for float32


def plan_problems(plan):
    out = []
    levels = plan["levels"]
    if len(levels) < 2:
        out.append(f"{len(levels)} levels")
    last_y = None
    for index, level in enumerate(levels):
        if not level["pieces"]:
            out.append(f"level {index} has no pieces")
            continue
        if level["thickness"] <= 0:
            out.append(f"level {index} thickness {level['thickness']}")
        if last_y is not None and level["y"] <= last_y:
            out.append(f"level {index} y {level['y']} not above {last_y}")
        last_y = level["y"]
        polygons = []
        for piece in level["pieces"]:
            if len(piece) > MAX_PIECE_VERTICES:
                out.append(f"level {index} piece has {len(piece)} vertices")
            ring = Polygon(piece)
            if not ring.is_valid:
                out.append(f"level {index} piece is not a simple ring")
            polygons.append(ring)
        for a in range(len(polygons)):
            for b in range(a + 1, len(polygons)):
                shared = polygons[a].intersection(polygons[b]).area
                if shared > OVERLAP_TOLERANCE:
                    out.append(f"level {index} pieces overlap by {shared:.2f} sq studs")
        core = plan["core"]
        core_box = box(core["minX"], core["minZ"], core["maxX"], core["maxZ"])
        outside = core_box.difference(unary_union(polygons)).area
        if outside > OVERLAP_TOLERANCE:
            out.append(f"core sticks {outside:.2f} sq studs outside level {index}")
    return out


def main():
    chunks = sorted(SWEEP.glob("chunks/*.json"))
    if not chunks:
        raise SystemExit("no chunks; run tools/source_slice_chunks.py first")
    live = {b["name"] for b in json.loads((DATA / "live_buildings.json").read_text())
            if b["name"].startswith("BuildingSmooth")}
    applied = {n.strip() for n in (DATA / "applied_greys.txt").read_text().splitlines() if n.strip()}
    applied_ids = {n.strip() for n in (DATA / "applied_ids.txt").read_text().splitlines()
                   if n.strip()}

    owner, ids, failures, buildings, greys = {}, {}, [], 0, 0
    crown_notes = []
    for path in chunks:
        doc = json.loads(path.read_text())
        name = doc["name"]
        for plan in doc["plans"]:
            buildings += 1
            pid = plan["id"]
            if pid in ids:
                failures.append(f"{name}: plan id {pid} also in {ids[pid]}")
            ids[pid] = name
            if pid in applied_ids:
                failures.append(f"{name}: {pid} is ALREADY a live BuildingSourceSlice")
            for problem in plan_problems(plan):
                failures.append(f"{name}/{pid}: {problem}")
            for grey in plan["sourceInfo"]["replaces"]:
                greys += 1
                if grey in owner:
                    failures.append(f"{name}: {grey} also claimed by {owner[grey]}")
                owner[grey] = f"{name}/{pid}"
                if grey not in live:
                    failures.append(f"{name}/{pid}: {grey} is not a live grey")
                if grey in applied:
                    failures.append(f"{name}/{pid}: {grey} was already replaced")
            entry = doc["parapets"].get(pid)
            if entry is None:
                crown_notes.append(f"{pid}: no crown data at all")
            elif entry.get("interesting"):
                if not doc["crowns"].get(pid):
                    crown_notes.append(f"{pid}: interesting but no triangles shipped")
            elif not entry.get("pieces"):
                crown_notes.append(f"{pid}: dull but no parapet outline")

    print(f"{len(chunks)} chunks, {buildings} buildings, {greys} grey claims")
    print(f"crown data: {sum(len(json.loads(p.read_text())['crowns']) for p in chunks)} shells")
    if crown_notes:
        print(f"\n{len(crown_notes)} buildings will get no crown:")
        for note in crown_notes[:15]:
            print("  " + note)
        if len(crown_notes) > 15:
            print(f"  ... and {len(crown_notes) - 15} more")
    if failures:
        print(f"\n{len(failures)} FAILURES:")
        for failure in failures[:40]:
            print("  " + failure)
        if len(failures) > 40:
            print(f"  ... and {len(failures) - 40} more")
        raise SystemExit(1)
    print("\nevery chunk is internally consistent and claims only live, unreplaced greys")


if __name__ == "__main__":
    main()
