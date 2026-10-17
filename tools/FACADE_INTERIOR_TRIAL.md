# Ground facade inlet trial - October 16, 2026

The owner requested small walled inlets before further city expansion. No computer control is authorized while the owner uses the browser. Use Studio MCP only.

## Live changes verified in TestJJK

39 shallow static window inlets (351 parts) are visible in Edit. Each cell tapers inward, clips rear bounds against nearby facade bisectors, and uses wedge-filled trapezoidal floors/ceilings. Furniture was omitted. Nine interior pieces belong directly to each pane as glass overlays; the exterior facade remains outside the floor outline. GlassInteriorStaticVersion prevents duplicate client rooms. Original flat backings remain saved but transparent; InteriorBeforeTransparency / InteriorBeforeFilmTransparency retain prior values. GroundFacadeInteriorTrial is an explicit Edit helper, never auto-run at server startup.

Five deeper garage cells add25 wall/parking-line parts, with depths48,48,24,48,36 studs. Only existing parking/loading openings were used. Checks require actual floor support, footprint containment, and no blocking core, source structure or other facade throughout the proposed volume. Existing floors remain the driveable surface. Two initial candidates were rejected when opposed facade geometry was included. No structure was carved. Car capacity depends on the actual vehicle size; wider/longer native voids can support multiple cars.

## Verification

- Native exact occupancy:25/25 tapered floor samples, including both wedge fills.
- Native exact intersection:376 added parts, zero intersections between separate cells.
- Cloned inlet glass states2,3,1,4:all9 pieces hide, restore and delete correctly.
- Every static inlet checked for overlap with original interior geometry before acceptance.
- Default Rojo build and whitespace checks passed.
- MCP screenshots GroundInletTrial and GarageInteriorTrial reviewed. Shop shows shallow tapered cells; garage shows meaningful depth. No native/browser input was sent.
- Full Play/performance verification remains pending. Prior Play startup was interrupted by a Team Create reconnect; do not claim a passing runtime test.

## Locations

Shop screenshot:Workspace.Buildings.BuildingSourceSlice_fbx_10_-14483_1320_-7605, around(-1433,70,-777). Garage screenshot:BuildingSourceSlice_fbx_10_-15601_849_-10951, around(-1592,71,-1070).

Six shallow trial models use IDs fbx_10_-13463_1146_-6580, fbx_10_-13951_1242_-7077, fbx_10_-14276_1291_-7380, fbx_10_-14468_1416_-4279, fbx_10_-14483_1320_-7605, fbx_10_-14605_1026_-11521. Six additional garage candidates were evaluated; inspect GarageInteriorTrial children for the accepted cells. They are the first six sorted existing parking candidates in the current partial city.

The optional client GroundFacadeInteriors module creates at most32 nearby cells (max3-stud depth, enter95/drop115studs, at most2 attempts/.3s) on explicit FacadeInteriorTrial buildings. It retains backing where structure blocks depth and removes a cell immediately when its pane shatters. Static trial panes are excluded from dynamic creation. Wider rollout remains paused for this review.

## Persistence and recovery

After reopening TestJJK, MCP confirmed1066 facade roots, both interior modules, six original trial flags, station archive and chunked registry. The 39 static inlets and five garages were applied afterwards. An explicit save-only request through documented AssetService.SavePlaceAsync({SaveWithoutPublish=true}) failed because Studio plugin context cannot call Game:SavePlace; a final manual Save to Roblox remains unconfirmed while computer control is prohibited. Team Create persistence is supported by actual reopen checks, not by that failed save call. Git contains scripts and replay helpers, not the complete live city geometry.

Use GroundFacadeRegistry.Read/Write for registry data. The coordinating pass reconciles actual roots and reports after adding trial pieces. The full2091-building eligibility target is not complete; earlier city checkpoint had1066 roots/988 revision9. Do not expand until inlet review is complete.
