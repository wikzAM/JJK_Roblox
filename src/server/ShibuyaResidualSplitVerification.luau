--!nonstrict
-- Disposable end-to-end fixture for partial extraction plus exact residual retention.
local Verify = {}

local Http = game:GetService("HttpService")

local function mask(nx, nz, left, right)
	local bits = table.create(nx * nz, "0")
	for i = 1, 8 do for j = 1, 8 do bits[(i - 1) * nz + j] = "1" end end
	if right then
		for i = 15, 19 do for j = 3, 7 do bits[(i - 1) * nz + j] = "1" end end
	end
	return table.concat(bits)
end

function Verify.Run()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	local token = "ResidualFixture_" .. Http:GenerateGUID(false):gsub("-", ""):sub(1, 8)
	local source = Instance.new("Model")
	source.Name = "BuildingAuto_" .. token
	source:SetAttribute("ShibuyaSourceKey", token)
	source:SetAttribute("InteriorBBoxCFrame", CFrame.new(50000, 50, 50000))
	source:SetAttribute("InteriorBBoxSize", Vector3.new(100, 100, 50))
	local nx, nz = 20, 10
	local first, upper = mask(nx, nz, true, true), mask(nx, nz, true, false)
	source:SetAttribute("InteriorGrid", Http:JSONEncode({
		cell = 5, nx = nx, nz = nz, minX = -50, minZ = -25,
		floors = 4, ground = 12.5, clearUpper = 12.5,
		occ = {first, upper, upper, upper},
		occTight = {first, upper, upper, upper},
	}))
	source.Parent = workspace.Buildings
	local stage, archive
	local ok, result = pcall(function()
		local pass = require(script.Parent.ShibuyaResidualSplitPass)
		local report = pass.Preview({source}, {MaxSources = 1})
		assert(#report.sources == 1 and #report.plans == 1, "Valid vertical body was not extracted")
		local row = report.sources[1]
		assert(row.consumedCells == 256 and row.remainingCells == 25,
			string.format("Accepted or residual cell accounting changed: %d consumed, %d remaining",
				row.consumedCells, row.remainingCells))
		local failures
		stage, failures = pass.Stage(report)
		assert(#failures == 0 and #stage:GetChildren() == 2, "Smooth plus residual staging failed")
		local smooth, residual = 0, 0
		for _, output in stage:GetChildren() do
			if output:GetAttribute("ResidualOutputKind") == "Smooth" then smooth += 1
			elseif output:GetAttribute("ResidualOutputKind") == "LegacyResidual" then residual += 1 end
		end
		assert(smooth == 1 and residual == 1, "Stage did not retain both output kinds")
		archive = pass.Apply(stage)
		assert(source.Parent == archive, "Original fixture was not archived")
		local installed = 0
		for _, output in workspace.Buildings:GetChildren() do
			if output.Name:find(token, 1, true) then installed += 1 end
		end
		assert(installed == 2, "Atomic apply did not install smooth plus residual outputs")
		return {plans = #report.plans, consumed = row.consumedCells, residual = row.remainingCells, installed = installed}
	end)
	for _, output in workspace.Buildings:GetChildren() do
		if output.Name:find(token, 1, true) then output:Destroy() end
	end
	if source.Parent then source:Destroy() end
	if archive and archive.Parent then archive:Destroy() end
	if stage and stage.Parent then stage:Destroy() end
	assert(ok, result)
	print("RESIDUAL_SPLIT_VERIFIED", Http:JSONEncode(result))
	return result
end

return Verify
