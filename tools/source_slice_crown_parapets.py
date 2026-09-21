"""Classify every crown, then give the dull ones a parapet and flag the rest.

  python tools/source_slice_crown_parapets.py <plansDir> [outJson]

Why
---
Four attempts at reconstructing rooftop detail from the scan all failed the same
way -- wedge shells fanned at corners, slice stacks terraced, per-object prisms
terraced again. The reason is in the data, not the algorithm: the median crown
component keeps only **0.38** of a closed box's surface area, because the scan
saw its top and one or two sides and nothing else. There is no solid in there to
recover; any fitter is inventing the missing half, and inventing it differently
each time is what produced the artefacts.

Most roofs do not deserve that effort anyway. So:

  * DULL crown  -> a parapet. The top floor's own outline, extruded a few studs,
                   through PolygonSlab. 1-4 solid parts, no invention, and it
                   reuses polygons SourceSliceBuilder has already validated.
  * INTERESTING -> left alone and marked, for detailed or hand work. Domes,
                   billboards, big stepped crowns.

What counts as interesting, measured over 181 distinct crowns
-------------------------------------------------------------
Two signals separate cleanly; the rest do not.

  slope area share : median 0.00, p75 0.05, p90 0.17   <- most roofs are flat
  band height      : median 24, p90 47 studs

`SLOPE_SHARE >= 0.20 or BAND_TALL >= 50` selects **25 of 181 (14%)** -- the
Cerulean Tower among them, which is the building the map owner named. Loosening
to 0.15/45 gives 31, tightening to 0.25/55 gives 15.

A taper test (bottom-third vs top-third footprint IoU) was tried and dropped: it
comes out bimodal at exactly 0.00 or 1.00 because one of the two footprints is
usually empty, so it carries no information.
"""
from pathlib import Path
import glob
import json
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_crown_boxes as crown  # noqa: E402  (band_for, components)
import numpy as np  # noqa: E402

DATA = ROOT / "source_slices"
DEFAULT_OUT = ROOT.parent / "src" / "server" / "SourceSliceParapets.json"

SLOPE_SHARE = 0.20     # of the crown's surface area that is genuinely sloped
BAND_TALL = 50.0       # studs of crown band
PARAPET_MIN = 2.0      # studs
PARAPET_MAX = 8.0      # studs; a parapet is a low wall, not a storey


def interest(plan, triangles, lo, hi):
    """-> (is_interesting, band_height, slope_share, reason)."""
    band, y0, y1 = crown.band_for(plan, triangles, lo, hi)
    if band is None or len(band) == 0:
        return False, 0.0, 0.0, "no crown geometry"
    height = y1 - y0
    normals = np.cross(band[:, 1] - band[:, 0], band[:, 2] - band[:, 0])
    mag = np.linalg.norm(normals, axis=1)
    ny = np.abs(normals[:, 1]) / np.maximum(mag, 1e-9)
    share = float(mag[(ny > 0.15) & (ny < 0.92)].sum() / max(mag.sum(), 1e-9))
    if share >= SLOPE_SHARE:
        return True, height, share, f"sloped {share:.0%}"
    if height >= BAND_TALL:
        return True, height, share, f"tall {height:.0f} studs"
    return False, height, share, ""


# Half the Cerulean Tower's 719.6 studs. Above this AND with an interesting
# rooftop, a building gets NO crown and is noted instead: the map owner designs
# those roofs case by case. Shell crowns are no longer an option anywhere --
# they cost 355 parts each against a parapet's 10, and the scan they are built
# from is 86% open edges, so they read as gapped plates on anything curved.
MANUAL_MIN_HEIGHT = 360.0


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    plans_dir = Path(args[0]) if args else DATA / "plans_sector2"
    out_path = Path(args[1]) if len(args) > 1 else DEFAULT_OUT

    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    lo, hi = triangles.min(axis=1), triangles.max(axis=1)

    payload, report = {}, []
    for path in sorted(glob.glob(str(plans_dir / "*.json"))):
        plan = json.load(open(path))
        special, height, share, why = interest(plan, triangles, lo, hi)
        o, last = plan["origin"], plan["levels"][-1]
        top = o["y"] + last["y"] + last["thickness"]
        building_height = last["y"] + last["thickness"]
        # THREE outcomes now, not two. The interest measurement is kept under
        # `shellDeclined`, but it no longer selects a shell -- nothing does.
        # Big AND interesting means hands off, for manual design later.
        manual = special and building_height >= MANUAL_MIN_HEIGHT
        entry = {"yaw": round(o["yaw"], 6), "ox": round(o["x"], 3), "oz": round(o["z"], 3),
                 "interesting": False, "shellDeclined": special, "manual": manual,
                 "buildingHeight": round(building_height, 1),
                 "bandHeight": round(float(height), 1),
                 "slopeShare": round(share, 3), "why": why}
        if not manual:
            thickness = float(np.clip(height, PARAPET_MIN, PARAPET_MAX))
            entry["y"] = round(top, 3)
            entry["h"] = round(thickness, 3)
            # the top floor's OWN outline: already validated by the builder, so
            # nothing here can invent geometry the plan does not already assert
            entry["pieces"] = [[[round(float(a), 3), round(float(b), 3)] for a, b in piece]
                               for piece in last["pieces"]]
        payload[plan["id"]] = entry
        report.append((plan["id"], special, height, share, why))

    out_path.write_text(json.dumps(payload))
    special = [r for r in report if r[1]]
    manual = [pid for pid, e in payload.items() if e.get("manual")]
    print(f"{len(payload)} crowns -> {out_path}")
    print(f"  parapet: {len(payload) - len(manual)}   manual (no crown, noted): {len(manual)}")
    print(f"  measured interesting: {len(special)}, parapeted unless also >= "
          f"{MANUAL_MIN_HEIGHT:.0f} studs tall")
    ranked = sorted(((payload[pid]["buildingHeight"], pid, payload[pid])
                     for pid, e in payload.items() if e.get("shellDeclined")), reverse=True)
    lines = ["# Rooftops worth designing by hand", "",
             "Measured interesting by the original rule (slope >= 0.20 or band >= 50 studs).",
             f"**MANUAL** = no crown was built; the roof waits on a hand-made one "
             f"(building >= {MANUAL_MIN_HEIGHT:.0f} studs, half the Cerulean Tower).",
             "Everything else carries a parapet. Ranked so the next ones worth doing",
             "by hand are obvious even below that bar.", "",
             "| building | height | band | slope | why | state |", "|---|---|---|---|---|---|"]
    for h, pid, e in ranked:
        lines.append(f"| `{pid}` | {h:.0f} | {e['bandHeight']:.0f} | {e['slopeShare']:.2f} | "
                     f"{e['why']} | {'**MANUAL**' if e.get('manual') else 'parapet'} |")
    out_path.with_name("rooftops_for_manual_design.md").write_text(chr(10).join(lines) + chr(10))
    print(f"  worklist -> {out_path.with_name(chr(39) + chr(39)) if False else out_path.parent}/rooftops_for_manual_design.md")
    print(f"{'plan':30s} {'bandH':>6} {'slope':>6}  why")
    for pid, is_special, height, share, why in sorted(special, key=lambda r: -r[2]):
        print(f"{pid:30s} {height:6.0f} {share:6.2f}  {why}")


if __name__ == "__main__":
    main()
