--!nonstrict
-- require(game.ServerScriptService.Server.SourceSliceVerification).Run()
-- Disposable source-slice builder/replacement fixtures. Only uniquely named
-- temporary models enter Workspace.Buildings, and every path cleans them up.
local Verify = {}

local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local SLAB, PITCH = 1.5 / 0.28, 5 / 0.28

local function rectangle(x0, z0, x1, z1)
	return {{x0, z0}, {x1, z0}, {x1, z1}, {x0, z1}}
end

local function levels(piecesByLevel)
	local result = {}
	for index, pieces in piecesByLevel do
		table.insert(result, {y = (index - 1) * PITCH, thickness = SLAB, pieces = pieces})
	end
	return result
end

local function plan(id, origin, piecesByLevel, core)
	return {
		id = id,
		origin = {x = origin.X, y = origin.Y, z = origin.Z},
		levels = levels(piecesByLevel),
		core = core,
		sourceInfo = {fixture = true, id = id},
	}
end

local function sourceFixture(token, index)
	local model = Instance.new("Model")
	model.Name = string.format("BuildingSmooth_%s_%d", token, index)
	model:SetAttribute("ShibuyaSourceKey", string.format("%s_source_%d", token, index))
	local part = Instance.new("Part")
	part.Name = "FixtureStructure"
	part.Size = Vector3.new(12, 12, 12)
	part.CFrame = CFrame.new(30000 + index * 20, 5000, -30000)
	part.Anchored = true
	part.CanCollide = true
	part.Parent = model
	model.Parent = assert(workspace:FindFirstChild("Buildings"), "Workspace.Buildings is missing")
	return model, part
end

local function countArchives()
	local count = 0
	for _, child in Storage:GetChildren() do
		if child:IsA("Folder") and child.Name:match("^ShibuyaBeforeSourceSlice_") then count += 1 end
	end
	return count
end

local function requireCleanAudit(audit, label)
	if audit.summary.badBuildings == 0 then return end
	local reasons = {}
	for _, row in audit.badModels do
		for _, reason in row.reasons do table.insert(reasons, reason) end
	end
	error(label .. ": " .. table.concat(reasons, " | "), 2)
end

function Verify.Run()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	script:SetAttribute("VerificationLastOK", nil)
	script:SetAttribute("VerificationLastResult", nil)
	local Builder = require(script.Parent.SourceSliceBuilder)
	local Replacement = require(script.Parent.SourceSliceReplacement)
	local token = "SourceSliceFixture_" .. Http:GenerateGUID(false):gsub("-", ""):sub(1, 10)
	local world = Instance.new("WorldModel")
	world.Name = token .. "_World"
	world.Parent = workspace
	local cleanup = {world}
	local stats = {
		builderFixtures = 0,
		invalidRejected = 0,
		regeneration = false,
		wedgeCSG = false,
		previewRestore = false,
		manyToOneApply = false,
		staleMutationRejected = false,
	}

	local ok, result = pcall(function()
		local base = Vector3.new(24000, 4000, -24000)
		local rectanglePlan = plan(token .. "_rectangle", base, {
			{rectangle(-40, -30, 40, 30)},
			{rectangle(-40, -30, 40, 30)},
			{rectangle(-40, -30, 40, 30)},
		}, {minX = -8, minZ = -8, maxX = 8, maxZ = 8})
		local rectangleModel = Builder.Build(rectanglePlan)
		rectangleModel.Parent = world
		requireCleanAudit(Builder.Audit(rectangleModel), "Rectangle audit failed")
		stats.builderFixtures += 1

		local concave = {{-50, -40}, {50, -40}, {50, -10}, {0, -10}, {0, 40}, {-50, 40}}
		local concavePlan = plan(token .. "_concave", base + Vector3.new(200, 0, 0), {
			{concave}, {concave}, {concave},
		}, {minX = -30, minZ = -5, maxX = -15, maxZ = 10})
		local concaveModel = Builder.Build(concavePlan)
		concaveModel.Parent = world
		local concaveAudit = Builder.Audit(concaveModel)
		requireCleanAudit(concaveAudit, "Concave source floor audit failed")
		assert(concaveAudit.summary.wedges > 0, "Concave source floor lost its native wedge geometry")
		stats.builderFixtures += 1

		local courtyard = {
			rectangle(-40, -30, 40, -15),
			rectangle(-40, 15, 40, 30),
			rectangle(-40, -15, -15, 15),
			rectangle(15, -15, 40, 15),
		}
		local courtyardPlan = plan(token .. "_courtyard", base + Vector3.new(400, 0, 0), {
			courtyard, courtyard, courtyard,
		}, {minX = -35, minZ = -6, maxX = -22, maxZ = 6})
		local courtyardModel = Builder.Build(courtyardPlan)
		courtyardModel.Parent = world
		requireCleanAudit(Builder.Audit(courtyardModel), "Courtyard piece union audit failed")
		stats.builderFixtures += 1

		local setbackPlan = plan(token .. "_setback", base + Vector3.new(600, 0, 0), {
			{rectangle(-55, -45, 55, 45)},
			{rectangle(-25, -25, 35, 30)},
			{rectangle(-25, -25, 35, 30)},
		}, {minX = -10, minZ = -10, maxX = 10, maxZ = 10})
		local setbackModel = Builder.Build(setbackPlan)
		setbackModel.Parent = world
		requireCleanAudit(Builder.Audit(setbackModel), "Changing setback audit failed")
		stats.builderFixtures += 1

		local overlappingPlan = plan(token .. "_overlap", base, {
			{rectangle(-30, -20, 10, 20), rectangle(-10, -20, 30, 20)},
			{rectangle(-30, -20, 30, 20)},
		}, {minX = -6, minZ = -6, maxX = 6, maxZ = 6})
		assert(not pcall(Builder.Validate, overlappingPlan), "Overlapping source pieces were accepted")
		stats.invalidRejected += 1

		local noCommonCorePlan = plan(token .. "_no_common_core", base, {
			{rectangle(-40, -20, 10, 20)},
			{rectangle(20, -20, 70, 20)},
		}, {minX = -8, minZ = -6, maxX = 8, maxZ = 6})
		assert(not pcall(Builder.Validate, noCommonCorePlan), "A core outside an upper floor was accepted")
		stats.invalidRejected += 1

		local oldDescendants = #concaveModel.Interior:GetDescendants()
		local delta = CFrame.new(40, 30, -70) * CFrame.Angles(0, 0.27, 0)
		concaveModel:PivotTo(delta * concaveModel:GetPivot())
		local regenerated, backup = Builder.Regenerate(concaveModel)
		table.insert(cleanup, backup)
		assert(regenerated and backup:FindFirstChild("Interior"), "Moved regeneration did not retain its backup")
		assert(#concaveModel.Interior:GetDescendants() == oldDescendants, "Moved regeneration changed structure")
		requireCleanAudit(Builder.Audit(concaveModel), "Moved regenerated model failed audit")
		stats.regeneration = true

		local wedge
		for _, object in concaveModel.Interior:GetDescendants() do
			if object:IsA("WedgePart") then wedge = object break end
		end
		assert(wedge, "No source-slice wedge exists for the CSG fixture")
		local clone = wedge:Clone()
		clone.Parent = world
		local cutter = Instance.new("Part")
		cutter.Shape = Enum.PartType.Ball
		local diameter = math.min(clone.Size.X, clone.Size.Y, clone.Size.Z) * 0.6
		cutter.Size = Vector3.one * diameter
		cutter.CFrame = clone.CFrame * CFrame.new(0, -clone.Size.Y / 6, clone.Size.Z / 6)
		cutter.Anchored = true
		cutter.CanCollide = false
		cutter.Parent = world
		local carved = clone:SubtractAsync({cutter})
		assert(carved and carved:IsA("UnionOperation"), "Source-slice wedge cannot be carved through CSG")
		carved:Destroy()
		cutter:Destroy()
		clone:Destroy()
		stats.wedgeCSG = true

		local source1 = sourceFixture(token, 1)
		local source2 = sourceFixture(token, 2)
		table.insert(cleanup, source1)
		table.insert(cleanup, source2)
		local replacementPlan = plan(token .. "_many_to_one", Vector3.new(30020, 5000, -30000), {
			{rectangle(-25, -15, 25, 15)},
			{rectangle(-25, -15, 25, 15)},
		}, {minX = -7, minZ = -6, maxX = 7, maxZ = 6})
		local stage, failures = Builder.StagePlans({replacementPlan})
		table.insert(cleanup, stage)
		assert(#failures == 0 and #stage:GetChildren() == 1, "Replacement fixture staging failed")
		local captured = Replacement.Capture(stage, {source1, source2})
		assert(captured.sources == 2 and captured.outputs == 1, "Many-to-one ownership binding changed")
		local preview = Replacement.Preview(stage, "after")
		assert(source1.Parent ~= workspace.Buildings and source2.Parent ~= workspace.Buildings
			and preview.folder.Parent == workspace, "After preview did not isolate exact originals")
		assert(Replacement.Restore(stage), "Preview restore reported no active preview")
		assert(source1.Parent == workspace.Buildings and source2.Parent == workspace.Buildings
			and preview.folder.Parent == nil, "Preview restore did not recover exact originals")
		stats.previewRestore = true
		local archive = Replacement.Apply(stage)
		table.insert(cleanup, archive)
		local output
		for _, child in workspace.Buildings:GetChildren() do
			if child:GetAttribute("SourceSliceId") == replacementPlan.id then output = child break end
		end
		assert(source1.Parent == archive and source2.Parent == archive and output,
			"Many-to-one apply did not archive both exact originals and install its output")
		table.insert(cleanup, output)
		stats.manyToOneApply = true

		local staleSource, stalePart = sourceFixture(token, 3)
		table.insert(cleanup, staleSource)
		local stalePlan = plan(token .. "_stale", Vector3.new(30100, 5000, -30000), {
			{rectangle(-15, -15, 15, 15)},
			{rectangle(-15, -15, 15, 15)},
		}, {minX = -6, minZ = -6, maxX = 6, maxZ = 6})
		local staleStage, staleFailures = Builder.StagePlans({stalePlan})
		table.insert(cleanup, staleStage)
		assert(#staleFailures == 0, "Stale-source fixture staging failed")
		Replacement.Capture(staleStage, {staleSource})
		local archivesBefore = countArchives()
		local oldColor = stalePart.Color
		stalePart.Color = Color3.fromRGB(255, 0, 0)
		assert(not pcall(Replacement.Apply, staleStage), "Mutated bound source was applied")
		assert(staleSource.Parent == workspace.Buildings and countArchives() == archivesBefore,
			"Rejected stale apply moved an original or created an archive")
		stalePart.Color = oldColor
		stats.staleMutationRejected = true

		return stats
	end)

	for index = #cleanup, 1, -1 do
		local object = cleanup[index]
		if object and object.Parent then object:Destroy() end
	end
	for _, child in workspace:GetChildren() do
		if child.Name:find(token, 1, true) then child:Destroy() end
	end
	for _, child in workspace.Buildings:GetChildren() do
		if child.Name:find(token, 1, true)
			or child:GetAttribute("SourceSliceId") and tostring(child:GetAttribute("SourceSliceId")):find(token, 1, true) then
			child:Destroy()
		end
	end
	for _, child in Storage:GetChildren() do
		if child.Name:find(token, 1, true) then child:Destroy() end
	end
	script:SetAttribute("VerificationLastOK", ok)
	script:SetAttribute("VerificationLastResult", ok and Http:JSONEncode(result) or tostring(result))
	assert(ok, result)
	print("SOURCE_SLICE_VERIFIED", Http:JSONEncode(result))
	return result
end

return Verify
