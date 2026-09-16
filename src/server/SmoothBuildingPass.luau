--!nonstrict
-- Guarded edit-time orchestration for incremental legacy-to-smooth batches.
-- Rojo syncs this module, but Studio's Command Bar must invoke RunNext().
local Pass = {}

local DEFAULT_BATCH_SIZE = 100

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end

local function configuredOptions(options)
	options = options or {}
	local batchSize = options.BatchSize or DEFAULT_BATCH_SIZE
	assert(type(batchSize) == "number" and batchSize % 1 == 0 and batchSize >= 1,
		"BatchSize must be a positive integer")
	return options, batchSize
end

local function selectedReport(report, batchSize)
	local ranked = table.clone(report.plans)
	table.sort(ranked, function(a, b)
		if a.confidence ~= b.confidence then return a.confidence > b.confidence end
		if a.area ~= b.area then return a.area > b.area end
		return a.key < b.key
	end)

	local plans = {}
	for index = 1, math.min(batchSize, #ranked) do
		plans[index] = ranked[index]
	end
	return {
		plans = plans,
		scanned = report.scanned,
		matched = report.matched,
		available = #report.plans,
		rejected = report.rejected,
		methods = report.methods,
	}
end

-- Read-only scan. Returns both the selected batch and the complete massing report.
function Pass.PreviewNext(options)
	editOnly()
	local configured, batchSize = configuredOptions(options)
	options = configured
	local components = require(script.Parent.ShibuyaGeometry).Scan(options.Source)
	local report = require(script.Parent.ShibuyaMassing).Preview(components, options)
	local selected = selectedReport(report, batchSize)
	print("SMOOTH_NEXT_PREVIEW", #selected.plans, "selected from", #report.plans,
		"eligible plans;", report.matched, "remaining legacy models matched")
	return selected, report
end

-- Builds only in ServerStorage. No live model is moved by this function.
function Pass.StageNext(options)
	editOnly()
	options = options or {}
	local selected, report = Pass.PreviewNext(options)
	assert(#selected.plans > 0, "No remaining BuildingAuto models passed smooth massing analysis")
	local stage, failures = require(script.Parent.SmoothBuildingBuilder).Build(selected, {
		RequestedFloors = options.RequestedFloors,
	})
	stage:SetAttribute("SmoothPassAvailable", selected.available)
	stage:SetAttribute("SmoothPassSelected", #selected.plans)
	return stage, failures, report
end

-- Structural verification is mandatory. Apply archives exact originals in
-- ServerStorage.ShibuyaBeforeSmooth_*; it never deletes the jagged copies.
function Pass.ApplyVerified(stage)
	editOnly()
	assert(stage and stage.Parent == game:GetService("ServerStorage"), "Pass a staged smooth batch")
	assert(stage:GetAttribute("BuildFailures") == 0, "Staged batch has build failures; do not apply it")
	local audit = require(script.Parent.SmoothBuildingAudit).Run(stage)
	assert(audit.summary.buildings == stage:GetAttribute("Expected"), "Audit did not inspect the complete stage")
	assert(audit.summary.badBuildings == 0, "Staged batch failed structural audit; do not apply it")
	local archive = require(script.Parent.SmoothBuildingBuilder).Apply(stage)
	assert(archive:GetAttribute("ReplacedCount") == audit.summary.buildings, "Archive count disagrees with applied batch")
	print("SMOOTH_NEXT_VERIFIED_APPLIED", audit.summary.buildings,
		"smooth buildings;", archive.Name, "retains every original")
	return archive, audit
end

-- One-command incremental pass. Set StageOnly=true to stop before live changes.
function Pass.RunNext(options)
	editOnly()
	options = options or {}
	local stage, failures, report = Pass.StageNext(options)
	if #failures > 0 then
		warn("SMOOTH_NEXT_NOT_APPLIED", #failures, "build failures; inspect", stage.Name)
		return nil, stage, failures, report
	end
	if options.StageOnly then
		print("SMOOTH_NEXT_STAGED_ONLY", stage.Name, #stage:GetChildren(), "buildings")
		return nil, stage, failures, report
	end
	local archive, audit = Pass.ApplyVerified(stage)
	return archive, stage, failures, report, audit
end

return Pass
