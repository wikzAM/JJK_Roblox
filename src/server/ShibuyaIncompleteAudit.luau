--!nonstrict
-- Read-only screening of severe legacy snippets, NOT a removal decision.
-- Preview(workspace.Buildings) returns exact candidate objects for visual review.
-- No source masks are repaired, no geometry is inferred, no instances are changed.
-- "Complete floor" below means one four-connected occupied body only. It does
-- not certify a real building outline, absence of courtyards, or usable access.
local Audit = {}
local Http = game:GetService("HttpService")
local THRESHOLDS = {
	MinPlannedFloors = 3,
	MaxEnvelopeFraction = 0.25,
	MaxLargestBodyArea = 150,
	MinSourceHeightForTinyBody = 60,
}

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function reject(reason)
	error(reason, 0)
end

local function readGrid(model)
	local raw = model:GetAttribute("InteriorGrid")
	if type(raw) ~= "string" then reject("missing saved grid") end
	local ok, grid = pcall(Http.JSONDecode, Http, raw)
	if not ok or type(grid) ~= "table" then reject("invalid saved grid JSON") end
	local size = model:GetAttribute("InteriorBBoxSize")
	if typeof(size) ~= "Vector3" or not finite(size.X) or not finite(size.Y)
		or not finite(size.Z) or math.min(size.X, size.Y, size.Z) <= 0 then
		reject("invalid source envelope dimensions")
	end
	for _, key in {"cell", "nx", "nz", "floors", "minX", "minZ"} do
		if not finite(grid[key]) then reject("invalid grid " .. key) end
	end
	if grid.cell <= 0 or grid.nx < 1 or grid.nz < 1 or grid.nx % 1 ~= 0
		or grid.nz % 1 ~= 0 or grid.nx * grid.nz > 16384 then
		reject("invalid grid dimensions")
	end
	if grid.floors < 1 or grid.floors >= 200 or grid.floors % 1 ~= 0
		or type(grid.occ) ~= "table" then reject("invalid planned floors") end
	if math.abs(grid.minX + size.X / 2) > 0.05 or math.abs(grid.minZ + size.Z / 2) > 0.05 then
		reject("grid origin does not match source envelope")
	end
	-- A truncated grid must not masquerade as a mostly empty large envelope.
	if grid.nx * grid.cell < size.X - 0.05 or grid.nz * grid.cell < size.Z - 0.05
		or (grid.nx - 1) * grid.cell >= size.X or (grid.nz - 1) * grid.cell >= size.Z then
		reject("grid extent does not match source envelope")
	end
	local generated = model:GetAttribute("GeneratedFloors")
	if generated ~= nil and generated ~= grid.floors then reject("saved and generated floor counts disagree") end
	for index in grid.occ do
		if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > grid.floors then
			reject("unexpected saved floor mask")
		end
	end
	return grid, size
end

local function cellAreas(grid, size)
	local areas = table.create(grid.nx * grid.nz)
	for i = 1, grid.nx do
		local x0 = grid.minX + (i - 1) * grid.cell
		local width = math.min(x0 + grid.cell, size.X / 2) - math.max(x0, -size.X / 2)
		for j = 1, grid.nz do
			local z0 = grid.minZ + (j - 1) * grid.cell
			local depth = math.min(z0 + grid.cell, size.Z / 2) - math.max(z0, -size.Z / 2)
			if width <= 0 or depth <= 0 then reject("grid cell lies outside source envelope") end
			areas[(i - 1) * grid.nz + j] = width * depth
		end
	end
	return areas
end

local function measureFloor(mask, grid, areas, envelope)
	if type(mask) ~= "string" or #mask ~= grid.nx * grid.nz or mask:find("[^01]") then
		reject("missing or invalid floor mask")
	end
	local occupiedArea, occupiedCells, components, largestBodyArea = 0, 0, 0, 0
	local visited = {}
	for start = 1, #mask do
		if mask:byte(start) ~= 49 or visited[start] then continue end
		components += 1
		local queue, head, bodyArea = {start}, 1, 0
		visited[start] = true
		while head <= #queue do
			local index = queue[head]
			head += 1
			bodyArea += areas[index]
			occupiedCells += 1
			local i, j = math.floor((index - 1) / grid.nz) + 1, (index - 1) % grid.nz + 1
			for _, neighbor in {
				i > 1 and index - grid.nz or 0, i < grid.nx and index + grid.nz or 0,
				j > 1 and index - 1 or 0, j < grid.nz and index + 1 or 0,
			} do
				if neighbor > 0 and not visited[neighbor] and mask:byte(neighbor) == 49 then
					visited[neighbor] = true
					table.insert(queue, neighbor)
				end
			end
		end
		occupiedArea += bodyArea
		largestBodyArea = math.max(largestBodyArea, bodyArea)
	end
	return {
		occupiedArea = occupiedArea, occupiedCells = occupiedCells,
		sourceEnvelopeArea = envelope, occupiedFraction = occupiedArea / envelope,
		componentCount = components, largestBodyArea = largestBodyArea,
		largestBodyFraction = largestBodyArea / envelope,
		singleConnectedBody = components == 1,
	}
end

local function measure(model, grid, size)
	local envelope = size.X * size.Z
	local areas, cached, floors = cellAreas(grid, size), {}, {}
	local maxOccupied, maxBody, largestComplete, emptyFloors, disconnectedFloors = 0, 0, 0, 0, 0
	for k = 1, grid.floors do
		local mask = grid.occ[k]
		-- Invalid masks reject the entire model; missing data is not zero area.
		local measured = type(mask) == "string" and cached[mask] or nil
		if not measured then
			measured = measureFloor(mask, grid, areas, envelope)
			cached[mask] = measured
		end
		local floor = table.clone(measured)
		floor.floor = k
		floors[k] = floor
		maxOccupied = math.max(maxOccupied, floor.occupiedArea)
		maxBody = math.max(maxBody, floor.largestBodyArea)
		if floor.singleConnectedBody then largestComplete = math.max(largestComplete, floor.occupiedArea) end
		if floor.componentCount == 0 then emptyFloors += 1 end
		if floor.componentCount > 1 then disconnectedFloors += 1 end
	end
	local metrics = {
		plannedFloors = grid.floors, sourceHeight = size.Y, sourceEnvelopeArea = envelope,
		sourceWidth = size.X, sourceDepth = size.Z, cellSize = grid.cell,
		maxOccupiedArea = maxOccupied, maxOccupiedFraction = maxOccupied / envelope,
		maxLargestBodyArea = maxBody, maxLargestBodyFraction = maxBody / envelope,
		largestCompleteFloorArea = largestComplete, largestCompleteFloorFraction = largestComplete / envelope,
		emptyFloors = emptyFloors, disconnectedFloors = disconnectedFloors, floors = floors,
	}
	local reasons = {}
	if maxOccupied <= envelope * THRESHOLDS.MaxEnvelopeFraction
		and largestComplete <= envelope * THRESHOLDS.MaxEnvelopeFraction then
		table.insert(reasons, "Every floor occupies at most 25% of the source envelope")
	end
	if maxBody < THRESHOLDS.MaxLargestBodyArea and size.Y >= THRESHOLDS.MinSourceHeightForTinyBody then
		table.insert(reasons, "No connected floor body reaches 150 square studs in a source at least 60 studs tall")
	end
	return {model = model, name = model.Name, key = model:GetAttribute("ShibuyaSourceKey"), metrics = metrics, reasons = reasons}
end

function Audit.Preview(folder)
	folder = folder or workspace:FindFirstChild("Buildings")
	assert(typeof(folder) == "Instance", "Pass the folder containing legacy building models")
	local summary = {scanned = 0, autoModels = 0, analyzed = 0, candidates = 0,
		notFlagged = 0, skipped = 0, lowRise = 0, protected = 0, invalid = 0,
		rejected = {}, candidateReasons = {}}
	local report = {summary = summary, candidates = {}, rows = {}, skippedModels = {},
		thresholds = table.clone(THRESHOLDS), readOnly = true}
	local function skip(model, reason, category)
		summary.skipped += 1
		summary.rejected[reason] = (summary.rejected[reason] or 0) + 1
		if category then summary[category] += 1 end
		table.insert(report.skippedModels, {model = model, name = model.Name, reason = reason})
	end
	for _, model in folder:GetChildren() do
		summary.scanned += 1
		if not model:IsA("Model") or not model.Name:match("^BuildingAuto_") then
			skip(model, "not a legacy auto model", "protected")
			continue
		end
		summary.autoModels += 1
		if model:GetAttribute("SmoothMassing") or model:GetAttribute("ManualShellVersion")
			or model:GetAttribute("ShibuyaBoxKey") or model:GetAttribute("ManualSurvey") then
			skip(model, "protected authored or replaced model", "protected")
			continue
		end
		local key = model:GetAttribute("ShibuyaSourceKey")
		if type(key) ~= "string" or key == "" then
			skip(model, "missing legacy source identity", "invalid")
			continue
		end
		local ok, grid, size = pcall(readGrid, model)
		if not ok then
			skip(model, tostring(grid), "invalid")
		elseif grid.floors < THRESHOLDS.MinPlannedFloors then
			skip(model, "fewer than three planned floors", "lowRise")
		else
			local measured, row = pcall(measure, model, grid, size)
			if not measured then
				skip(model, tostring(row), "invalid")
			else
				summary.analyzed += 1
				table.insert(report.rows, row)
				if #row.reasons == 0 then
					summary.notFlagged += 1
					summary.rejected["severe thresholds not met"] = (summary.rejected["severe thresholds not met"] or 0) + 1
				else
					table.insert(report.candidates, row)
					for _, reason in row.reasons do
						summary.candidateReasons[reason] = (summary.candidateReasons[reason] or 0) + 1
					end
				end
			end
		end
		if summary.autoModels % 25 == 0 then task.wait() end
	end
	table.sort(report.candidates, function(a, b)
		if a.metrics.maxLargestBodyFraction ~= b.metrics.maxLargestBodyFraction then
			return a.metrics.maxLargestBodyFraction < b.metrics.maxLargestBodyFraction
		end
		return a.name < b.name
	end)
	summary.candidates = #report.candidates
	print(string.format("INCOMPLETE AUDIT: %d legacy auto models; %d assessed, %d severe candidates for visual review, %d below thresholds, %d skipped. Nothing changed.",
		summary.autoModels, summary.analyzed, summary.candidates, summary.notFlagged, summary.skipped))
	print("INCOMPLETE AUDIT STATS", Http:JSONEncode(summary))
	return report
end

return Audit
