"""Extract a crown shell for every plan in a directory.

A crown is whatever the FBX has ABOVE a building's last floor: a stepped top, a
parapet, plant, a ledge. It needs no storeys, so it is not sliced -- the FBX
triangles are clipped to the band and handed to TriangleShell as wedges.

  python tools/source_slice_crowns_batch.py <plansDir> [outJson] [--no-seal] [--cap-top]

Writes src/server/SourceSliceCrowns.json (Rojo syncs it as a ModuleScript).

Each crown is bounded by the building's OWN top outline, not a bounding box. In a
dense sector a box pad reaches into the neighbours and their crowns come along.

The clipped soup is then sealed (source_slice_crown_seal) before it is written.
The FBX is a scan and is not watertight, so the raw soup renders with slits you
can see through; sealing fills them. --no-seal writes the raw soup instead.
"""
from pathlib import Path
import glob, json, sys
ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: E402,F401  (fixes the vendored deps path)
import numpy as np  # noqa: E402
from shapely.geometry import Polygon, Point  # noqa: E402
from shapely.ops import unary_union  # noqa: E402
import source_slice_crown_seal as seal_mod  # noqa: E402

DATA = ROOT / "source_slices"
DEFAULT_OUT = ROOT.parent / "src" / "server" / "SourceSliceCrowns.json"

OUTLINE_PAD = 14.0     # studs of slack around the top plate
MAX_CROWN = 140.0      # studs; a hard backstop when the plan records no top
CROWN_HEADROOM = 10.0  # studs a crown may stand above its building's own top
MIN_TRI_AREA = 0.05


def clip_half(polygon, y, keep_above):
    out = []
    n = len(polygon)
    for i in range(n):
        cur, nxt = polygon[i], polygon[(i + 1) % n]
        cin = (cur[1] >= y) if keep_above else (cur[1] <= y)
        nin = (nxt[1] >= y) if keep_above else (nxt[1] <= y)
        if cin:
            out.append(cur)
        if cin != nin:
            span = nxt[1] - cur[1]
            if abs(span) > 1e-12:
                out.append(cur + (nxt - cur) * ((y - cur[1]) / span))
    return out


def clip_band(triangles, y0, y1):
    kept = []
    for tri in triangles:
        poly = clip_half([tri[0], tri[1], tri[2]], y0, True)
        if len(poly) < 3:
            continue
        poly = clip_half(poly, y1, False)
        if len(poly) < 3:
            continue
        for i in range(1, len(poly) - 1):
            fan = np.array([poly[0], poly[i], poly[i + 1]])
            if np.linalg.norm(np.cross(fan[1] - fan[0], fan[2] - fan[0])) / 2 >= MIN_TRI_AREA:
                kept.append(fan)
    return kept


def world_ring(piece, ox, oz, yaw):
    cos, sin = np.cos(yaw), np.sin(yaw)
    return [(ox + cos * a + sin * b, oz - sin * a + cos * b) for a, b in piece]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    do_seal = "--no-seal" not in flags
    cap_top = "--cap-top" in flags
    plans_dir = Path(args[0]) if args else DATA / "plans_sector"
    out_path = Path(args[1]) if len(args) > 1 else DEFAULT_OUT
    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    lo, hi = triangles.min(axis=1), triangles.max(axis=1)

    payload, report = {}, []
    for path in sorted(glob.glob(str(plans_dir / "*.json"))):
        plan = json.load(open(path))
        o, levels = plan["origin"], plan["levels"]
        last = levels[-1]
        crown_from = o["y"] + last["y"] + last["thickness"]
        # the building's own top outline, with a little slack
        top_shape = unary_union([Polygon(world_ring(p, o["x"], o["z"], o["yaw"])).buffer(0)
                                 for p in last["pieces"]]).buffer(OUTLINE_PAD)
        minx, minz, maxx, maxz = top_shape.bounds
        near = ((hi[:, 1] >= crown_from) & (lo[:, 1] <= crown_from + MAX_CROWN)
                & (hi[:, 0] >= minx) & (lo[:, 0] <= maxx)
                & (hi[:, 2] >= minz) & (lo[:, 2] <= maxz))
        band = triangles[near]
        if len(band) == 0:
            report.append((plan["id"], 0, 0, crown_from, crown_from))
            continue
        # keep only triangles whose centroid sits over this building
        centroids = band.mean(axis=1)
        inside = np.array([top_shape.contains(Point(c[0], c[2])) for c in centroids])
        band = band[inside]
        if len(band) == 0:
            report.append((plan["id"], 0, 0, crown_from, crown_from))
            continue
        # Ceiling at the building's OWN top, not a flat 140 studs. A 14-stud
        # outline pad in a dense sector reaches the neighbours, and a flat band
        # then swept a whole adjacent tower into a 23-stud building's crown:
        # 92 of 123 crowns reached above their own top, and the mean crown came
        # out 1.24x the height of the building under it. The plan already
        # measured where this building stops, so use that.
        info = plan.get("sourceInfo", {})
        own_top = max(float(info.get("fbxTop", 0.0)), float(info.get("greyTop", 0.0)))
        ceiling = own_top + CROWN_HEADROOM if own_top > crown_from else crown_from + MAX_CROWN
        crown_to = min(float(band[:, :, 1].max()), ceiling)
        if crown_to <= crown_from:
            report.append((plan["id"], 0, 0, 0, 0, 0, 0, crown_from, crown_from))
            continue
        tris = clip_band(band, crown_from, crown_to)
        if not tris:
            report.append((plan["id"], 0, 0, crown_from, crown_to))
            continue
        raw = len(tris)
        before = seal_mod.crack_count(tris)
        after = before
        if do_seal:
            tris, st = seal_mod.seal(tris, cap_top=cap_top)
            after = st["cracks"]
            if not tris:
                report.append((plan["id"], 0, 0, 0, raw, before, after, crown_from, crown_to))
                continue
        payload[plan["id"]] = [[[round(float(v), 3) for v in vert] for vert in t] for t in tris]
        report.append((plan["id"], len(tris), 2 * len(tris), raw, raw,
                       before, after, crown_from, crown_to))

    out_path.write_text(json.dumps(payload))
    print(f"{len(payload)} crowns -> {out_path}  (seal={do_seal}, cap_top={cap_top})\n")
    print(f"{'plan':30s} {'raw':>6} {'tris':>6} {'wedges':>7} {'crack':>12} "
          f"{'fromY':>8} {'toY':>8} {'studs':>6}")
    for pid, t, w, _u, raw, cb, ca, a, b in sorted(report, key=lambda r: -r[1]):
        print(f"{pid:30s} {raw:6d} {t:6d} {w:7d} {cb:5d} -> {ca:4d} "
              f"{a:8.1f} {b:8.1f} {b-a:6.1f}")
    cb, ca = sum(r[5] for r in report), sum(r[6] for r in report)
    print(f"\ntotal wedges: {sum(r[2] for r in report)}")
    if cb:
        print(f"crack edges: {cb} -> {ca}  ({1 - ca / cb:.0%} closed)")


if __name__ == "__main__":
    main()
