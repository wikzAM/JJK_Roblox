-- Run in Studio edit mode after syncing. Only temporary ServerStorage stages.
local Manual = require(game.ServerScriptService.Server.ManualShellBuilder)
local created = {}
local ok, err = pcall(function()
	local cf = CFrame.new(200,60,-300) * CFrame.Angles(0,0.37,0)
	local sections = {
		{cf=cf, size=Vector3.new(80,120,60), floors=6},
		{cf=cf*CFrame.new(60,-20,0), size=Vector3.new(40,80,60), floors=4, core=false},
	}
	local stage = Manual.Stage("BuildingManualVerification", sections)
	table.insert(created, stage)
	assert(stage:GetAttribute("ManualSectionCount") == 2)
	assert(stage:GetAttribute("GeneratedFloorSections") == 10)
	for i, section in stage.Interior:GetChildren() do
		local expected = sections[i]
		assert(section:GetAttribute("GeneratedFloors") == expected.floors)
		for _, floor in section.Interior:GetChildren() do
			local slabs = 0
			for _, p in floor:GetChildren() do
				if p.Name == "Slab" then
					slabs += 1
					assert(p:IsA("Part") and p.Anchored and p.CanCollide)
					assert(math.abs(p.Size.X - expected.size.X) < 0.001)
					assert(math.abs(p.Size.Z - expected.size.Z) < 0.001)
				end
			end
			assert(slabs == 1, "Section floor must be one exact rectangular slab")
		end
	end
	assert(stage.Interior.BuildingSection_02:GetAttribute("CoreSize") == nil)
	local rejected = pcall(Manual.Stage, "BuildingOverlapVerification", {sections[1],sections[1]})
	assert(not rejected, "Duplicate overlapping massing must reject")
	stage:PivotTo(stage:GetPivot() * CFrame.new(30,0,90) * CFrame.Angles(0,0.2,0))
	local rebuilt = Manual.Rebuild(stage)
	table.insert(created, rebuilt)
	assert((rebuilt:GetPivot().Position - stage:GetPivot().Position).Magnitude < 0.01, "Moved rebuild shifted position")
	assert(rebuilt:GetAttribute("GeneratedParts") == stage:GetAttribute("GeneratedParts"))
end)
for _, item in created do item:Destroy() end
assert(ok, err)
print("MANUAL_SHELL_VERIFICATION_PASSED: exact rotated sections, overlap rejection, disabled wing core, moved staged rebuild")
