"""Extract the FBX triangles above a building's last floor, for TriangleShell.

Floors are slices; a crown is not. Everything above the last storey -- a stepped
top, a parapet, a ledge, plant -- already exists in the FBX as triangles, so it
does not need slicing at all. This pulls those triangles out so the Luau side can
render them directly as WedgePairs.

  python tools/source_slice_crown.py <greyKey> <fromY> <toY> [padStuds]

Writes src/server/SourceSliceCrowns.json as {id: [[[x,y,z],[x,y,z],[x,y,z]], ...]}
in Roblox world coordinates, which Rojo syncs into Studio as a ModuleScript.
"""
from pathlib import Path
import csv, json, sys
import numpy as np

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
OUT = ROOT.parent / "src" / "server" / "SourceSliceCrowns.json"


def crown_triangles(key, y_from, y_to, pad=25.0):
    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    rows = {r["n"]: r for r in csv.DictReader(open(DATA / "live_extents.csv"))}
    r = rows[key]
    x0, z0 = float(r["x0"]) - pad, float(r["z0"]) - pad
    x1, z1 = float(r["x1"]) + pad, float(r["z1"]) + pad
    lo, hi = triangles.min(axis=1), triangles.max(axis=1)
    keep = ((hi[:, 1] >= y_from) & (lo[:, 1] <= y_to)
            & (hi[:, 0] >= x0) & (lo[:, 0] <= x1)
            & (hi[:, 2] >= z0) & (lo[:, 2] <= z1))
    return _clip_band(triangles[keep], y_from, y_to)


def _clip_half(polygon, y, keep_above):
    """Sutherland-Hodgman against one horizontal plane."""
    out = []
    count = len(polygon)
    for index in range(count):
        current, following = polygon[index], polygon[(index + 1) % count]
        cur_in = (current[1] >= y) if keep_above else (current[1] <= y)
        nxt_in = (following[1] >= y) if keep_above else (following[1] <= y)
        if cur_in:
            out.append(current)
        if cur_in != nxt_in:
            span = following[1] - current[1]
            if abs(span) > 1e-12:
                out.append(current + (following - current) * ((y - current[1]) / span))
    return out


def _clip_band(triangles, y_from, y_to):
    """Clip every triangle to y_from <= y <= y_to and re-triangulate.

    Selecting triangles that merely INTERSECT the band keeps them whole, so a
    wall triangle spanning the full building height drags the shell down with it
    -- the first run produced a crown spanning Y 434..906 for a band of 815..872.
    """
    kept = []
    for tri in triangles:
        poly = _clip_half([tri[0], tri[1], tri[2]], y_from, True)
        if len(poly) < 3:
            continue
        poly = _clip_half(poly, y_to, False)
        if len(poly) < 3:
            continue
        for i in range(1, len(poly) - 1):          # fan from the first vertex
            fan = np.array([poly[0], poly[i], poly[i + 1]])
            edge = np.cross(fan[1] - fan[0], fan[2] - fan[0])
            if np.linalg.norm(edge) / 2 >= 0.05:   # drop slivers
                kept.append(fan)
    return np.array(kept) if kept else np.empty((0, 3, 3))


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return
    key, y_from, y_to = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
    pad = float(sys.argv[4]) if len(sys.argv) > 4 else 25.0
    sel = crown_triangles(key, y_from, y_to, pad)
    normals = np.cross(sel[:, 1] - sel[:, 0], sel[:, 2] - sel[:, 0])
    areas = np.linalg.norm(normals, axis=1) / 2
    unit = normals / np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    payload = {}
    if OUT.exists():
        payload = json.loads(OUT.read_text())
    payload["fbx_" + key] = [[[round(float(v), 3) for v in vertex] for vertex in tri]
                             for tri in sel]
    OUT.write_text(json.dumps(payload))
    print(f"{key}: {len(sel)} triangles, Y {y_from:.0f}..{y_to:.0f}")
    print(f"  surface area {areas.sum():.0f} sq studs  ->  {2 * len(sel)} wedges")
    print(f"  orientation: horizontal {(np.abs(unit[:,1])>0.9).sum()}  "
          f"sloped {((np.abs(unit[:,1])<=0.9)&(np.abs(unit[:,1])>=0.1)).sum()}  "
          f"vertical {(np.abs(unit[:,1])<0.1).sum()}")
    print(f"  wrote {OUT} ({len(payload)} crown(s))")


if __name__ == "__main__":
    main()
