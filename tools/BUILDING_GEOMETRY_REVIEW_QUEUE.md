# Building geometry review queue

October 17, 2026. Owner reports that some generated building models include disconnected geometry from another building and create double overlaps. Do not treat every piece in a source model as belonging to one building. Review source ownership and neighboring footprints before rebuilding; do not fill a combined bounding box across separate buildings.

## Owner-selected example

- ID: `fbx_4_-9770_4222_-4948`.
- Live model: `Workspace.Buildings.BuildingSourceSlice_fbx_4_-9770_4222_-4948`.
- Generated floors: 42. This is outside the ordinary ground-facade rollout's 15-floor limit.
- Recorded approximate bounds center: (-984.78, 436.64, -505.67); size: (549.94, 761.36, 414.34) studs. Bounds are an identification aid, not an approved replacement footprint.
- Owner specifically identifies a disconnected piece belonging to another building. This report is recorded; the precise components and ownership have not yet been independently verified.
- Native reference and recorded bounds: `ServerStorage.BuildingGeometryReviewTargets.fbx_4_-9770_4222_-4948`.

Future repair should inspect connected components and source plans floor by floor, compare adjacent building ownership, preserve exact original geometry, and regenerate only reviewed ownership footprints. Do not recreate buildings the owner has deleted, and retain current manual moves. No geometry repair has been performed on this target.

The two separately authorized rectangular replacements remain listed in `FACADE_BOX_REPAIR_HANDOFF.md`; this new report does not authorize replacing this tall building with a bounding-box mass.
