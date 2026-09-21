"""Turn FBX cross-sections into SourceSliceBuilder plans, for any seed.

SourceSliceFbxSample.luau hand-carries one seed's polygons as constants. This
generalises that: given a group of live greys that are really one building, it
slices world_triangles.npz under their shared centre, detects the bands where
the section stops changing, fits a frame to the section rather than to any live
model, and emits a plan that satisfies the builder's contract.

Offline only - reads world_triangles.npz and live_buildings.json, talks to no
Studio session and writes nothing live.

  python tools/source_slice_plan_builder.py                 # top candidates
  python tools/source_slice_plan_builder.py --key 16_7714   # one group
  python tools/source_slice_plan_builder.py --limit 20 --out tools/source_slices/plans

Every emitted plan is validated here against the same rules SourceSliceBuilder
enforces in Luau, so a plan that fails is reported rather than written.
"""
from pathlib import Path
import argparse
import json
import re
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from source_slice_pipeline import sections  # noqa: E402  (also fixes the deps path)
from polygon_slab_sim import buildable  # noqa: E402
from source_slice_roofs import roof_plate, roofs_in, solid, slice_at, main_roof, polygons  # noqa: E402
import numpy as np  # noqa: E402
from shapely.geometry import Point, Polygon, box  # noqa: E402
from shapely.ops import unary_union  # noqa: E402
import csv  # noqa: E402

DATA = ROOT / "source_slices"

# Mirrors of the builder's constants (SourceSliceBuilder.luau).
SLAB = 1.5 / 0.28
MIN_CLEAR = 2.0 / 0.28
PITCH = SLAB + 3.5 / 0.28
MAX_PIECE_VERTICES = 512

STEP = 2.0            # vertical sampling interval when hunting for bands
BAND_IOU = 0.98       # below this the section has genuinely changed shape
MIN_BAND = 12.0       # bands thinner than this are roof clutter, not storeys
SIMPLIFY = 0.9        # stud tolerance; keeps wedge counts sane
# PolygonSlab's ear clipper gives up after 2048 search states, and its error text
# blames a 0.05-stud minimum that is not the actual cause -- the outlines that
# defeat it have minimum edge 0.92-2.06 studs and minimum angle 47-68 degrees.
# They are just too intricate. Rather than emit a plan that dies in Studio, walk
# a coarser ladder until the ring provably triangulates (polygon_slab_sim).
SIMPLIFY_LADDER = (SIMPLIFY, 1.4, 2.0, 3.0, 4.5)
BUILDABILITY_CHECK_VERTICES = 14   # below this a ring always tiles; do not pay for the check
BUILDABILITY_STATES = 300          # replica search cap; a cheap "no" just costs one simplify step
# Offsets tried around a floor's own height before giving up and using its band.
SECTION_PROBES = (0.0, 0.6, -0.6, 1.2, -1.2, 2.0, -2.0)
# A per-floor section smaller than this share of its own band is an artifact.
BAND_TRUST_SHARE = 0.4
# ...and the SAME distrust on the high side, which was missing. The probe loop
# deliberately takes the LARGEST section in its window to dodge slivers, so at a
# transition it will happily take a slice that has swallowed the neighbouring
# building. Nothing capped that: 83 of 1,287 plans had a >4x area jump between
# consecutive storeys, the worst 43x, which is what makes a building read as
# three different buildings stacked on top of each other.
# REJECTED: an upper bound here (shape.area > 2.5 * band) looked symmetric with
# the low-side guard and was wrong. A band can legitimately be far smaller than a
# storey inside it, so the bound threw away a correct 31,806 sq stud plate on
# fbx_13_-15642_1589_16325 and replaced it with a 746 sq stud one -- it fixed one
# building of four and broke another. Continuity between neighbouring storeys,
# below, is the check that actually holds.
# A storey smaller than this share of BOTH its neighbours is a hole in the scan,
# not a real neck, and is replaced by the floor below. A trailing storey smaller
# than this share of the one under it is a mast, and is dropped -- the crown
# already covers whatever sits up there.
PINCH_SHARE = 0.25
# Where no wall section closes, a floor used to COPY ITS BAND's shape -- the
# source of the pinches, mushroom caps and wrong outlines the map owner flagged.
# It now takes the ROOF ENVELOPE at its own height instead (source_slice_roofs),
# clipped to the building's own region grown by this much, and falls back to
# the band only if even that is empty. Wall sections stay first choice: they
# are exact where they close, which is how the Cerulean reached 0.998.
ROOF_REGION_PAD = 6.0
# LEVEL CURVES (the map owner's framing): a floor is the building's slice at its
# height, bounded by the perimeter and filled. `slice_at` gives that slice from
# the roof envelope with seams up to 2*LEVEL_SEAM closed; a wall section is kept
# only where it closes AND stays inside it (CONTAIN_SHARE), which is what stops a
# floor spilling out of the FBX -- 876 of 2,004 buildings had a floor more than
# 10% outside it, some 100%.
LEVEL_SEAM = 3.0
CONTAIN_SHARE = 0.6
CONTAIN_TOLERANCE = 1.5
SLIVER_SHARE = 0.15
COLLINEAR = 0.6       # drop vertices this close to their neighbours' line

MIN_FOOTPRINT = 400.0  # sq studs; below this it is a sliver, not a floor plate
MAX_OVERSIZE = 8.0     # grey/FBX beyond this means we grabbed a fragment
MAX_CORE_SHARE = 0.6   # core swallowing the plate means nothing is left to floor

# Section selection. A section counts as "this building" when it overlaps the
# greys' measured footprint enough; a single centre point does not survive
# fragment groups, whose mean lands in a courtyard (measured 37.9 and 67.6 studs
# outside the nearest polygon on two of the six review seeds).
MIN_SECTION_OVERLAP = 300.0   # sq studs of intersection with the grey region
MIN_SECTION_INSIDE = 0.35     # fraction of the section that must be in-region

# Rooftop clutter. The user does not want signs or AC units modelled, only the
# building. Clutter is both SMALL and SHORT; a genuine setback is small but runs
# for storeys, so area alone would cut real architecture off the top.
# TUNED DOWN Sept 17 after measuring. At 0.25 / 36 studs this fired on 25 of 55
# plans and removed up to TWO real storeys: fbx_poly_170_6 lost 34 studs while the
# live greys reach 229.3 there, and v5 (no trimming) had matched that top to 0.8
# studs. Half the map is not rooftop clutter. The share is tighter now, and the
# trim can never take the roof more than one storey below what the live building
# actually shows -- so a genuine crown survives even if it is slim.
ROOF_MIN_SHARE = 0.15         # a section under this share of the body is a candidate
ROOF_MAX_RUN = 24.0           # ...and is clutter only if it persists for less than this

# Ground this pipeline must never touch, as (x, z, radius) in studs. These are
# hand-built and would be destroyed by a replacement, so the fence is permanent
# and not a CLI flag you can forget to pass. A group is rejected if ANY of its
# members falls inside -- testing only the group centre would let a group with
# one foot in the zone through.
#   Shibuya Sky (Workspace.Buildings.Building1): the tallest thing on the map,
#   measured X -793..-468, Z -120..217, Y 57..967, 29,907 parts with a furnished
#   interior. It is not a BuildingSmooth_* grey so it is not a candidate anyway,
#   but the fence also stops a generated neighbour landing on top of it.
PROTECTED = (
    (-630.0, 48.0, 260.0, "Shibuya Sky / Building1"),
)


def load():
    """Live geometry, measured where possible.

    live_buildings.json stores Model:GetBoundingBox(), which is PIVOT-oriented,
    and these models' pivots are not upright -- so its `base`/`top` and its
    footprint are not world quantities at all. On fbx_poly_170_0 it reports
    Y 101.6..206.7 where the real measured span is 121..233. live_extents.csv
    (SourceSliceLiveExtents.Dump in Studio, via PartExtents) is wedge-aware and
    world-axis, so it overrides those fields whenever it is present.
    """
    triangles = np.load(DATA / "world_triangles.npz")["triangles"]
    live = [b for b in json.loads((DATA / "live_buildings.json").read_text())
            if b["name"].startswith("BuildingSmooth")]
    measured = {}
    path = DATA / "live_extents.csv"
    if path.exists():
        with open(path, newline="") as fh:
            for row in csv.DictReader(fh):
                measured["BuildingSmooth_" + row["n"]] = row
    for b in live:
        cf, size = b["cf"], b["size"]
        m = measured.get(b["name"])
        if m:
            b["base"], b["top"] = float(m["y0"]), float(m["y1"])
            b["rect"] = (float(m["x0"]), float(m["z0"]), float(m["x1"]), float(m["z1"]))
            b["footprint"] = float(m["fa"])          # material area, not a bbox
            b["measured"] = True
        else:
            b["base"] = cf[1] - size[1] / 2
            b["top"] = cf[1] + size[1] / 2
            half_x, half_z = size[0] / 2, size[2] / 2
            b["rect"] = (cf[0] - half_x, cf[2] - half_z, cf[0] + half_x, cf[2] + half_z)
            b["footprint"] = size[0] * size[2]
            b["measured"] = False
    print(f"  live: {sum(1 for b in live if b['measured'])}/{len(live)} measured "
          f"from live_extents.csv")
    return triangles, live


def source_key(name):
    """BuildingSmooth_<key>[_Body01|_ResidualBody02|_Residual_<guid>_Body01]."""
    stem = name[len("BuildingSmooth_"):]
    stem = re.sub(r"_Residual_[0-9a-f]+_Body\d+$", "", stem)
    stem = re.sub(r"_ResidualBody\d+$", "", stem)
    stem = re.sub(r"_Residual$", "", stem)
    stem = re.sub(r"_Body\d+$", "", stem)
    return stem


def groups(live, min_members=2):
    out = {}
    for b in live:
        out.setdefault(source_key(b["name"]), []).append(b)
    return {k: v for k, v in out.items() if len(v) >= min_members}


class Slicer:
    """Sections of the FBX restricted to one neighbourhood."""

    def __init__(self, triangles, cx, cz, region=None, margin=300.0):
        lo = triangles[:, :, [0, 2]].min(axis=1)
        hi = triangles[:, :, [0, 2]].max(axis=1)
        keep = ((hi[:, 0] >= cx - margin) & (lo[:, 0] <= cx + margin)
                & (hi[:, 1] >= cz - margin) & (lo[:, 1] <= cz + margin))
        self.local = triangles[keep]
        self.point = Point(cx, cz)
        self.region = region
        self._cache = {}

    def at(self, y):
        """The section that is THIS building at height y, or None.

        Selection is by overlap with the greys' measured footprint, not by a
        single centre point. The mean of a fragment group's centres routinely
        lands in a courtyard: on fbx_poly_170_0 it sits 37.9 studs outside the
        nearest section, and on fbx_poly_170_2 67.6 studs, so point containment
        reported "empty" across the whole lower half of both buildings.
        Region overlap also holds on at the top, where it recovered 20 more
        studs on fbx_poly_130_47.
        """
        key = round(float(y), 3)
        if key not in self._cache:
            polygons = sections(self.local, key)[0]
            chosen = None
            if self.region is not None:
                mine = []
                for p in polygons:
                    if p.area < MIN_FOOTPRINT:
                        continue
                    shared = p.intersection(self.region).area
                    if shared < MIN_SECTION_OVERLAP or shared / p.area < MIN_SECTION_INSIDE:
                        continue
                    mine.append(p)
                # ALL of this building, not just its biggest piece. A section that
                # is several disjoint polygons -- two wings, a courtyard, or an
                # L-shape the mesh split -- was losing everything but the largest,
                # which is the whole of the remaining under-coverage: the worst
                # plans covered 11-56% of their own floor while spilling ~0.5%.
                # SourceSliceBuilder takes a list of pieces per level already.
                if mine:
                    chosen = unary_union(mine)
            if chosen is None:
                hits = [p for p in polygons if p.contains(self.point)]
                chosen = max(hits, key=lambda q: q.area) if hits else None
            self._cache[key] = chosen
        return self._cache[key]

    def edge(self, inside, outside, iterations=24):
        """Bisect for the last Y that still has a section under the centre."""
        for _ in range(iterations):
            mid = (inside + outside) / 2
            if self.at(mid) is None:
                outside = mid
            else:
                inside = mid
        return inside


def _same_section(a, b):
    union = a.union(b).area
    return union > 0 and a.intersection(b).area / union >= BAND_IOU


def bands(slicer, bottom, top):
    """Split [bottom, top] where the cross-section genuinely changes shape.

    Gaps are BRIDGED, not treated as band boundaries, and a single disagreeing
    sample is treated as noise rather than a setback.

    The Shibuya export is not watertight, so polygonising a continuous tower
    yields None at scattered heights and the occasional half-closed contour.
    On fbx_poly_250_80 the section drops out at 5 separate heights between
    Y 223 and Y 269. The previous version ended a band at every one of those,
    which chopped a solid ~35-stud tower into five 2-10 stud slivers; MIN_BAND
    then deleted all five, and every floor inherited the podium's 11,487 plate.
    41% of the top floors' area hung outside the building as a result.
    """
    samples = []
    y = bottom
    while y <= top:
        polygon = slicer.at(y)
        if polygon is not None:
            samples.append((y, polygon))
        y += STEP
    if not samples:
        return []

    found = []
    start, reference, last = samples[0][0], samples[0][1], samples[0][0]
    index = 1
    while index < len(samples):
        y, current = samples[index]
        if _same_section(current, reference):
            last = y
            index += 1
            continue
        # One odd sample between two matching ones is a polygonisation artifact
        # (a partially closed contour), not a storey boundary.
        if index + 1 < len(samples) and _same_section(samples[index + 1][1], reference):
            index += 1
            continue
        found.append((start, (last + y) / 2, reference))
        start, reference, last = y, current, y
        index += 1
    found.append((start, max(top, last), reference))
    return [b for b in found if b[1] - b[0] >= MIN_BAND]


def frame_of(polygon):
    """Fit the origin frame to the section's minimum-area rectangle."""
    rect = np.array(polygon.minimum_rotated_rectangle.exterior.coords)[:-1]
    edge = rect[1] - rect[0]
    other = rect[2] - rect[1]
    if np.linalg.norm(other) > np.linalg.norm(edge):
        edge = other
    unit = edge / np.linalg.norm(edge)
    yaw = float(np.arctan2(-unit[1], unit[0]))
    centre = polygon.minimum_rotated_rectangle.centroid
    return float(centre.x), float(centre.y), yaw


def _ring_at(polygon, ox, oz, yaw, tolerance):
    simplified = polygon.simplify(tolerance, preserve_topology=True)
    ring = np.array(simplified.exterior.coords)[:-1]
    if len(ring) < 3:
        return None
    cos, sin = np.cos(yaw), np.sin(yaw)
    dx, dz = ring[:, 0] - ox, ring[:, 1] - oz
    local = np.stack([cos * dx - sin * dz, sin * dx + cos * dz], axis=1)
    kept = []
    for i in range(len(local)):
        a, b, c = local[i - 1], local[i], local[(i + 1) % len(local)]
        u, v = b - a, c - a
        if abs(u[0] * v[1] - u[1] * v[0]) > COLLINEAR:
            kept.append(b)
    if len(kept) < 3 or len(kept) > MAX_PIECE_VERTICES:
        return None
    return snap_rectangle(np.array(kept))


RING_STATS = {"escalated": 0, "dropped": 0}
_BUILDABLE_CACHE = {}


def _ring_to_local(polygon, ox, oz, yaw):
    """The most faithful ring PolygonSlab will actually accept.

    Tries the normal tolerance first and only coarsens when the ring cannot be
    triangulated, so fidelity is given up a step at a time and only where it is
    the price of building at all. Returns None if even the coarsest fails, in
    which case the caller falls back to the level's band.
    """
    for index, tolerance in enumerate(SIMPLIFY_LADDER):
        ring = _ring_at(polygon, ox, oz, yaw, tolerance)
        if ring is None:
            continue
        # Only pay for the check where it can fail. The triangulator is cheap on a
        # ring it can tile and expensive on one it cannot -- it burns the whole
        # 2048-state budget before admitting defeat, and the Python replica is far
        # slower than the Luau original. Every observed failure had >= 18 vertices;
        # simple rings always tile, so checking them stalled the run for no gain.
        if len(ring) < BUILDABILITY_CHECK_VERTICES:
            if index:
                RING_STATS["escalated"] += 1
            return ring
        key = tuple(round(float(v), 2) for point in ring for v in point)
        ok = _BUILDABLE_CACHE.get(key)
        if ok is None:
            ok = buildable([tuple(point) for point in ring], limit=BUILDABILITY_STATES)[0]
            _BUILDABLE_CACHE[key] = ok
        if ok:
            if index:
                RING_STATS["escalated"] += 1
            return ring
    RING_STATS["dropped"] += 1
    return None


def to_local(geometry, ox, oz, yaw):
    """Every ring of a Polygon or MultiPolygon, in the origin frame.

    Returns a list of rings (the builder's `pieces`), or None if nothing usable
    survives. Disjoint parts of one section are separate pieces, not a hull.
    """
    parts = getattr(geometry, "geoms", None)
    parts = list(parts) if parts is not None else [geometry]
    rings = []
    for part in parts:
        if part.is_empty or part.area < 40:
            continue
        ring = _ring_to_local(part, ox, oz, yaw)
        if ring is not None:
            rings.append(ring)
    return rings or None


def snap_rectangle(ring, tolerance=0.02):
    """Square up a ring that is a rectangle to within export noise.

    PolygonSlab emits ONE Part per floor only when isRectangle() passes; four
    sides is not enough, the corners have to agree. Measured sections miss by
    a few tenths of a stud, which silently triangulated every floor into wedges
    (the 16_7714 seed produced 56 where 0 were expected).
    """
    if len(ring) != 4:
        return ring
    polygon = Polygon(ring)
    if not polygon.is_valid or polygon.area <= 0:
        return ring
    rect = polygon.minimum_rotated_rectangle
    if polygon.symmetric_difference(rect).area / polygon.area > tolerance:
        return ring
    corners = np.array(rect.exterior.coords)[:-1]
    # Keep the original vertex order so winding and edge pairing are unchanged.
    used, ordered = set(), []
    for point in ring:
        index = min((i for i in range(len(corners)) if i not in used),
                    key=lambda i: np.hypot(*(corners[i] - point)))
        used.add(index)
        ordered.append(corners[index])
    return np.array(ordered)


def _rings_shape(rings):
    """Union of a level's pieces, for core/overlap maths. None if unusable."""
    polys = []
    for ring in rings:
        poly = Polygon(ring)
        if poly.is_valid and poly.area >= 40:
            polys.append(poly)
    if not polys:
        return None
    shape = unary_union(polys)
    return shape if not shape.is_empty and shape.area >= 40 else None


def largest_core(region, limit=60.0):
    """Biggest axis-aligned rectangle the builder will accept, anywhere in region.

    It does NOT have to be centred on the origin. SourceSliceBuilder's contract
    takes an explicit {minX,minZ,maxX,maxZ}; only this search insisted the core
    straddle (0,0). That cost 39 of 83 groups once per-floor plates made the
    level intersection both tighter and off-centre -- a setback tower sits away
    from the podium centroid, so no centred rectangle fits even though a
    perfectly good off-centre one does.

    Returns (area, halfX, halfZ, centreX, centreZ).
    """
    if region.is_empty or region.area <= 0:
        return None
    minx, minz, maxx, maxz = region.bounds

    def fits(cx, cz, hx, hz):
        return region.contains(Polygon([(cx - hx, cz - hz), (cx + hx, cz - hz),
                                        (cx + hx, cz + hz), (cx - hx, cz + hz)]))

    def grow(cx, cz, first_axis_x):
        if not fits(cx, cz, 2.0, 2.0):
            return None
        hx = hz = 2.0
        for _ in range(2):                      # widen, then deepen, then retry
            if first_axis_x:
                lo, high = hx, limit
                while high - lo > 0.25:
                    mid = (lo + high) / 2
                    lo, high = (mid, high) if fits(cx, cz, mid, hz) else (lo, mid)
                hx = lo
                lo, high = hz, limit
                while high - lo > 0.25:
                    mid = (lo + high) / 2
                    lo, high = (mid, high) if fits(cx, cz, hx, mid) else (lo, mid)
                hz = lo
            else:
                lo, high = hz, limit
                while high - lo > 0.25:
                    mid = (lo + high) / 2
                    lo, high = (mid, high) if fits(cx, cz, hx, mid) else (lo, mid)
                hz = lo
                lo, high = hx, limit
                while high - lo > 0.25:
                    mid = (lo + high) / 2
                    lo, high = (mid, high) if fits(cx, cz, mid, hz) else (lo, mid)
                hx = lo
        return (4 * hx * hz, hx, hz, cx, cz) if hx >= 2 and hz >= 2 else None

    best = None
    step = max(2.0, min(maxx - minx, maxz - minz) / 16)
    xs = np.arange(minx + 2, maxx - 2 + 1e-9, step)
    zs = np.arange(minz + 2, maxz - 2 + 1e-9, step)
    representative = region.representative_point()
    centres = [(float(x), float(z)) for x in xs for z in zs]
    centres.append((0.0, 0.0))                  # the old behaviour, still preferred when it wins
    centres.append((float(representative.x), float(representative.y)))
    for cx, cz in centres:
        for first in (True, False):
            found = grow(cx, cz, first)
            if found and (best is None or found[0] > best[0]):
                best = found
    return best


def build_plan(key, members, slicer):
    """None plus a reason when this group cannot produce a valid plan."""
    RING_STATS["escalated"] = RING_STATS["dropped"] = 0
    lowest = min(b["base"] for b in members)
    highest = max(b["top"] for b in members)

    # SCAN, do not bisect. edge() bisected for the last Y with a section, which
    # assumes one contiguous interval. Real towers go YES/no/YES on the way up
    # (fbx_poly_170_0 at Y 206/212/218), so bisection stopped at the first gap
    # and silently threw away everything beyond it.
    grid = [float(y) for y in np.arange(lowest - STEP, highest + STEP, STEP)]
    present = [y for y in grid if slicer.at(y) is not None]
    if not present:
        return None, "no FBX section over the grey footprint"
    fbx_bottom, top = present[0], present[-1]

    # Trim rooftop clutter: signs, parapets, plant. Measured against the body's
    # median section area, and only when the small run is too short to be a real
    # setback, so a slim tower on a wide podium survives.
    areas = [slicer.at(y).area for y in present]
    body = float(np.median(areas))
    trimmed = 0.0
    cut = len(present)
    while cut > 1 and areas[cut - 1] < ROOF_MIN_SHARE * body:
        cut -= 1
    if cut < len(present) and (present[-1] - present[cut - 1]) < ROOF_MAX_RUN:
        # Never cut more than one storey below the live building's own top.
        floor_limit = highest - PITCH
        candidate = max(present[cut - 1], min(top, floor_limit))
        if candidate < top:
            trimmed = top - candidate
            top = candidate
    if top - fbx_bottom < 2 * PITCH:
        return None, f"FBX band too short ({top - fbx_bottom:.1f} studs)"

    found = bands(slicer, fbx_bottom, top)
    if not found:
        return None, "no band survived the minimum thickness"

    # ANCHOR THE BASE TO THE LIVE GREYS.
    # The FBX is hollow below roughly Y 170 at many footprints while the live
    # buildings run down to the neighbourhood ground -- 52 studs lower on
    # fbx_poly_170_0, 48 on fbx_poly_170_2. The user has already rejected a
    # floating overlay once ("the grey live tower goes down to the neighborhood
    # base"), and the hand-authored 16_7714 seed anchors to the live base for
    # exactly this reason. Extrude the lowest band down instead of starting in
    # mid-air. Only downwards: never raise the base above the FBX.
    bottom = min(lowest, fbx_bottom)
    if fbx_bottom - bottom > 0.01:
        found[0] = (bottom, found[0][1], found[0][2])
    base_extension = fbx_bottom - bottom

    ox, oz, yaw = frame_of(found[0][2])
    shaped = []
    for lo, hi, polygon in found:
        rings = to_local(polygon, ox, oz, yaw)
        if not rings:
            continue
        shape = _rings_shape(rings)
        if shape is None:
            continue
        shaped.append((lo, hi, rings, shape))
    if not shaped:
        return None, "no band produced a usable polygon"

    # Floors stop at the top of the last STABLE band, not at the last height with
    # any geometry at all. Above a tower's last real storey the FBX still has the
    # crown -- a sloped roof, plant screen or spire -- and horizontal cuts through
    # a slope give short, ragged, wildly varying sections. bands() already drops
    # those (they fall under MIN_BAND), but `top` still pointed past them, so the
    # floor loop kept going and band_for() handed each one the TOWER's plate.
    # That is what puts a flat roof with storeys in it on top of a building that
    # should taper. Measured on the Cerulean Tower (4_-9770_4222_-4948): the tower
    # is a clean 52,300 pentagon to Y 783, then 12,598-18,813 with 33/23/17/14
    # vertices to Y 795, then 43,422 to Y 804. Only the first is a building.
    roof_top = shaped[-1][1]
    if roof_top < top:
        crown_trimmed = top - roof_top
        top = roof_top
    else:
        crown_trimmed = 0.0

    # A floor sits at every pitch step; its outline is whichever band it lands in.
    # Thin bands get dropped above, so a floor can fall in a gap - it takes the
    # nearest surviving band rather than being skipped, which would leave the
    # tower partly unfloored.
    def band_for(y):
        inside = next((s for s in shaped if s[0] <= y < s[1]), None)
        if inside is not None:
            return inside
        return min(shaped, key=lambda s: 0 if s[0] <= y < s[1]
                   else min(abs(y - s[0]), abs(y - s[1])))

    # A floor takes the section at ITS OWN height wherever one exists, and only
    # falls back to its band otherwise (inside a gap, or below the FBX in the
    # base extension). Bands are a coarse abstraction: a tapering building has no
    # prismatic band at all, so every band is thin, MIN_BAND drops them, and the
    # floors inherit a plate from the wrong height. Measured on the 41-plan batch,
    # band-only plates put a median 40% of the top floors' area OUTSIDE the FBX.
    levels, overlap, exact, roofed = [], None, 0, 0
    reach = slicer.region.buffer(ROOF_REGION_PAD) if slicer.region is not None else None
    my_roofs = roofs_in(slicer.local, reach)

    _slices = {}

    def level_slice(at):
        """The building's filled level curve for a floor at `at` (world XZ)."""
        key = round(at, 3)
        if key not in _slices:
            plate = slice_at(my_roofs, at + SLAB + 1.0, reach, LEVEL_SEAM) if len(my_roofs) else None
            if plate is not None:
                big = max((g.area for g in polygons(plate)), default=0.0)
                keep = [g for g in polygons(plate) if g.area >= max(100.0, 0.03 * big)]
                plate = unary_union(keep) if keep else None
            _slices[key] = plate if plate is not None and plate.area >= MIN_FOOTPRINT else None
        return _slices[key]

    def local_of(world):
        rings = to_local(world, ox, oz, yaw) if world is not None else None
        shape = _rings_shape(rings) if rings else None
        return (rings, shape) if shape is not None else (None, None)

    def world_of(rings):
        cos, sin = np.cos(yaw), np.sin(yaw)
        return unary_union([Polygon([(ox + cos * a + sin * b, oz - sin * a + cos * b) for a, b in r]).buffer(0)
                            for r in rings])

    def contained(world, at):
        """`world` clipped to the building's own slice, or None if most of it
        was outside it (then it was never this building's floor)."""
        env = level_slice(at)
        if env is None or world is None:
            return world
        parts = polygons(world.intersection(env.buffer(CONTAIN_TOLERANCE), grid_size=0.01))
        if not parts:
            return None
        clipped = unary_union(parts)
        return clipped if clipped.area >= CONTAIN_SHARE * world.area else None

    def roof_level(at):
        return local_of(level_slice(at))

    y = bottom
    while y + SLAB <= top:
        middle = y + SLAB / 2
        local = ring = None
        if middle >= fbx_bottom:
            # Probe around the floor's own height, not just at it. The export
            # drops sections at scattered levels, and a single miss sends the
            # floor to its band -- which is badly wrong on a tapering building.
            # fbx_poly_250_79 lost exactly this way: its top two floors inherited
            # a 39,336 plate from ten storeys down while the real sections there
            # are 26,299 and 15,559, putting 34.5% and 61.1% of the plate outside
            # the building. Every other level of that plan matches to 0.2%.
            # Take the BEST section in the probe window, not the first one found.
            # At a podium/tower transition the nearest slice can be a sliver while
            # a real section sits a stud away: on the Cerulean Tower, Y 159 gives
            # 1,259 sq studs at the centre with ~20,000 alongside. Taking the
            # first hit there forced the band fallback, which parked a 56,604
            # plate where the building has almost nothing -- 97.8% of that one
            # floor hung outside the FBX.
            section = None
            for probe in SECTION_PROBES:
                candidate_section = slicer.at(middle + probe)
                if candidate_section is None:
                    continue
                if section is None or candidate_section.area > section.area:
                    section = candidate_section
            if section is not None:
                section = contained(section, y)
            if section is not None:
                candidate = to_local(section, ox, oz, yaw)
                shape = _rings_shape(candidate) if candidate else None
                # Distrust a plate that is a small fraction of its own band. A
                # band IS the stable shape over that height range, so a storey
                # inside it should match it; one that does not is a slicing
                # artifact at a transition. On the Cerulean Tower the podium->
                # tower transition yields a 1,259 sq stud sliver between a 72,420
                # floor and a 58,309 floor, and because the builder requires one
                # core inside EVERY level, that single sliver drove the running
                # intersection to zero and rejected the whole 43-storey building.
                if shape is not None:
                    home = band_for(y)
                    if home is not None and shape.area < BAND_TRUST_SHARE * home[3].area:
                        shape = None
                if shape is not None:
                    local, ring = candidate, shape
                    exact += 1
        # Only for gaps INSIDE the building. Below the lowest closed section the
        # band is deliberately extended to the live ground (see ANCHOR THE BASE),
        # and on the Cerulean -- which the map owner called perfect -- the roof
        # envelope there changed 10 of 41 floors (IoU 0.62 against the tuned
        # plan). Above it, band-copying is what produced the wrong shapes.
        if local is None and middle >= fbx_bottom:
            local, ring = roof_level(y)
            if local is not None:
                roofed += 1
        if local is None:
            band = band_for(y)
            local, ring = band[2], band[3]
            # The band may copy a shape from another height; never let it stand
            # outside this building's own slice.
            band_world = world_of(local)
            kept = contained(band_world, y)
            if kept is not None and kept.area < band_world.area - 1.0:
                clipped_local, clipped_ring = local_of(kept)
                if clipped_local is not None:
                    local, ring = clipped_local, clipped_ring
        levels.append(dict(y=round(y - bottom, 4), thickness=round(SLAB, 4),
                           pieces=[[[round(float(a), 3), round(float(b), 3)] for a, b in piece]
                                   for piece in local]))
        overlap = ring if overlap is None else overlap.intersection(ring)
        y += PITCH

    # UP TO THE REAL ROOF. Wall sections stop where the export's walls open --
    # fbx_9_-10581_2338_11079 stopped at Y 160 while its roofs reach 372 -- but
    # the building's slice continues. Keep flooring it while it is a floor.
    extended = 0
    below = world_of(levels[-1]["pieces"]) if levels else None
    while len(my_roofs):
        world = level_slice(y)
        if world is None:
            break
        # Inside the floor beneath it: the roof faces within the padded region
        # include a TALLER NEIGHBOUR's edge, and without this the control
        # building fbx_4_-1164_1279_-9107 grew two storeys above its own roof.
        if below is not None:
            parts = polygons(world.intersection(below.buffer(CONTAIN_TOLERANCE), grid_size=0.01))
            world = unary_union(parts) if parts else None
            if world is None or world.area < MIN_FOOTPRINT:
                break
        rings, shape = local_of(world)
        if shape is None:
            break
        # Stop before a floor that would leave no room for the one core that
        # must run through EVERY level (a tapering top did, on 9_-17820_2326_7084).
        joint = shape if overlap is None else overlap.intersection(shape)
        if joint.is_empty or largest_core(joint) is None:
            break
        levels.append(dict(y=round(y - bottom, 4), thickness=round(SLAB, 4),
                           pieces=[[[round(float(a), 3), round(float(b), 3)] for a, b in piece]
                                   for piece in rings]))
        overlap = joint
        below = world
        extended += 1
        y += PITCH

    # TOP SLAB AT THE ROOF. On a fixed storey grid the last slab lands up to a
    # storey below the roof; the median building was 20.8 studs short. Find the
    # roof over most of the top floor and lift (or add) the top slab onto it.
    snapped = 0.0
    if levels and len(my_roofs):
        last_y = bottom + levels[-1]["y"]
        last_world = world_of(levels[-1]["pieces"])
        roof_y = main_roof(my_roofs, last_world, last_y + SLAB, last_y + SLAB + 2 * PITCH, reach)
        want = roof_y - SLAB
        prev_top = bottom + levels[-2]["y"] + SLAB if len(levels) >= 2 else None
        if want - (last_y + SLAB) >= MIN_CLEAR:
            top_world = slice_at(my_roofs, roof_y - 2.0, reach, LEVEL_SEAM)
            if top_world is not None:
                top_world = top_world.intersection(last_world)
            use = top_world if top_world is not None and top_world.area >= MIN_FOOTPRINT else last_world
            rings, shape = local_of(use)
            joint = shape if (shape is None or overlap is None) else overlap.intersection(shape)
            if shape is not None and not joint.is_empty and largest_core(joint) is not None:
                levels.append(dict(y=round(want - bottom, 4), thickness=round(SLAB, 4),
                                   pieces=[[[round(float(a), 3), round(float(b), 3)] for a, b in piece]
                                           for piece in rings]))
                overlap = overlap.intersection(shape) if overlap is not None else shape
                snapped = want - last_y
        elif want > last_y + 0.5 and (prev_top is None or want - prev_top >= MIN_CLEAR):
            snapped = want - last_y
            levels[-1]["y"] = round(want - bottom, 4)
    # --- repair two measured artifacts before the plan is emitted ----------
    # Both come from the export being non-watertight, and both are what makes a
    # building read as several different buildings stacked on each other.
    def plate_area(level):
        rings = [Polygon(piece).buffer(0) for piece in level["pieces"]]
        return unary_union(rings).area if rings else 0.0

    areas = [plate_area(level) for level in levels]
    repaired_pinch = 0
    # 1. A PINCH: one storey far smaller than BOTH its neighbours. Measured on
    #    fbx_13_-15642_1589_16325: 31,809 / 766 / 31,805 sq studs on consecutive
    #    floors. A building does not neck to 2% for one storey and come back --
    #    the section at that height is a hole in the scan. Take the floor below.
    for index in range(1, len(levels) - 1):
        neighbour = min(areas[index - 1], areas[index + 1])
        if neighbour > 0 and areas[index] < PINCH_SHARE * neighbour:
            levels[index]["pieces"] = [[list(point) for point in piece]
                                       for piece in levels[index - 1]["pieces"]]
            areas[index] = areas[index - 1]
            repaired_pinch += 1

    # 2. A TRAILING SLIVER: the top "storey" is a mast or an aerial, not a floor.
    #    fbx_9_-17978_3725_2279 ran 30 floors at 23,800 sq studs and then one at
    #    547. The crown handles whatever is up there; flooring it produces the
    #    thin stalks with plates on them that the map owner flagged.
    #    Compared against the building's WIDEST floor, not the one directly
    #    below: a stalk several storeys tall is a run of equally tiny plates, so
    #    each looked normal next to its neighbour and the first version of this
    #    trim missed all of them (26 live buildings, 49 floors, e.g. three 194 sq
    #    stud floors on top of a 4,164 sq stud building).
    trimmed_sliver = 0
    while len(levels) > 2 and areas[-1] < SLIVER_SHARE * max(areas[:-1]):
        levels.pop()
        areas.pop()
        trimmed_sliver += 1

    if len(levels) < 2:
        return None, f"only {len(levels)} usable storeys"
    if overlap is None or overlap.is_empty:
        return None, "bands share no common area for a core"

    core = largest_core(overlap)
    if core is None:
        return None, "no 4-stud core fits every level"
    # Keep the core to a plausible service size when there is room to spare.
    hx, hz = min(core[1], 30.0), min(core[2], 30.0)
    # A core found at EXACTLY the 4-stud minimum can round to 3.9999 when the
    # plan is emitted and fail "core thinner than 4 studs" -- 9_-17820_2326_7084
    # did, once the floors reached its tapering roof. A thousandth of a stud of
    # margin is far inside the overlap tolerance.
    hx, hz = max(hx, 2.001), max(hz, 2.001)
    ccx, ccz = core[3], core[4]

    grey = max(b["footprint"] for b in members)
    fbx = shaped[0][3].area
    # Guards against latching onto a fragment - a rooftop detail or a sliver -
    # and proposing it as the replacement for several real buildings.
    if fbx < MIN_FOOTPRINT:
        return None, f"footprint only {fbx:.0f} sq studs"
    if grey / fbx > MAX_OVERSIZE:
        return None, f"greys are {grey / fbx:.1f}x the section; likely a fragment"
    # SHRINK the core before giving up on the building. The share guard exists to
    # stop a silly core being proposed for a sliver, but rejecting outright threw
    # away real, small buildings: on the first Cerulean-sector run 6 of 10 skips
    # were this one guard. The core only has to be >= 4 studs a side, so scale it
    # down to fit the plate and only reject when even the minimum will not.
    if (4 * hx * hz) / fbx > MAX_CORE_SHARE:
        budget = MAX_CORE_SHARE * fbx / 4.0          # target hx*hz
        scale = (budget / (hx * hz)) ** 0.5
        hx, hz = max(2.0, hx * scale), max(2.0, hz * scale)
        # EPSILON, and it is load-bearing. The scale above is derived to land the
        # core EXACTLY on MAX_CORE_SHARE, so re-testing it with a bare `>` is
        # decided by float rounding rather than by geometry: measured over the
        # whole-map sweep, 166 groups (228 greys) were rejected here at a share
        # of 0.600000000000001. The guard's real job is to catch the case where
        # the max(2.0, ...) clamp stopped the shrink, so only that should fail.
        if (4 * hx * hz) / fbx > MAX_CORE_SHARE + 1e-9:
            return None, "core would fill the footprint; even a 4-stud core does not fit"
        core_shrunk = True
    else:
        core_shrunk = False
    return dict(
        id=f"fbx_{key}",
        origin=dict(x=round(ox, 4), y=round(bottom, 4), z=round(oz, 4), yaw=round(yaw, 6)),
        levels=levels,
        core=dict(minX=round(ccx - hx, 4), minZ=round(ccz - hz, 4),
                  maxX=round(ccx + hx, 4), maxZ=round(ccz + hz, 4)),
        sourceInfo=dict(
            origin="world_triangles.npz horizontal sections",
            sourceKey=key,
            planBottom=round(bottom, 3),
            fbxBottom=round(fbx_bottom, 3),
            fbxTop=round(top, 3),
            # How far the lowest band was extruded below the FBX to reach the
            # live neighbourhood base. Non-zero is normal and intended; it is
            # what stops the building floating. Large values are worth a look.
            baseExtension=round(base_extension, 3),
            greyBase=round(lowest, 3),
            greyTop=round(highest, 3),
            bandCount=len(shaped),
            # Studs of rooftop clutter cut off the top (signs/plant, not setbacks).
            roofClutterTrimmed=round(trimmed, 2),
            # Studs cut off the top because they were crown, not storeys.
            crownTrimmed=round(crown_trimmed, 2),
            # Floors whose plate came from their own height rather than a band.
            exactLevels=exact,
            roofLevels=roofed,
            extendedLevels=extended,
            topSnapped=round(snapped, 2),
            coreShrunkToFit=core_shrunk,
            # Rings that needed a coarser tolerance to triangulate, and rings that
            # could not be built at any tolerance (those fall back to the band).
            simplifyEscalated=RING_STATS["escalated"],
            ringsDropped=RING_STATS["dropped"],
            replaces=sorted(b["name"] for b in members),
            measuredMembers=sum(1 for b in members if b.get("measured")),
            # Material-area ratio when live_extents.csv is present, bbox ratio
            # otherwise. NOT an extent comparison -- see the handoff doc.
            greyOversizeFactor=round(grey / fbx, 3) if fbx else None,
        ),
    ), None


def validate(plan):
    """The checks SourceSliceBuilder.compile performs, run before staging."""
    problems = []
    levels = plan["levels"]
    if not 2 <= len(levels) <= 200:
        problems.append(f"level count {len(levels)} outside 2..200")
    core = plan["core"]
    region = Polygon([(core["minX"], core["minZ"]), (core["maxX"], core["minZ"]),
                      (core["maxX"], core["maxZ"]), (core["minX"], core["maxZ"])])
    if core["maxX"] - core["minX"] < 4 or core["maxZ"] - core["minZ"] < 4:
        problems.append("core thinner than 4 studs")
    previous = None
    for index, level in enumerate(levels):
        union = None
        for piece in level["pieces"]:
            ring = Polygon(piece)
            if not ring.is_valid:
                problems.append(f"level {index} piece is not a simple polygon")
                continue
            if union is not None and union.intersection(ring).area > 0.002:
                problems.append(f"level {index} pieces overlap")
            union = ring if union is None else union.union(ring)
        if union is not None and not union.buffer(1e-6).contains(region):
            problems.append(f"level {index} does not contain the core")
        if previous is not None:
            clear = level["y"] - previous["y"] - previous["thickness"]
            if clear < MIN_CLEAR - 1e-5:
                problems.append(f"level {index} leaves {clear:.3f} clear (min {MIN_CLEAR:.3f})")
        previous = level
    return problems


def deduplicate(plans, tolerance=6.0):
    """One physical building can be found at several survey heights.

    Those runs produce near-identical plans that claim overlapping grey models;
    staging both would double-build it and leave two cores. Keep the richest plan
    per origin, union the members, then make grey ownership exclusive.
    """
    kept = []
    for plan in sorted(plans, key=lambda p: (-len(p["levels"]), p["id"])):
        ox, oz = plan["origin"]["x"], plan["origin"]["z"]
        twin = next((k for k in kept
                     if abs(k["origin"]["x"] - ox) <= tolerance
                     and abs(k["origin"]["z"] - oz) <= tolerance
                     and abs(k["origin"]["y"] - plan["origin"]["y"]) <= tolerance), None)
        if twin is None:
            kept.append(plan)
            continue
        merged = sorted(set(twin["sourceInfo"]["replaces"]) | set(plan["sourceInfo"]["replaces"]))
        twin["sourceInfo"]["replaces"] = merged
        twin["sourceInfo"].setdefault("mergedFrom", []).append(plan["id"])

    # A grey belongs to exactly one plan: the one with the most levels.
    owner = {}
    for plan in sorted(kept, key=lambda p: (-len(p["levels"]), p["id"])):
        mine = []
        for name in plan["sourceInfo"]["replaces"]:
            if name not in owner:
                owner[name] = plan["id"]
                mine.append(name)
        plan["sourceInfo"]["replaces"] = mine
    return [p for p in kept if p["sourceInfo"]["replaces"]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--key", help="only this ShibuyaSourceKey")
    parser.add_argument("--limit", type=int, default=12)
    parser.add_argument("--min-members", type=int, default=3)
    parser.add_argument("--from-survey", action="store_true",
                        help="group by FBX polygon ownership (fill_survey.json) rather than "
                             "by ShibuyaSourceKey; keys can split one physical building")
    parser.add_argument("--near", nargs=3, type=float, metavar=("X", "Z", "RADIUS"),
                        help="only groups whose mean centre lies within RADIUS studs of (X,Z); "
                             "use to do one contiguous sector at a time")
    parser.add_argument("--exclude", nargs=3, type=float, action="append",
                        metavar=("X", "Z", "RADIUS"),
                        help="drop any group with a member inside this circle; repeatable. "
                             "PROTECTED zones are always applied on top of these")
    parser.add_argument("--box", nargs=4, type=float, metavar=("X0", "Z0", "X1", "Z1"),
                        help="only groups whose mean centre lies in this world-axis box, "
                             "half-open on the max edges. Unlike --near, boxes TILE: a grid of "
                             "them partitions the map so a sweep plans every group exactly once "
                             "and two tiles can never both claim one building")
    parser.add_argument("--skip-names", metavar="FILE",
                        help="file of BuildingSmooth_* names, one per line, that are already "
                             "replaced by a live BuildingSourceSlice. They are dropped before "
                             "grouping, so the sweep never re-plans ground that is already done")
    parser.add_argument("--out", default=str(DATA / "plans"))
    args = parser.parse_args()

    triangles, live = load()
    if args.skip_names:
        done = {n.strip() for n in Path(args.skip_names).read_text().splitlines() if n.strip()}
        before = len(live)
        live = [b for b in live if b["name"] not in done]
        print(f"  --skip-names: {before - len(live)} greys already replaced, {len(live)} left")
    if args.from_survey:
        survey = DATA / "fill_survey.json"
        if not survey.exists():
            print("run tools/source_slice_fill_survey.py first")
            return
        by_name = {b["name"]: b for b in live}
        candidates = {}
        for row in json.loads(survey.read_text())["multiOwner"]:
            members = [by_name[n] for n in row["members"] if n in by_name]
            if len(members) >= args.min_members:
                candidates[f"poly_{row['y']:.0f}_{len(candidates)}"] = members
    else:
        candidates = groups(live, args.min_members)
    if args.near:
        # Spatial selection, so a whole neighbourhood can be replaced and reviewed
        # together instead of scattered seeds across the map.
        nx, nz, radius = args.near
        chosen = {}
        for k, v in candidates.items():
            cx = float(np.mean([b["cf"][0] for b in v]))
            cz = float(np.mean([b["cf"][2] for b in v]))
            if ((cx - nx) ** 2 + (cz - nz) ** 2) ** 0.5 <= radius:
                chosen[k] = v
        candidates = chosen
        print(f"  --near {nx:.0f},{nz:.0f} r={radius:.0f}: {len(candidates)} groups in the sector")

    if args.box:
        # Half-open on the max edges so a grid of boxes partitions the plane: a
        # group's centre lands in exactly one tile, which is what makes a
        # parallel sweep free of duplicate work and of two tiles claiming the
        # same greys (the failure --near has to be filtered for afterwards).
        bx0, bz0, bx1, bz1 = args.box
        chosen = {}
        for k, v in candidates.items():
            cx = float(np.mean([b["cf"][0] for b in v]))
            cz = float(np.mean([b["cf"][2] for b in v]))
            if bx0 <= cx < bx1 and bz0 <= cz < bz1:
                chosen[k] = v
        candidates = chosen
        print(f"  --box [{bx0:.0f},{bz0:.0f} .. {bx1:.0f},{bz1:.0f}): "
              f"{len(candidates)} groups in the tile")

    zones = [tuple(z) + (f"--exclude {z[0]:.0f},{z[1]:.0f}",) for z in (args.exclude or [])]
    zones += list(PROTECTED)
    if zones:
        kept, blocked = {}, {}
        for k, v in candidates.items():
            hit = None
            for zx, zz, zr, label in zones:
                if any(((b["cf"][0] - zx) ** 2 + (b["cf"][2] - zz) ** 2) ** 0.5 <= zr for b in v):
                    hit = label
                    break
            if hit:
                blocked[k] = hit
            else:
                kept[k] = v
        for k, label in blocked.items():
            print(f"  FENCED {k}: inside {label}")
        candidates = kept

    if args.key:
        candidates = {k: v for k, v in candidates.items() if k == args.key}
        if not candidates:
            print(f"no group for key {args.key}")
            return
    ordered = sorted(candidates.items(), key=lambda kv: -len(kv[1]))[:args.limit]
    print(f"{len(candidates)} groups with >= {args.min_members} members; "
          f"planning {len(ordered)}\n")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    built, bad = [], 0
    for key, members in ordered:
        cx = float(np.mean([b["cf"][0] for b in members]))
        cz = float(np.mean([b["cf"][2] for b in members]))
        # Measured world-axis rectangles, so the slicer can ask "which section
        # is this building" by overlap instead of by a centre point that may sit
        # in a courtyard.
        region = unary_union([box(*b["rect"]) for b in members if b.get("rect")])
        plan, reason = build_plan(key, members, Slicer(triangles, cx, cz, region=region))
        if plan is None:
            bad += 1
            print(f"  SKIP {key} ({len(members)} greys): {reason}")
            continue
        problems = validate(plan)
        if problems:
            bad += 1
            print(f"  BAD  {key}: {problems[0]}")
            continue
        built.append(plan)

    final = deduplicate(built)
    print(f"\n{len(built)} valid, {len(built) - len(final)} folded into duplicates, {bad} rejected")
    for plan in sorted(final, key=lambda p: p["id"]):
        info = plan["sourceInfo"]
        vertices = max(len(p) for lv in plan["levels"] for p in lv["pieces"])
        (out_dir / f"{plan['id']}.json").write_text(json.dumps(plan, indent=1))
        print(f"  {plan['id']}: {len(plan['levels'])} levels, {info['bandCount']} bands, "
              f"<= {vertices} verts, Y {info['fbxBottom']:.1f}-{info['fbxTop']:.1f}, "
              f"greys={len(info['replaces'])}, oversize={info['greyOversizeFactor']}")
    claimed = [n for p in final for n in p["sourceInfo"]["replaces"]]
    assert len(claimed) == len(set(claimed)), "a grey is still claimed twice"
    print(f"\n{len(final)} plans -> {out_dir}; {len(claimed)} greys claimed, each exactly once")


if __name__ == "__main__":
    main()
