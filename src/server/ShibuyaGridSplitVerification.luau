--!nonstrict
-- Disposable saved-grid split fixtures. Live map and archives are untouched.
local Verify = {}

local Http = game:GetService("HttpService")
local SLAB, PITCH = 1.5 / 0.28, 5 / 0.28

local function mask(predicate)
	local bits = {}
	for i = 1, 20 do
		for j = 1, 20 do table.insert(bits, predicate(i, j) and "1" or "0") end
	end
	return table.concat(bits)
end

local function fixture(parent, key, masks)
	local model = Instance.new("Model")
	model.Name = "BuildingAuto_" .. key
	model:SetAttribute("ShibuyaSourceKey", key)
	local height = #masks * PITCH + SLAB
	model:SetAttribute("InteriorBBoxCFrame", CFrame.new(14000, height / 2, -14000) * CFrame.Angles(0, 0.31, 0))
	model:SetAttribute("InteriorBBoxSize", Vector3.new(60, height, 60))
	model:SetAttribute("InteriorGrid", Http:JSONEncode({
		cell = 3,
		nx = 20,
		nz = 20,
		minX = -30,
		minZ = -30,
		floors = #masks,
		ground = PITCH - SLAB,
		clearUpper = PITCH - SLAB,
		occ = masks,
		occTight = masks,
	}))
	model.Parent = parent
	return model
end

function Verify.Run()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	local folder = Instance.new("Folder")
	folder.Name = "GridSplitVerificationTemporary"
	folder.Parent = game.ServerStorage
	local stages = {}
	local ok, result = pcall(function()
		local twoBodies = mask(function(i, j)
			return (i <= 8 and j <= 8) or (i >= 13 and j >= 13)
		end)
		fixture(folder, "split_two", {twoBodies, twoBodies, twoBodies})
		local connected = mask(function(i, j)
			return (i <= 8 and j <= 8) or (i >= 13 and j >= 13)
				or (i >= 8 and i <= 13 and j >= 8 and j <= 13)
		end)
		fixture(folder, "split_branch", {connected, twoBodies, twoBodies})
		local primaryAndTiny = mask(function(i, j)
			return (i <= 12 and j <= 12) or (i == 20 and j == 20)
		end)
		fixture(folder, "split_tiny", {primaryAndTiny, primaryAndTiny, primaryAndTiny})

		local split = require(script.Parent.ShibuyaGridSplitPass)
		local report = split.Preview(folder)
		assert(#report.sources == 1 and #report.plans == 2,
			"Only the two independent persistent bodies should pass")
		assert(report.sources[1].key == "split_two", "Wrong split source accepted")
		for index, plan in report.sources[1].plans do
			assert(plan.splitBodyIndex == index and plan.splitBodyCount == 2, "Split identity is not deterministic")
			assert(plan.oldModel == folder.BuildingAuto_split_two, "Plan lost its exact source identity")
		end
		local stage, failures = split.Stage(report)
		table.insert(stages, stage)
		assert(#failures == 0 and #stage:GetChildren() == 2, "Split staging did not build both bodies")
		local audit = require(script.Parent.SmoothBuildingAudit).Run(stage)
		assert(audit.summary.badBuildings == 0 and audit.summary.buildings == 2,
			"Staged split bodies failed structural audit")
		local segmentReport = split.PreviewSegments(folder, {MinBodyFloors = 1})
		assert(#segmentReport.sources == 2 and #segmentReport.plans == 5,
			"Branch decomposition should produce two independent bodies plus podium and towers")
		local segmentStage, segmentFailures = split.Stage(segmentReport, {MinBodyFloors = 1})
		table.insert(stages, segmentStage)
		assert(#segmentFailures == 0 and #segmentStage:GetChildren() == 5,
			"Segment staging did not preserve the complete decompositions")
		local segmentAudit = require(script.Parent.SmoothBuildingAudit).Run(segmentStage)
		assert(segmentAudit.summary.badBuildings == 0 and segmentAudit.summary.buildings == 5,
			"Staged branch segments failed structural audit")
		return {
			acceptedSources = #report.sources,
			acceptedBodies = #report.plans,
			segmentSources = #segmentReport.sources,
			segmentBodies = #segmentReport.plans,
			rejectedSources = 2,
			structuralParts = audit.summary.structuralParts + segmentAudit.summary.structuralParts,
		}
	end)
	for _, stage in stages do if stage then stage:Destroy() end end
	folder:Destroy()
	assert(ok, result)
	print("GRID_SPLIT_VERIFIED", Http:JSONEncode(result))
	return result
end

return Verify
