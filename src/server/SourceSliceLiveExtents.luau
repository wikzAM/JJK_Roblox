--!nonstrict
-- Live dump of REAL per-building footprint geometry, so fill_survey.json can be
-- rebuilt on measured extents instead of pivot-oriented Model:GetBoundingBox().
--
-- Why this exists: tools/source_slices/live_buildings.json stores only each
-- model's `cf`/`size` from GetBoundingBox. That is pivot-oriented -- these models'
-- pivots are not upright (BuildingSmooth_16_7714_2072_-5958 has RightVector
-- 0.000, 0.907, 0.420) -- so `size.X * size.Z` is not a horizontal area at all,
-- and the survey's `fill` metric built on it is retracted. It cannot be repaired
-- offline; the real numbers only exist in the live DataModel.
--
-- Emits two quantities per building, which are NOT interchangeable:
--   ax, az   world-space axis-aligned EXTENT of real part geometry (wedge-aware)
--   fa       material FOOTPRINT AREA of the widest storey (sum of SlabFootprintArea)
-- Extent cannot detect a footprint that is a bounding box around a yawed outline;
-- area can. Use `fa` for any "is grey oversized" question. See the handoff doc.
--
-- Output: CSV in ServerStorage StringValues `SourceSliceExtents_1..n` (<=180 KB
-- each, so they stay readable), plus `SourceSliceExtents_Manifest` with the count.
-- Columns: name,ax,az,ay,minX,minZ,cx,cz,fa,storeys,parts,estimated
--
-- Read-only: creates nothing in Workspace and mutates no building.
--
-- Command Bar (Edit):
--   local s=game.ServerScriptService.Server
--   local f=Instance.new("Folder"); f.Name="SourceSliceFresh"; f.Parent=s
--   s.PartExtents:Clone().Parent=f
--   local m=s.SourceSliceLiveExtents:Clone(); m.Parent=f
--   local ok,r=pcall(function() return require(m).Dump() end)
--   f:Destroy(); if not ok then error(r) end; return r
local LiveExtents = {}

local Storage = game:GetService("ServerStorage")
local Collection = game:GetService("CollectionService")
local PartExtents = require(script.Parent.PartExtents)

local PREFIX = "SourceSliceExtents_"
local CHUNK_BYTES = 180 * 1024

local function isSlab(part)
	return part:IsA("BasePart")
		and (part:GetAttribute("PolygonSlab") == true or part.Name == "Slab")
		and not Collection:HasTag(part, "BuildingCore")
end

local function clear()
	for _, child in Storage:GetChildren() do
		if child.Name:sub(1, #PREFIX) == PREFIX then child:Destroy() end
	end
end

-- namePattern defaults to every destructible building model.
function LiveExtents.Dump(namePattern)
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	local pattern = namePattern or "^Building"
	local folder = assert(workspace:FindFirstChild("Buildings"), "Workspace.Buildings is missing")
	clear()

	local lines = {"name,ax,az,ay,minX,minZ,cx,cz,fa,storeys,parts,estimated"}
	local scanned, skipped = 0, 0
	for index, model in folder:GetChildren() do
		if not model:IsA("Model") or not model.Name:match(pattern) then skipped += 1; continue end
		local box = PartExtents.Footprint(model)
		if box then
			local storeys = PartExtents.Storeys(model, isSlab)
			local widest, estimated = nil, 0
			for _, row in storeys do
				estimated += row.estimated
				if not widest or row.area > widest.area then widest = row end
			end
			table.insert(lines, string.format(
				"%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d",
				model.Name, box.sizeX, box.sizeZ, box.sizeY, box.minX, box.minZ,
				(box.minX + box.maxX) / 2, (box.minZ + box.maxZ) / 2,
				widest and widest.area or 0, #storeys, box.parts, estimated))
			scanned += 1
		else
			skipped += 1
		end
		if index % 25 == 0 then task.wait() end
	end

	-- Chunked so each StringValue stays small enough to read back in one piece.
	local chunks, current, size = {}, {}, 0
	for _, line in lines do
		if size + #line + 1 > CHUNK_BYTES and #current > 0 then
			table.insert(chunks, table.concat(current, "\n"))
			current, size = {}, 0
		end
		table.insert(current, line)
		size += #line + 1
	end
	if #current > 0 then table.insert(chunks, table.concat(current, "\n")) end

	for i, text in chunks do
		local value = Instance.new("StringValue")
		value.Name = PREFIX .. i
		value.Value = text
		value.Parent = Storage
	end
	local manifest = Instance.new("StringValue")
	manifest.Name = PREFIX .. "Manifest"
	manifest.Value = string.format("chunks=%d buildings=%d skipped=%d", #chunks, scanned, skipped)
	manifest.Parent = Storage

	print("SOURCE_SLICE_LIVE_EXTENTS", manifest.Value)
	return {chunks = #chunks, buildings = scanned, skipped = skipped, prefix = PREFIX}
end

function LiveExtents.Clear()
	clear()
	return true
end

return LiveExtents
