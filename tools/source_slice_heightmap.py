"""Floors from ROOFS, not from wall cuts.

Every earlier generator cut the FBX with horizontal planes and polygonised the
cut. That needs closed walls, and this export does not have them: it is PLATEAU
(`surfaceMember` meshes, walls and roofs as separate surfaces) and whole wall
runs are missing. At Shibuya PARCO the cut at Y 250 crosses 17 triangles, 411
studs of wall, every end open -- zero outlines at every height from 150 to 350,
and a morphological close of up to 24 studs still finds nothing. Parco also had
no grey over it, so the grey-driven sweep never even looked.

Roofs survive where walls do not. A building's floor plate at height y is
simply everywhere some roof sits above y, so:

  1. rasterise every roof-like triangle into a max-height map H(x, z);
  2. a building is a connected region of the map with a roof over it;
  3. its plate at level y is the part of that region with H above the slab.

Plates made this way are MONOTONE -- a roof above y is above every lower level
too -- so a plate can never be larger than the one below it. The three artefact
classes the map owner flagged (mushroom caps, pinched storeys, floating plates)
cannot occur by construction. What is lost is a true overhang, which Shibuya
barely has.

  python tools/source_slice_heightmap.py --seed 740 1599 --out tools/source_slices/heightmap_test
"""
from pathlib import Path
import argparse
import json
import sys

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "source_slices"
sys.path.insert(0, str(ROOT))
import source_slice_pipeline  # noqa: F401,E402  (puts tools/python_deps* on the path)
import numpy as np  # noqa: E402
import scipy.ndimage as nd  # noqa: E402
from shapely.geometry import box  # noqa: E402
from shapely.ops import unary_union  # noqa: E402
import source_slice_plan_builder as B  # noqa: E402

CELL = 1.0            # studs per height-map cell
ROOF_NY = 0.5         # |normal.y| above this is a roof (or a ground face; MAX ignores those)
WINDOW = 420.0        # studs around the seed to rasterise
MIN_CLEAR_ABOVE = 1.0 # a plate exists where the roof clears the slab top by this much
BRIDGE_CELLS = 2      # join roof regions separated by up to ~4 studs (a wall line)


def roof_triangles(triangles):
    n = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    mag = np.linalg.norm(n, axis=1)
    ny = np.abs(n[:, 1]) / np.maximum(mag, 1e-12)
    # Winding is not consistent in this scan (see the crown work), so take |ny|.
    return triangles[(ny > ROOF_NY) & (mag > 1e-9)]


def rasterise(roofs, x0, z0, nx, nz, cell=CELL):
    """Max roof height per cell; -inf where no roof covers the cell (a street)."""
    H = np.full((nx, nz), -np.inf, dtype=np.float64)
    for tri in roofs:
        xs, zs = tri[:, 0], tri[:, 2]
        i0 = max(0, int(np.floor((xs.min() - x0) / cell)))
        i1 = min(nx - 1, int(np.floor((xs.max() - x0) / cell)))
        j0 = max(0, int(np.floor((zs.min() - z0) / cell)))
        j1 = min(nz - 1, int(np.floor((zs.max() - z0) / cell)))
        if i1 < i0 or j1 < j0:
            continue
        px = x0 + (np.arange(i0, i1 + 1) + 0.5) * cell
        pz = z0 + (np.arange(j0, j1 + 1) + 0.5) * cell
        PX, PZ = np.meshgrid(px, pz, indexing="ij")
        a, b, c = tri
        v0x, v0z = c[0] - a[0], c[2] - a[2]
        v1x, v1z = b[0] - a[0], b[2] - a[2]
        den = v0x * v1z - v1x * v0z
        if abs(den) < 1e-12:
            continue
        wx, wz = PX - a[0], PZ - a[2]
        u = (wx * v1z - v1x * wz) / den
        v = (v0x * wz - wx * v0z) / den
        inside = (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6)
        if not inside.any():
            continue
        y = a[1] + u * (c[1] - a[1]) + v * (b[1] - a[1])
        block = H[i0:i1 + 1, j0:j1 + 1]
        np.maximum(block, np.where(inside, y, -np.inf), out=block)
    return H


def mask_polygon(mask, x0, z0, cell=CELL):
    """World-space polygon of a boolean cell mask, from merged row runs."""
    boxes = []
    for i in range(mask.shape[0]):
        row = mask[i]
        if not row.any():
            continue
        idx = np.flatnonzero(row)
        breaks = np.flatnonzero(np.diff(idx) > 1)
        starts = np.concatenate(([idx[0]], idx[breaks + 1]))
        ends = np.concatenate((idx[breaks], [idx[-1]]))
        for s, e in zip(starts, ends):
            boxes.append(box(x0 + i * cell, z0 + s * cell, x0 + (i + 1) * cell, z0 + (e + 1) * cell))
    return unary_union(boxes) if boxes else None


def clip_above(tri, yc):
    """XZ polygon of the part of a triangle at or above height yc, or None."""
    out = []
    n = len(tri)
    for k in range(n):
        a, b = tri[k], tri[(k + 1) % n]
        ina, inb = a[1] >= yc, b[1] >= yc
        if ina:
            out.append((a[0], a[2]))
        if ina != inb:
            t = (yc - a[1]) / (b[1] - a[1])
            out.append((a[0] + t * (b[0] - a[0]), a[2] + t * (b[2] - a[2])))
    if len(out) < 3:
        return None
    from shapely.geometry import Polygon as _P
    poly = _P(out)
    return poly.buffer(0) if poly.area > 1e-6 else None


def roof_plate(roofs, yc):
    """EXACT plate at height yc: the union of every roof face that lies above it.

    Uses the building's own edges, so a diagonal wall stays one straight edge
    instead of the 1-stud staircase a raster gives (150-207 vertices per ring on
    PARCO, i.e. ~150 wedges per floor)."""
    pieces = [c for c in (clip_above(t, yc) for t in roofs) if c is not None]
    if not pieces:
        return None
    # Faces of one roof meet edge to edge; a hair of buffer closes float seams so
    # the union is one polygon rather than a mosaic of slivers.
    return unary_union([q.buffer(0.05, join_style=2) for q in pieces]).buffer(-0.05, join_style=2)


def building_at(triangles, seed_x, seed_z, key, window=WINDOW, cell=CELL):
    x0, z0 = seed_x - window / 2, seed_z - window / 2
    n = int(window / cell)
    lo, hi = triangles[:, :, [0, 2]].min(axis=1), triangles[:, :, [0, 2]].max(axis=1)
    near = ((hi[:, 0] >= x0) & (lo[:, 0] <= x0 + window) & (hi[:, 1] >= z0) & (lo[:, 1] <= z0 + window))
    local = triangles[near]
    H = rasterise(roof_triangles(local), x0, z0, n, n, cell)

    # A tower's roof and its podium's roof rasterise with a one-cell ring of no
    # roof between them (the wall line), so a plain label splits them: the
    # Cerulean came out as a tower standing on its podium at Y 445 -- two
    # buildings stacked, exactly the artefact the map owner flagged. Bridge gaps
    # of a couple of studs when deciding what belongs together; streets are far
    # wider, so separate blocks stay separate.
    covered = np.isfinite(H)
    bridged = nd.binary_dilation(covered, iterations=BRIDGE_CELLS)
    labels, _ = nd.label(bridged)
    si, sj = int((seed_x - x0) / cell), int((seed_z - z0) / cell)
    label = labels[si, sj]
    if label == 0 or not covered[si, sj]:
        return None, "no roof under the seed"
    region = covered & (labels == label)
    footprint = mask_polygon(region, x0, z0, cell)

    # Base: the lowest point of any surface whose centre lies over the building.
    # Walls reach the ground even where they are patchy, so their minimum is it.
    cx = local[:, :, 0].mean(axis=1)
    cz = local[:, :, 2].mean(axis=1)
    ci = np.clip(((cx - x0) / cell).astype(int), 0, n - 1)
    cj = np.clip(((cz - z0) / cell).astype(int), 0, n - 1)
    # A wall stands ON the footprint edge, so its centre rasterises inside or
    # just outside at random -- excluding it lost the Cerulean's whole shaft and
    # put its base at the crown (Y 813 instead of 95). Dilate a few cells so the
    # walls count; the base is then their true foot.
    near_region = nd.binary_dilation(region, iterations=3)
    mine = near_region[ci, cj]
    base = float(local[mine][:, :, 1].min()) if mine.any() else float(H[region].min())
    top = float(H[region].max())

    # The raster found WHICH building this is; its roof faces give the outline.
    roofs = roof_triangles(local[mine]) if mine.any() else roof_triangles(local)
    plates, y = [], base
    while True:
        plate = roof_plate(roofs, y + B.SLAB + MIN_CLEAR_ABOVE)
        if plate is None or plate.area < B.MIN_FOOTPRINT:
            break
        plates.append((y, plate))
        y += B.PITCH
    # A stalk is not a storey: drop trailing plates under SLIVER_SHARE of the
    # widest, the same rule the section builder now uses.
    widest = max((p.area for _, p in plates), default=0)
    while len(plates) > 2 and plates[-1][1].area < B.SLIVER_SHARE * widest:
        plates.pop()
    if len(plates) < 2:
        return None, f"only {len(plates)} storeys above {B.MIN_FOOTPRINT:.0f} sq studs"

    ox, oz, yaw = B.frame_of(plates[0][1].buffer(0).convex_hull)
    levels, overlap = [], None
    for y, plate in plates:
        # Cells that meet only at a corner become separate parts, and simplifying
        # parts independently can then make them overlap (a contract failure on
        # PARCO's level 22). A small close fuses them first; slivers under the
        # builder's piece minimum are dropped rather than emitted.
        fused = plate.buffer(0.75, join_style=2).buffer(-0.75, join_style=2)
        parts = [g for g in getattr(fused, "geoms", [fused]) if g.area >= B.MIN_FOOTPRINT / 4]
        if not parts:
            continue
        # Fill holes: the builder takes EXTERIOR rings only, so a courtyard with a
        # part inside it emits an island inside its surround -- overlapping
        # pieces. Courtyards were measured at 0.1% of plate area; fill them.
        from shapely.geometry import Polygon as _P
        solid = unary_union([_P(g.exterior) for g in parts])
        clean = solid.simplify(B.SIMPLIFY, preserve_topology=True).buffer(0)
        clean = unary_union([_P(g.exterior) for g in getattr(clean, "geoms", [clean])])
        rings = B.to_local(clean, ox, oz, yaw)
        if not rings:
            continue
        shape = B._rings_shape(rings)
        if shape is None:
            continue
        levels.append(dict(y=round(y - base, 4), thickness=round(B.SLAB, 4),
                           pieces=[[[round(float(a), 3), round(float(b), 3)] for a, b in r] for r in rings]))
        overlap = shape if overlap is None else overlap.intersection(shape)
    if len(levels) < 2 or overlap is None or overlap.is_empty:
        return None, "no common area for a core"
    core = B.largest_core(overlap)
    if core is None:
        return None, "no 4-stud core fits every level"
    hx, hz = min(core[1], 30.0), min(core[2], 30.0)
    plan = dict(
        id=f"hm_{key}",
        origin=dict(x=round(ox, 4), y=round(base, 4), z=round(oz, 4), yaw=round(yaw, 6)),
        levels=levels,
        core=dict(minX=round(core[3] - hx, 4), minZ=round(core[4] - hz, 4),
                  maxX=round(core[3] + hx, 4), maxZ=round(core[4] + hz, 4)),
        sourceInfo=dict(origin="roof height map", seed=[seed_x, seed_z], base=round(base, 2),
                        top=round(top, 2), footprintArea=round(footprint.area, 1),
                        cell=cell, replaces=[]))
    problems = B.validate(plan)
    if problems:
        return None, f"contract: {problems[0]}"
    return plan, None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", nargs=2, type=float, required=True, metavar=("X", "Z"))
    parser.add_argument("--key", default=None)
    parser.add_argument("--out", default=str(DATA / "heightmap_test"))
    args = parser.parse_args()
    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    key = args.key or f"{args.seed[0]:.0f}_{args.seed[1]:.0f}"
    plan, why = building_at(triangles, args.seed[0], args.seed[1], key)
    if plan is None:
        print("NO PLAN:", why)
        return
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{plan['id']}.json").write_text(json.dumps(plan, indent=1))
    info = plan["sourceInfo"]
    print(f"{plan['id']}: {len(plan['levels'])} levels, base {info['base']} top {info['top']}, "
          f"footprint {info['footprintArea']:.0f} sq studs")
    for lv in plan["levels"]:
        from shapely.geometry import Polygon
        a = unary_union([Polygon(p).buffer(0) for p in lv["pieces"]]).area
        print(f"   y+{lv['y']:7.1f}  {len(lv['pieces'])} piece(s)  {a:8.0f} sq studs  "
              f"<= {max(len(p) for p in lv['pieces'])} verts")


if __name__ == "__main__":
    main()
