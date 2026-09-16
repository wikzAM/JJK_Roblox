--!nonstrict
-- Safely separates legacy grid models that contain multiple independent,
-- vertically persistent floor bodies. Every substantial body must validate;
-- branching/merging bodies and incomplete sources remain untouched.
local Split = {}

local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local History = game:GetService("ChangeHistoryService")
local SLAB = 1.5 / 0.28
local DEFAULTS = {
	MinBodyFloors = 2,
	MaxBodies = 12,
	MaxTinyCells = 4,
	MaxTinyFraction = 0.05,
	MaxSources = 50,
}

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end

local function optionsWithDefaults(options)
	local configured = table.clone(DEFAULTS)
	for key, value in options or {} do
		assert(DEFAULTS[key] ~= nil, "Unknown split option: " .. tostring(key))
		configured[key] = value
	end
	for _, key in {"MinBodyFloors", "MaxBodies", "MaxTinyCells", "MaxSources"} do
		assert(type(configured[key]) == "number" and configured[key] >= 1 and configured[key] % 1 == 0,
			key .. " must be a positive integer")
	end
	assert(type(configured.MaxTinyFraction) == "number"
		and configured.MaxTinyFraction >= 0 and configured.MaxTinyFraction <= 0.1,
		"MaxTinyFraction must be between zero and 0.1")
	return configured
end

local function floorBottom(grid, floor)
	if floor <= 1 then return 0 end
	return SLAB + grid.ground + (floor - 2) * (grid.clearUpper + SLAB)
end

local function readGrid(model)
	local raw = model:GetAttribute("InteriorGrid")
	assert(type(raw) == "string", "missing saved grid")
	local grid = Http:JSONDecode(raw)
	local cf, size = model:GetAttribute("InteriorBBoxCFrame"), model:GetAttribute("InteriorBBoxSize")
	assert(typeof(cf) == "CFrame" and typeof(size) == "Vector3" and cf.UpVector.Y > 0.999999,
		"invalid source envelope")
	for _, key in {"cell", "nx", "nz", "floors", "minX", "minZ", "ground"} do
		assert(type(grid[key]) == "number", "invalid grid " .. key)
	end
	grid.clearUpper = grid.clearUpper or 3.5 / 0.28
	assert(grid.nx >= 1 and grid.nz >= 1 and grid.nx * grid.nz <= 16384
		and grid.floors >= 1 and grid.floors < 200 and type(grid.occ) == "table",
		"invalid grid dimensions")
	return grid, cf, size
end

local function floorComponents(mask, grid, floor, nodes, owner)
	assert(type(mask) == "string" and #mask == grid.nx * grid.nz and not mask:find("[^01]"),
		"invalid floor mask")
	local seen = {}
	owner[floor] = {}
	for start = 1, #mask do
		if seen[start] or mask:byte(start) ~= 49 then continue end
		local node = {id = #nodes + 1, floor = floor, cells = {}, cellSet = {}}
		local queue, head = {start}, 1
		seen[start] = true
		while head <= #queue do
			local index = queue[head]
			head += 1
			table.insert(node.cells, index)
			node.cellSet[index] = true
			owner[floor][index] = node.id
			local i = math.floor((index - 1) / grid.nz) + 1
			local j = (index - 1) % grid.nz + 1
			for _, nextIndex in {
				i > 1 and index - grid.nz or 0,
				i < grid.nx and index + grid.nz or 0,
				j > 1 and index - 1 or 0,
				j < grid.nz and index + 1 or 0,
			} do
				if nextIndex > 0 and not seen[nextIndex] and mask:byte(nextIndex) == 49 then
					seen[nextIndex] = true
					table.insert(queue, nextIndex)
				end
			end
		end
		nodes[node.id] = node
	end
end

local function extractBodies(grid)
	local nodes, owner = {}, {}
	for floor = 1, grid.floors do
		floorComponents(grid.occ[floor], grid, floor, nodes, owner)
	end
	local parent = {}
	for id = 1, #nodes do parent[id] = id end
	local function root(id)
		while parent[id] ~= id do
			parent[id] = parent[parent[id]]
			id = parent[id]
		end
		return id
	end
	local function union(a, b)
		a, b = root(a), root(b)
		if a ~= b then parent[b] = a end
	end
	for floor = 2, grid.floors do
		for index, id in owner[floor] do
			local below = owner[floor - 1][index]
			if below then union(id, below) end
		end
	end
	local bodies = {}
	for _, node in nodes do
		local id = root(node.id)
		local body = bodies[id] or {nodes = {}, floors = {}, maxCells = 0, totalCells = 0}
		bodies[id] = body
		table.insert(body.nodes, node)
		body.floors[node.floor] = body.floors[node.floor] or {}
		table.insert(body.floors[node.floor], node)
		body.maxCells = math.max(body.maxCells, #node.cells)
		body.totalCells += #node.cells
	end
	local result = {}
	for _, body in bodies do table.insert(result, body) end
	return result
end

-- Split the floor-component graph wherever one body forks or several merge.
-- Each returned segment is a one-component-per-floor vertical chain, so podium
-- and tower plates never overlap or disappear during one-to-many replacement.
local function extractSegments(grid)
	local nodes, owner = {}, {}
	for floor = 1, grid.floors do
		floorComponents(grid.occ[floor], grid, floor, nodes, owner)
	end
	local previous, following = {}, {}
	for id = 1, #nodes do previous[id], following[id] = {}, {} end
	local edges = {}
	for floor = 2, grid.floors do
		for index, id in owner[floor] do
			local below = owner[floor - 1][index]
			if not below then continue end
			local key = below .. ":" .. id
			if edges[key] then continue end
			edges[key] = true
			table.insert(following[below], id)
			table.insert(previous[id], below)
		end
	end
	local assigned, segments = {}, {}
	for _, start in nodes do
		local prior = previous[start.id]
		local begins = #prior ~= 1 or #following[prior[1]] ~= 1
		if not begins or assigned[start.id] then continue end
		local segment = {nodes = {}, floors = {}, maxCells = 0, totalCells = 0}
		local current = start
		while current and not assigned[current.id] do
			assigned[current.id] = true
			table.insert(segment.nodes, current)
			segment.floors[current.floor] = {current}
			segment.maxCells = math.max(segment.maxCells, #current.cells)
			segment.totalCells += #current.cells
			local nextIds = following[current.id]
			if #nextIds ~= 1 or #previous[nextIds[1]] ~= 1 then break end
			current = nodes[nextIds[1]]
		end
		table.insert(segments, segment)
	end
	for _, node in nodes do assert(assigned[node.id], "Unassigned floor component in segment graph") end
	return segments
end

local function bodyProxy(source, grid, sourceCF, sourceSize, body, bodyIndex, allowElevated)
	local first, last, minI, maxI, minJ, maxJ = math.huge, 0, math.huge, 0, math.huge, 0
	for floor, floorNodes in body.floors do
		if #floorNodes ~= 1 then return nil, "body branches or merges on floor " .. floor end
		first, last = math.min(first, floor), math.max(last, floor)
		for _, index in floorNodes[1].cells do
			local i = math.floor((index - 1) / grid.nz) + 1
			local j = (index - 1) % grid.nz + 1
			minI, maxI, minJ, maxJ = math.min(minI, i), math.max(maxI, i), math.min(minJ, j), math.max(maxJ, j)
		end
	end
	if first ~= 1 and not allowElevated then return nil, "substantial body does not begin on the ground floor" end
	for floor = first, last do
		if not body.floors[floor] then return nil, "body has an unsupported vertical gap" end
	end
	local nx, nz = maxI - minI + 1, maxJ - minJ + 1
	local masks = {}
	for floor = 1, last do
		if floor < first then continue end
		local bits = table.create(nx * nz, "0")
		for _, index in body.floors[floor][1].cells do
			local i = math.floor((index - 1) / grid.nz) + 1
			local j = (index - 1) % grid.nz + 1
			bits[(i - minI) * nz + (j - minJ) + 1] = "1"
		end
		masks[floor - first + 1] = table.concat(bits)
	end
	local x0 = grid.minX + (minI - 1) * grid.cell
	local z0 = grid.minZ + (minJ - 1) * grid.cell
	local x1 = math.min(grid.minX + maxI * grid.cell, sourceSize.X / 2)
	local z1 = math.min(grid.minZ + maxJ * grid.cell, sourceSize.Z / 2)
	local width, depth = x1 - x0, z1 - z0
	if width <= 0 or depth <= 0 then return nil, "body crop is empty" end
	local baseY = floorBottom(grid, first)
	local topY = math.min(sourceSize.Y, floorBottom(grid, last + 1) + SLAB)
	local height = topY - baseY
	local baseFrame = sourceCF * CFrame.new(0, -sourceSize.Y / 2, 0)
	local proxyCF = baseFrame * CFrame.new((x0 + x1) / 2, baseY + height / 2, (z0 + z1) / 2)
	local proxyGrid = {
		cell = grid.cell,
		nx = nx,
		nz = nz,
		minX = -width / 2,
		minZ = -depth / 2,
		floors = last - first + 1,
		ground = first == 1 and grid.ground or grid.clearUpper,
		clearUpper = grid.clearUpper,
		occ = masks,
		occTight = masks,
	}
	local proxy = Instance.new("Model")
	proxy.Name = string.format("BuildingAuto_%s_body%02d", source:GetAttribute("ShibuyaSourceKey"), bodyIndex)
	proxy:SetAttribute("ShibuyaSourceKey", source:GetAttribute("ShibuyaSourceKey") .. "_body" .. bodyIndex)
	proxy:SetAttribute("InteriorBBoxCFrame", proxyCF)
	proxy:SetAttribute("InteriorBBoxSize", Vector3.new(width, height, depth))
	proxy:SetAttribute("InteriorGrid", Http:JSONEncode(proxyGrid))
	return proxy
end

-- Low-level, read-only decomposition used by the residual-preserving pass.
-- Every original occupied cell belongs to exactly one returned segment.
function Split.DecomposeSegments(source)
	editOnly()
	assert(source and source:IsA("Model") and source.Name:match("^BuildingAuto_"),
		"Pass a legacy BuildingAuto model")
	local grid, sourceCF, sourceSize = readGrid(source)
	local segments = extractSegments(grid)
	local rows = {}
	for index, segment in segments do
		local proxy, reason = bodyProxy(source, grid, sourceCF, sourceSize, segment, index, true)
		table.insert(rows, {
			index = index,
			segment = segment,
			proxy = proxy,
			reason = reason,
			maxCells = segment.maxCells,
			totalCells = segment.totalCells,
		})
	end
	return {
		source = source,
		grid = grid,
		sourceCF = sourceCF,
		sourceSize = sourceSize,
		segments = rows,
	}
end

function Split.Preview(folder, options)
	editOnly()
	folder = folder or workspace:FindFirstChild("Buildings")
	assert(folder, "Workspace.Buildings is missing")
	local configured = optionsWithDefaults(options)
	local proxyFolder = Instance.new("Folder")
	proxyFolder.Name = "GridSplitPreview_" .. Http:GenerateGUID(false)
	proxyFolder.Parent = Storage
	local sourceRows, proxyRows = {}, {}
	local rejected = {}
	local function reject(reason)
		rejected[reason] = (rejected[reason] or 0) + 1
	end
	for _, source in folder:GetChildren() do
		if not source:IsA("Model") or not source.Name:match("^BuildingAuto_") then continue end
		local ok, grid, sourceCF, sourceSize = pcall(readGrid, source)
		if not ok then reject("invalid legacy grid"); continue end
		local extracted, bodies = pcall(extractBodies, grid)
		if not extracted then reject("invalid floor masks"); continue end
		local significant, tinyCells, allCells = {}, 0, 0
		for _, body in bodies do
			allCells += body.totalCells
			if body.maxCells <= configured.MaxTinyCells then tinyCells += body.totalCells
			else table.insert(significant, body) end
		end
		if #significant < 2 then reject("fewer than two substantial bodies"); continue end
		if #significant > configured.MaxBodies then reject("too many disconnected bodies"); continue end
		if tinyCells / math.max(1, allCells) > configured.MaxTinyFraction then
			reject("too much tiny disconnected debris"); continue
		end
		local row = {source = source, proxies = {}, expected = #significant}
		local valid = true
		for index, body in significant do
			local proxy, reason = bodyProxy(source, grid, sourceCF, sourceSize, body, index)
			if not proxy then reject(reason); valid = false; break end
			proxy.Parent = proxyFolder
			table.insert(row.proxies, proxy)
			proxyRows[proxy] = {sourceRow = row, bodyIndex = index}
		end
		if valid then table.insert(sourceRows, row)
		else for _, proxy in row.proxies do proxy:Destroy() end end
	end
	local gridReport = require(script.Parent.ShibuyaGridMassing).Preview(proxyFolder, {
		MinFloors = configured.MinBodyFloors,
		MinSupportFloors = configured.MinBodyFloors,
	})
	local acceptedByProxy = {}
	for _, plan in gridReport.plans do acceptedByProxy[plan.oldModel] = plan end
	local report = {plans = {}, sources = {}, rejected = rejected, gridRejected = gridReport.rejected, readOnly = true}
	for _, row in sourceRows do
		local sourcePlans, complete = {}, true
		for _, proxy in row.proxies do
			local plan = acceptedByProxy[proxy]
			if not plan then complete = false; break end
			local bodyIndex = proxyRows[proxy].bodyIndex
			plan.oldModel = row.source
			plan.key = row.source:GetAttribute("ShibuyaSourceKey") .. "_body" .. bodyIndex
			plan.splitBodyIndex = bodyIndex
			plan.splitBodyCount = row.expected
			table.insert(sourcePlans, plan)
		end
		if complete and #sourcePlans == row.expected then
			table.sort(sourcePlans, function(a, b) return a.splitBodyIndex < b.splitBodyIndex end)
			table.insert(report.sources, {oldModel = row.source, plans = sourcePlans, key = row.source:GetAttribute("ShibuyaSourceKey")})
			for _, plan in sourcePlans do table.insert(report.plans, plan) end
		else reject("one or more substantial bodies failed independent validation") end
	end
	proxyFolder:Destroy()
	table.sort(report.sources, function(a, b)
		local areaA, areaB = 0, 0
		for _, p in a.plans do areaA += p.area end
		for _, p in b.plans do areaB += p.area end
		if areaA ~= areaB then return areaA > areaB end
		return a.key < b.key
	end)
	print("GRID_SPLIT_PREVIEW", #report.sources, "legacy sources,", #report.plans,
		"independent smooth bodies; no geometry changed")
	return report
end

-- Branch-aware alternative: decomposes podium/tower forks and merges into
-- non-overlapping vertical segments. Every substantial segment must pass.
function Split.PreviewSegments(folder, options)
	editOnly()
	folder = folder or workspace:FindFirstChild("Buildings")
	assert(folder, "Workspace.Buildings is missing")
	local configured = optionsWithDefaults(options)
	local proxyFolder = Instance.new("Folder")
	proxyFolder.Name = "GridSegmentPreview_" .. Http:GenerateGUID(false)
	proxyFolder.Parent = Storage
	local sourceRows, proxyRows = {}, {}
	local rejected = {}
	local function reject(reason)
		rejected[reason] = (rejected[reason] or 0) + 1
	end
	for _, source in folder:GetChildren() do
		if not source:IsA("Model") or not source.Name:match("^BuildingAuto_") then continue end
		local ok, grid, sourceCF, sourceSize = pcall(readGrid, source)
		if not ok then reject("invalid legacy grid"); continue end
		local extracted, segments = pcall(extractSegments, grid)
		if not extracted then reject("invalid floor component graph"); continue end
		local significant, tinyCells, allCells = {}, 0, 0
		for _, segment in segments do
			allCells += segment.totalCells
			if segment.maxCells <= configured.MaxTinyCells then tinyCells += segment.totalCells
			else table.insert(significant, segment) end
		end
		if #significant < 2 then reject("fewer than two substantial vertical segments"); continue end
		if #significant > configured.MaxBodies then reject("too many vertical segments"); continue end
		if tinyCells / math.max(1, allCells) > configured.MaxTinyFraction then
			reject("too much tiny disconnected debris"); continue
		end
		local row = {source = source, proxies = {}, expected = #significant}
		local valid = true
		for index, segment in significant do
			local proxy, reason = bodyProxy(source, grid, sourceCF, sourceSize, segment, index, true)
			if not proxy then reject(reason); valid = false; break end
			proxy.Parent = proxyFolder
			table.insert(row.proxies, proxy)
			proxyRows[proxy] = {sourceRow = row, bodyIndex = index}
		end
		if valid then table.insert(sourceRows, row)
		else for _, proxy in row.proxies do proxy:Destroy() end end
	end
	local gridReport = require(script.Parent.ShibuyaGridMassing).Preview(proxyFolder, {
		MinFloors = configured.MinBodyFloors,
		MinSupportFloors = configured.MinBodyFloors,
	})
	local acceptedByProxy = {}
	for _, plan in gridReport.plans do acceptedByProxy[plan.oldModel] = plan end
	local report = {
		plans = {},
		sources = {},
		rejected = rejected,
		gridRejected = gridReport.rejected,
		readOnly = true,
		segmentMode = true,
	}
	for _, row in sourceRows do
		local sourcePlans, complete = {}, true
		for _, proxy in row.proxies do
			local plan = acceptedByProxy[proxy]
			if not plan then complete = false; break end
			local bodyIndex = proxyRows[proxy].bodyIndex
			plan.oldModel = row.source
			plan.key = row.source:GetAttribute("ShibuyaSourceKey") .. "_segment" .. bodyIndex
			plan.splitBodyIndex = bodyIndex
			plan.splitBodyCount = row.expected
			plan.reason = "Complete non-overlapping vertical grid segment; " .. plan.reason
			table.insert(sourcePlans, plan)
		end
		if complete and #sourcePlans == row.expected then
			table.sort(sourcePlans, function(a, b) return a.splitBodyIndex < b.splitBodyIndex end)
			table.insert(report.sources, {
				oldModel = row.source,
				plans = sourcePlans,
				key = row.source:GetAttribute("ShibuyaSourceKey"),
			})
			for _, plan in sourcePlans do table.insert(report.plans, plan) end
		else reject("one or more vertical segments failed independent validation") end
	end
	proxyFolder:Destroy()
	table.sort(report.sources, function(a, b)
		local areaA, areaB = 0, 0
		for _, p in a.plans do areaA += p.area end
		for _, p in b.plans do areaB += p.area end
		if areaA ~= areaB then return areaA > areaB end
		return a.key < b.key
	end)
	print("GRID_SEGMENT_PREVIEW", #report.sources, "legacy sources,", #report.plans,
		"non-overlapping smooth segments; no geometry changed")
	return report
end

function Split.Stage(report, options)
	editOnly()
	options = optionsWithDefaults(options)
	assert(type(report) == "table" and type(report.sources) == "table", "Pass a split preview report")
	local stage = Instance.new("Folder")
	stage.Name = "ShibuyaGridSplitStage_" .. Http:GenerateGUID(false)
	stage:SetAttribute("GridSplitStageVersion", 1)
	stage.Parent = Storage
	local failures, sourceCount = {}, math.min(options.MaxSources, #report.sources)
	for sourceIndex = 1, sourceCount do
		local sourceRow = report.sources[sourceIndex]
		local built, sourceFailure = {}, nil
		for _, plan in sourceRow.plans do
			local name = string.format("BuildingSmooth_%s_Body%02d", sourceRow.key, plan.splitBodyIndex)
			local ok, building = pcall(require(script.Parent.SmoothBuildingBuilder).StagePlan, name, plan)
			if not ok then sourceFailure = tostring(building); break end
			building:SetAttribute("ShibuyaSourceKey", plan.key)
			building:SetAttribute("MassingConfidence", plan.confidence)
			building:SetAttribute("MassingBasis", plan.reason)
			building:SetAttribute("SourceBaseY", plan.sourceBaseY)
			building:SetAttribute("FloorCountBasis", "Repeated independent legacy grid body")
			building:SetAttribute("SplitSourceKey", sourceRow.key)
			building:SetAttribute("SplitBodyIndex", plan.splitBodyIndex)
			building:SetAttribute("SplitBodyCount", #sourceRow.plans)
			local link = Instance.new("ObjectValue")
			link.Name = "ReplacementSource"
			link.Value = sourceRow.oldModel
			link.Parent = building
			building:SetAttribute("ReplacementSourcePivot", sourceRow.oldModel:GetPivot())
			table.insert(built, building)
		end
		if sourceFailure then
			for _, building in built do building:Destroy() end
			table.insert(failures, {name = sourceRow.oldModel.Name, reason = sourceFailure})
		else
			for _, building in built do building.Parent = stage end
		end
		if sourceIndex % 5 == 0 then task.wait() end
	end
	stage:SetAttribute("Expected", #stage:GetChildren())
	stage:SetAttribute("ExpectedSources", sourceCount - #failures)
	stage:SetAttribute("BuildFailures", #failures)
	print("GRID_SPLIT_STAGED", #stage:GetChildren(), "bodies from",
		stage:GetAttribute("ExpectedSources"), "sources;", #failures, "source failures", stage.Name)
	return stage, failures
end

function Split.Apply(stage)
	editOnly()
	assert(stage and stage.Parent == Storage and stage:GetAttribute("GridSplitStageVersion") == 1
		and not stage:GetAttribute("Applied"), "Invalid split stage")
	assert(stage:GetAttribute("BuildFailures") == 0, "Split stage has source failures")
	local audit = require(script.Parent.SmoothBuildingAudit).Run(stage)
	assert(audit.summary.badBuildings == 0 and audit.summary.buildings == stage:GetAttribute("Expected"),
		"Split stage failed structural audit")
	local bySource, names = {}, {}
	for _, building in stage:GetChildren() do
		local link = building:FindFirstChild("ReplacementSource")
		local old = link and link.Value
		assert(old and old.Parent == workspace.Buildings and old.Name:match("^BuildingAuto_"),
			"Split replacement source changed")
		assert(old:GetPivot() == building:GetAttribute("ReplacementSourcePivot"), "Split source moved after staging")
		assert(not workspace.Buildings:FindFirstChild(building.Name) and not names[building.Name],
			"Duplicate split replacement name")
		names[building.Name] = true
		bySource[old] = bySource[old] or {}
		table.insert(bySource[old], building)
	end
	local sourceCount = 0
	for old, buildings in bySource do
		sourceCount += 1
		local expected = buildings[1]:GetAttribute("SplitBodyCount")
		assert(#buildings == expected, "Split source is missing a staged body")
		local indices = {}
		for _, building in buildings do
			assert(building:GetAttribute("SplitBodyCount") == expected, "Split body counts disagree")
			indices[building:GetAttribute("SplitBodyIndex")] = true
		end
		for index = 1, expected do assert(indices[index], "Split body index is missing") end
	end
	assert(sourceCount == stage:GetAttribute("ExpectedSources"), "Split source count changed")
	History:SetWaypoint("Before split smooth polygon replacements")
	local archive = Instance.new("Folder")
	archive.Name = "ShibuyaBeforeGridSplit_" .. Http:GenerateGUID(false)
	archive.Parent = Storage
	local moved = {}
	local ok, err = pcall(function()
		for old in bySource do
			old.Parent = archive
			table.insert(moved, {kind = "old", object = old})
		end
		for _, building in stage:GetChildren() do
			building.Parent = workspace.Buildings
			table.insert(moved, {kind = "new", object = building})
		end
	end)
	if not ok then
		for index = #moved, 1, -1 do
			local item = moved[index]
			item.object.Parent = item.kind == "old" and workspace.Buildings or stage
		end
		error(err)
	end
	stage:SetAttribute("Applied", true)
	archive:SetAttribute("ReplacedSourceCount", sourceCount)
	archive:SetAttribute("GeneratedBodyCount", #moved - sourceCount)
	History:SetWaypoint("Split smooth polygon replacements")
	print("GRID_SPLIT_APPLIED", sourceCount, "legacy sources as", #moved - sourceCount,
		"smooth bodies; originals retained in", archive.Name)
	return archive, audit
end

return Split
