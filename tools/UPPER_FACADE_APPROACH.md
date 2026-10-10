# Upper-floor facade approach — planning after the ground trial

No upper-floor facade rollout is part of the current edit. First review the three-building ground trial documented in `FACADE_FLAT_TRIAL_HANDOFF.md`.

## Building identity before random floor details

Choose one coherent upper-floor family per ordinary building, seeded from its SourceSliceId. Carry its wall palette, frame material and window rhythm around the perimeter. Ground tenants can differ without making each upper floor a different architectural style. Preserve real source polygons, stepped heights, shared/internal edges, cores, floor slabs and crown geometry.

Initial families should include concrete office bands, tile-faced apartments, modest stucco residences, brick mixed-use buildings, and metal/glass commercial buildings. Family geometry needs meaningful variants: punched windows, paired windows, ribbon bands, deep reveals, privacy strips, restrained louvers and blank service panels. Use at least 15 physical arrangements across these families; name/sign randomness is additional variation. Balcony styles require verified clearance and a separate performance/geometry budget.

Street-facing commercial elevations can carry display glazing or occasional second-floor tenant signs. Neighbor gaps receive blank fire/service walls or limited high windows. Bedrooms and residences need smaller or frosted openings. A shallow floor slab must not automatically become a full glass curtain wall. Tall atrium glazing needs an explicitly verified slab-free void, rather than masking solid floors with glass.

## Logical panes and rendering cost

Architectural mullions define logical damage panes. Keep visible windows moderately sized; avoid one giant stretched glass sheet per building. Each window opening should have a stable building/floor/run/bay/pane identifier, aligned across client visuals and sparse server damage. Normal opaque structure remains the existing destruction target. Added facade trim is removable decoration; never duplicate an entire second structural shell.

Close range renders actual frames and individually addressable panes. Medium range can merge coplanar frame geometry while preserving the same opaque/glazed layout, tint and silhouette. Far range should simplify that same family; it must not switch from colored solid blocks to an unrelated glass shell as the player approaches. Establish consistent appearance before enabling far proxies. State 4 damage must remain a hole at every representation, and state 2 cracks can be omitted only beyond a documented visual threshold.

Build client visuals within existing budgets, prioritizing camera distance and visible-facing elevations. Keep authoritative server state sparse; no per-pane server heartbeat or city-wide shard physics. Particle bursts remain local and bounded. Pool reusable client geometry and test fast camera movement for reconstruction hitches; do not introduce generator streaming as a shortcut.

## Small next trial

After the ground trial is approved, add upper facades to these same three buildings first. Compare family appearance in Edit/Play and near/medium/far camera distances. Measure client part count, glass state consistency, creation time and burst cost before raising the eligible-building limit. Include plain neighboring walls, a narrow alley, a stepped building and mixed ground tenants in the comparison.

Mass deployment needs an explicit ordinary-building allow-list, repeatable placement manifest, archived previous owned facade children and a rollback path. Landmarks stay authored separately. Terrain/road/interior generators remain independent.
