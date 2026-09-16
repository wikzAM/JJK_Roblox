--!nonstrict
-- require(game.ServerScriptService.Server.ShibuyaGridMassingVerification).Run()
-- Saved-grid fixtures live only in a disposable ServerStorage folder.
local Verify={}
local Http=game:GetService("HttpService")
local SLAB,PITCH=1.5/0.28,5/0.28

function Verify.Run()
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest first")
	local module=require(script.Parent.ShibuyaGridMassing)
	local folder=Instance.new("Folder"); folder.Name="GridMassingVerificationTemporary"; folder.Parent=game.ServerStorage
	local ok,result=pcall(function()
		local function mask(predicate)
			local bits={}
			for i=1,20 do for j=1,20 do table.insert(bits,predicate(i,j) and "1" or "0") end end
			return table.concat(bits)
		end
		local full=mask(function() return true end)
		local function fixture(key,masks)
			local b=Instance.new("Model"); b.Name="BuildingAuto_"..key
			b:SetAttribute("ShibuyaSourceKey",key)
			local height=#masks*PITCH+SLAB
			b:SetAttribute("InteriorBBoxCFrame",CFrame.new(100,height/2,-200)*CFrame.Angles(0,0.41,0))
			b:SetAttribute("InteriorBBoxSize",Vector3.new(60,height,60))
			b:SetAttribute("InteriorGrid",Http:JSONEncode({cell=3,nx=20,nz=20,minX=-30,minZ=-30,
				floors=#masks,ground=PITCH-SLAB,clearUpper=PITCH-SLAB,occ=masks,occTight=masks}))
			b.Parent=folder
			return b
		end
		local function repeated(value) return {value,value,value,value,value} end
		fixture("rectangle",repeated(full))
		fixture("diagonal",repeated(mask(function(i,j) return i+j<=21 end)))
		fixture("large_L",repeated(mask(function(i,j) return i<=10 or j<=8 end)))
		fixture("short_majority",{full,full,mask(function(i) return i<=17 end)})
		fixture("partial_half",repeated(mask(function(i) return i<=10 end)))
		fixture("disconnected",repeated(mask(function(i) return i<=5 or i>=16 end)))
		fixture("courtyard",repeated(mask(function(i,j) return not (i>=8 and i<=12 and j>=8 and j<=12) end)))
		fixture("unsupported_middle",{full,full,mask(function(i) return i<=10 end),full,full})
		fixture("tiny_island",repeated(mask(function(i,j) return i<=18 or (i==20 and j==10) end)))
		fixture("tiny_hole",repeated(mask(function(i,j) return not (i==10 and j==10) end)))
		fixture("slender_second_body",repeated(mask(function(i,j) return i<=18 or (i==20 and j>=8 and j<=13) end)))
		fixture("small_courtyard",repeated(mask(function(i,j) return not (i>=9 and i<=10 and j>=9 and j<=10) end)))
		local protected=fixture("protected",repeated(full)); protected.Name="BuildingSmooth_protected"
		local report=module.Preview(folder)
		local accepted={}
		for _,plan in report.plans do
			accepted[plan.key]=plan
			assert(plan.oldModel.Parent==folder and plan.height>0 and #plan.tiers>=1,"Invalid compatible plan")
			assert(math.abs(plan.sourceBaseY)<0.01,"Source base moved")
		end
		assert(#report.plans==6,"Expected six supported fixtures: "..Http:JSONEncode(report.rejected))
		assert(accepted.rectangle and #accepted.rectangle.points==4,"Complete box was not simplified")
		assert(accepted.diagonal and #accepted.diagonal.points<=6,"Staircase diagonal was retained")
		local diagonal=false
		for i,p in accepted.diagonal.points do
			local edge=accepted.diagonal.points[i%#accepted.diagonal.points+1]-p
			if math.abs(edge.X)>10 and math.abs(edge.Y)>10 then diagonal=true end
		end
		assert(diagonal,"Diagonal footprint has no real straight angled edge")
		assert(accepted.large_L and #accepted.large_L.points>=6,"Significant L inlet was boxed over")
		assert(math.abs(accepted.large_L.area-2520)<0.01,"L inlet area changed")
		assert(accepted.short_majority,"Two-of-three strong short-building support rejected")
		assert(accepted.tiny_island and #accepted.tiny_island.points==4,"Bounded detached cell was not removed")
		assert(math.abs(accepted.tiny_island.gridEvidence.removedIslandArea-45)<0.01,"Detached-cell area was not reported")
		assert(accepted.tiny_hole and #accepted.tiny_hole.points==4,"Bounded single-cell hole was not repaired")
		assert(math.abs(accepted.tiny_hole.gridEvidence.filledHoleArea-45)<0.01,"Filled-hole area was not reported")
		for _,key in {"partial_half","disconnected","courtyard","unsupported_middle","protected","slender_second_body","small_courtyard"} do
			assert(not accepted[key],"Unsafe grid massing accepted: "..key)
		end
		assert(protected.Parent==folder and #folder:GetChildren()==13,"Preview changed source models")
		return {accepted=#report.plans,rejected=#report.rejectedModels,protected=report.protected}
	end)
	folder:Destroy()
	assert(ok,result)
	print("GRID_MASSING_VERIFIED",Http:JSONEncode(result))
	return result
end

return Verify
