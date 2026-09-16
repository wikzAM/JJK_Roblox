--!nonstrict
-- Incrementally extracts independently valid vertical grid segments while
-- regenerating every unaccepted source cell as a live residual BuildingAuto.
-- The complete original is archived atomically; no unresolved occupancy is lost.
local Residual = {}

local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local History = game:GetService("ChangeHistoryService")
local DEFAULTS = {
	MaxSources = 20,
	MaxTinyCells = 4,
	MinExtractFraction = 0.02,
	StructuralResidual = true,
}
local GRID_DEFAULTS = {
	MinFloors = 2,
	MinSupportFloors = 2,
	MinValidFraction = 0.67,
	MinHeightCoverage = 0.60,
	MinEnvelopeSpan = 0.60,
	MinEnvelopeArea = 0.30,
	Similarity = 0.82,
	NearbySimilarity = 0.72,
	MinDominantArea = 0.92,
}

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end

local function configured(options)
	local result = table.clone(DEFAULTS)
	for key, value in options or {} do
		if key == "GridOptions" then continue end
		assert(DEFAULTS[key] ~= nil, "Unknown residual option: " .. tostring(key))
		result[key] = value
	end
	assert(type(result.MaxSources) == "number" and result.MaxSources >= 1 and result.MaxSources % 1 == 0,
		"MaxSources must be a positive integer")
	assert(type(result.MaxTinyCells) == "number" and result.MaxTinyCells >= 1 and result.MaxTinyCells % 1 == 0,
		"MaxTinyCells must be a positive integer")
	assert(type(result.MinExtractFraction) == "number"
		and result.MinExtractFraction > 0 and result.MinExtractFraction <= 1, "Invalid MinExtractFraction")
	assert(type(result.StructuralResidual) == "boolean", "StructuralResidual must be boolean")
	result.GridOptions = table.clone(GRID_DEFAULTS)
	for key, value in (options and options.GridOptions) or {} do result.GridOptions[key] = value end
	return result
end

local function occupiedCells(grid)
	local count = 0
	for _, mask in grid.occ do
		for index = 1, #mask do if mask:byte(index) == 49 then count += 1 end end
	end
	return count
end

local function residualGrid(grid, acceptedRows)
	local removed = {}
	for floor = 1, grid.floors do removed[floor] = {} end
	local consumed = 0
	for _, row in acceptedRows do
		for _, node in row.segment.nodes do
			for _, index in node.cells do
				if not removed[node.floor][index] then
					removed[node.floor][index] = true
					consumed += 1
				end
			end
		end
	end
	local result = {
		cell = grid.cell, nx = grid.nx, nz = grid.nz,
		minX = grid.minX, minZ = grid.minZ, floors = grid.floors,
		ground = grid.ground, clearUpper = grid.clearUpper,
		occ = {}, occTight = {},
	}
	local remaining = 0
	for floor = 1, grid.floors do
		for field, target in {occ = result.occ, occTight = result.occTight} do
			local source = grid[field] and grid[field][floor] or grid.occ[floor]
			local bits = table.create(#source)
			for index = 1, #source do
				local occupied = source:byte(index) == 49 and not removed[floor][index]
				bits[index] = occupied and "1" or "0"
				if field == "occ" and occupied then remaining += 1 end
			end
			target[floor] = table.concat(bits)
		end
	end
	return result, consumed, remaining
end

function Residual.Preview(folder, options)
	editOnly()
	folder = folder or workspace:FindFirstChild("Buildings")
	assert(typeof(folder) == "Instance" or type(folder) == "table", "Pass a folder or source-model list")
	options = configured(options)
	local split = require(script.Parent.ShibuyaGridSplitPass)
	local gridMassing = require(script.Parent.ShibuyaGridMassing)
	local report = {sources = {}, plans = {}, rejected = {}, sourceFolder = folder, readOnly = true, options = options}
	local function reject(reason)
		report.rejected[reason] = (report.rejected[reason] or 0) + 1
	end
	local tested = 0
	local candidates = typeof(folder) == "Instance" and folder:GetChildren() or folder
	for _, source in candidates do
		if tested >= options.MaxSources then break end
		if not source:IsA("Model") or not source.Name:match("^BuildingAuto_") then continue end
		tested += 1
		local ok, decomposition = pcall(split.DecomposeSegments, source)
		if not ok then reject("invalid source grid"); continue end
		local proxyFolder = Instance.new("Folder")
		proxyFolder.Name = "ResidualProxy_" .. Http:GenerateGUID(false)
		proxyFolder.Parent = Storage
		local byProxy = {}
		for _, row in decomposition.segments do
			if row.proxy and row.maxCells > options.MaxTinyCells then
				row.proxy.Parent = proxyFolder
				byProxy[row.proxy] = row
			end
		end
		if #proxyFolder:GetChildren() == 0 then
			proxyFolder:Destroy()
			reject("no substantial vertical segments")
			continue
		end
		local gridReport = gridMassing.Preview(proxyFolder, options.GridOptions)
		local acceptedRows, plans = {}, {}
		for _, plan in gridReport.plans do
			local row = byProxy[plan.oldModel]
			if not row then continue end
			table.insert(acceptedRows, row)
			plan.oldModel = source
			plan.residualSegmentIndex = row.index
			plan.key = source:GetAttribute("ShibuyaSourceKey") .. "_residual" .. row.index
			plan.reason = "Residual-preserving vertical segment; " .. (plan.reason or "validated grid contour")
			table.insert(plans, plan)
		end
		local residual, consumed, remaining = residualGrid(decomposition.grid, acceptedRows)
		local total = occupiedCells(decomposition.grid)
		proxyFolder:Destroy()
		if #plans == 0 then reject("no independently valid segment"); continue end
		if consumed / math.max(total, 1) < options.MinExtractFraction then
			reject("accepted segments are too small")
			continue
		end
		table.sort(plans, function(a, b) return a.residualSegmentIndex < b.residualSegmentIndex end)
		local row = {
			source = source,
			key = source:GetAttribute("ShibuyaSourceKey"),
			plans = plans,
			residualGrid = residual,
			consumedCells = consumed,
			remainingCells = remaining,
			totalCells = total,
			sourceCF = decomposition.sourceCF,
			sourceSize = decomposition.sourceSize,
		}
		table.insert(report.sources, row)
		for _, plan in plans do table.insert(report.plans, plan) end
		if tested % 5 == 0 then task.wait() end
	end
	table.sort(report.sources, function(a, b)
		local fractionA, fractionB = a.consumedCells / a.totalCells, b.consumedCells / b.totalCells
		if fractionA ~= fractionB then return fractionA > fractionB end
		return a.key < b.key
	end)
	report.tested = tested
	print("RESIDUAL_PREVIEW", tested, "sources tested,", #report.sources, "extractable sources,",
		#report.plans, "smooth segments; no geometry changed")
	return report
end

local function sourceLink(output, source, expected)
	local link = Instance.new("ObjectValue")
	link.Name = "ReplacementSource"
	link.Value = source
	link.Parent = output
	output:SetAttribute("ReplacementSourcePivot", source:GetPivot())
	output:SetAttribute("ResidualOutputCount", expected)
end

function Residual.Stage(report)
	editOnly()
	assert(report and type(report.sources) == "table" and report.options, "Pass a residual preview report")
	local stage = Instance.new("Folder")
	stage.Name = "ShibuyaResidualStage_" .. Http:GenerateGUID(false)
	stage:SetAttribute("ResidualStageVersion", 1)
	stage.Parent = Storage
	local failures, smoothCount = {}, 0
	for _, sourceRow in report.sources do
		local outputs, failed = {}, nil
		for index, plan in sourceRow.plans do
			local name = string.format("BuildingSmooth_%s_ResidualBody%02d", sourceRow.key, plan.residualSegmentIndex)
			local ok, building = pcall(require(script.Parent.SmoothBuildingBuilder).StagePlan, name, plan)
			if not ok then failed = tostring(building); break end
			building:SetAttribute("ShibuyaSourceKey", plan.key)
			building:SetAttribute("MassingConfidence", plan.confidence)
			building:SetAttribute("MassingBasis", plan.reason)
			building:SetAttribute("SourceBaseY", plan.sourceBaseY)
			building:SetAttribute("FloorCountBasis", "Residual-preserving grid segment")
			building:SetAttribute("ResidualSegmentIndex", plan.residualSegmentIndex)
			building:SetAttribute("ResidualOutputKind", "Smooth")
			table.insert(outputs, building)
			smoothCount += 1
		end
		if not failed and sourceRow.remainingCells > 0 then
			local residual = Instance.new("Model")
			residual.Name = "BuildingAuto_" .. sourceRow.key .. "_Residual_" .. Http:GenerateGUID(false):sub(1, 8)
			residual:SetAttribute("ShibuyaSourceKey", residual.Name:sub(#"BuildingAuto_" + 1))
			residual:SetAttribute("InteriorBBoxCFrame", sourceRow.sourceCF)
			residual:SetAttribute("InteriorBBoxSize", sourceRow.sourceSize)
			residual:SetAttribute("InteriorGrid", Http:JSONEncode(sourceRow.residualGrid))
			residual:SetAttribute("StructuralOnly", report.options.StructuralResidual)
			residual:SetAttribute("ResidualFrom", sourceRow.key)
			residual:SetAttribute("ResidualOutputKind", "LegacyResidual")
			residual.Parent = stage
			local ok, generated = pcall(require(script.Parent.BuildingGenerator).Generate, residual)
			if not ok or not generated then failed = ok and "residual generation returned false" or tostring(generated) end
			table.insert(outputs, residual)
		end
		if failed then
			for _, output in outputs do output:Destroy() end
			table.insert(failures, {name = sourceRow.source.Name, reason = failed})
		else
			local expected = #outputs
			for _, output in outputs do
				sourceLink(output, sourceRow.source, expected)
				output:SetAttribute("ResidualConsumedCells", sourceRow.consumedCells)
				output:SetAttribute("ResidualRemainingCells", sourceRow.remainingCells)
				output.Parent = stage
			end
		end
	end
	smoothCount = 0
	for _, output in stage:GetChildren() do
		if output:IsA("Model") and output:GetAttribute("SmoothMassing") then smoothCount += 1 end
	end
	stage:SetAttribute("Expected", #stage:GetChildren())
	stage:SetAttribute("ExpectedSources", #report.sources - #failures)
	stage:SetAttribute("ExpectedSmooth", smoothCount)
	stage:SetAttribute("BuildFailures", #failures)
	print("RESIDUAL_STAGED", #stage:GetChildren(), "outputs from", stage:GetAttribute("ExpectedSources"),
		"sources;", #failures, "failures", stage.Name)
	return stage, failures
end

function Residual.Apply(stage)
	editOnly()
	assert(stage and stage.Parent == Storage and stage:GetAttribute("ResidualStageVersion") == 1
		and not stage:GetAttribute("Applied"), "Invalid residual stage")
	assert(#stage:GetChildren() == stage:GetAttribute("Expected"), "Residual stage is incomplete")
	local audit = require(script.Parent.SmoothBuildingAudit).Run(stage)
	assert(audit.summary.badBuildings == 0 and audit.summary.buildings == stage:GetAttribute("ExpectedSmooth"),
		"Residual smooth outputs failed structural audit")
	local bySource, names = {}, {}
	for _, output in stage:GetChildren() do
		local link = output:FindFirstChild("ReplacementSource")
		local source = link and link.Value
		assert(source and source.Parent == workspace.Buildings and source.Name:match("^BuildingAuto_"),
			"Residual source changed")
		assert(source:GetPivot() == output:GetAttribute("ReplacementSourcePivot"), "Residual source moved")
		assert(not workspace.Buildings:FindFirstChild(output.Name) and not names[output.Name],
			"Residual output name collision")
		names[output.Name] = true
		if output:GetAttribute("ResidualOutputKind") == "LegacyResidual" then
			assert(output:FindFirstChild("Interior"), "Residual output is missing its Interior")
			for _, part in output:GetDescendants() do
				if not part:IsA("BasePart") then continue end
				assert(part.Anchored and part.Size.X >= 0.05 and part.Size.Y >= 0.05 and part.Size.Z >= 0.05,
					"Residual output has invalid structural geometry")
			end
		end
		bySource[source] = bySource[source] or {}
		table.insert(bySource[source], output)
	end
	local sourceCount = 0
	for source, outputs in bySource do
		sourceCount += 1
		assert(#outputs == outputs[1]:GetAttribute("ResidualOutputCount"), "Residual source output set is incomplete")
	end
	assert(sourceCount == stage:GetAttribute("ExpectedSources"), "Residual source count changed")
	History:SetWaypoint("Before residual smooth replacements")
	local archive = Instance.new("Folder")
	archive.Name = "ShibuyaBeforeResidual_" .. Http:GenerateGUID(false)
	archive.Parent = Storage
	local moved = {}
	local ok, err = pcall(function()
		for source in bySource do
			source.Parent = archive
			table.insert(moved, {object = source, old = true})
		end
		for _, output in stage:GetChildren() do
			output.Parent = workspace.Buildings
			table.insert(moved, {object = output, old = false})
		end
	end)
	if not ok then
		for index = #moved, 1, -1 do
			local item = moved[index]
			item.object.Parent = item.old and workspace.Buildings or stage
		end
		archive:Destroy()
		error(err)
	end
	stage:SetAttribute("Applied", true)
	archive:SetAttribute("ReplacedSourceCount", sourceCount)
	archive:SetAttribute("GeneratedOutputCount", #moved - sourceCount)
	History:SetWaypoint("Residual smooth replacements")
	print("RESIDUAL_APPLIED", sourceCount, "legacy sources as", #moved - sourceCount,
		"smooth/residual outputs; originals retained in", archive.Name)
	return archive, audit
end

return Residual
