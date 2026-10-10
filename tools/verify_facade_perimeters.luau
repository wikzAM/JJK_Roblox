-- Edit-only semantic checks of installed drafts and live trial.
local R=game.ServerStorage.FacadePerimeterRuntime
local Names=require(R.GroundFacadeNames)
local C=require(R.GroundFacadeCatalog)
local K=require(R.GroundFacadeKit)
local F=require(R.GroundFacadeFrontage)
local H=game:GetService("HttpService")
assert(#Names.Labelings>=50 and #Names.Stems>=20)
local unique={};for _,l in Names.Labelings do assert(not unique[l.japanese]);unique[l.japanese]=true end
local nameCases=0
for _,feature in {"coffee","ramen","laundry","bicycle","florist","clinic","bookshop","soba","bathhouse","house"} do
	for seed=1,20 do
		local a=Names.Generate("retail",seed,{tag=feature});local b=Names.Generate("retail",seed,{tag=feature})
		assert(a.brand==b.brand and a.labelId==b.labelId and a.stemId==b.stemId)
		nameCases+=1
	end
end
for feature,fixed in Names.FixedChains do for seed=1,100 do assert(Names.Generate("chains",seed,{feature=feature}).brand==fixed.brand);nameCases+=1 end end
assert(not pcall(function()Names.Generate("food",1,{labelId="invalid"})end))
assert(not pcall(function()Names.Generate("food",1,{stemId="invalid"})end))
local a=K.Build(nil,"46_Laundry",CFrame.identity,{seed=90,nameSeed=1})
local b=K.Build(nil,"46_Laundry",CFrame.identity,{seed=90,nameSeed=99})
local function textOf(model) local values={};for _,p in model:GetDescendants() do if p:IsA("TextLabel") then table.insert(values,p.Text) end end;return table.concat(values,"|") end
assert(textOf(a)~=textOf(b),"Name seed did not vary identity")
local pa,pb={},{};for _,p in a:GetDescendants() do if p:IsA("BasePart") then table.insert(pa,p) end end;for _,p in b:GetDescendants() do if p:IsA("BasePart") then table.insert(pb,p) end end
assert(#pa==#pb);for i,p in pa do assert(p.CFrame==pb[i].CFrame and p.Size==pb[i].Size,"Name seed changed physical architecture") end;a:Destroy();b:Destroy()
local quietCases=0
for _,spec in C.TYPES do for _,role in {"window","blind"} do
	local l=K.Layout(spec.id,{role=role,height=spec.height or 12.5,seed=100})
	assert(#(l.portals or (l.door and {l.door} or {}))==0,"Quiet role has portal")
	for _,p in l.parts do assert(not p.text or p.text=="","Quiet role has business sign");if role=="blind" then assert(p.kind~="glass","Blind wall contains glass") end end
	quietCases+=1
end end
local report=H:JSONDecode(game.ServerStorage.GroundFacadePilotManifest:GetAttribute("Report"))
local scene=F.Index(Vector3.new(-1627,98,388),650);local faces,entrances,parking,planters=0,0,0,0
local allOwned=0
for _,m in workspace.Buildings:GetChildren() do
	local root=m:FindFirstChild("GroundFacadePilot")
	if root then
		allOwned+=1;local _,strips=require(R.FacadeLayout).ForModel(m);local expected=0
		for _,s in strips do if s.storey==1 then expected+=1 end end
		local owned=H:JSONDecode(m:GetAttribute("GroundFacadeOwnedRuns"));local count=0;for _ in owned do count+=1 end
		assert(count==expected,"Ground perimeter has an uncovered exterior run")
		local palette=root:GetAttribute("Palette")
		for _,run in root:GetChildren() do if run:IsA("Model") then
			faces+=1;local public=run:GetAttribute("FrontageClass")
			for _,bay in run:GetChildren() do if bay:IsA("Model") and bay:GetAttribute("FacadePortals") then
				assert(bay:GetAttribute("FacadePalette")==palette,"Building palette diverged")
				local portals=H:JSONDecode(bay:GetAttribute("FacadePortals"))
				if public=="blind" or public=="window" then assert(#portals==0,"Quiet elevation has entrance") end
				for _,p in portals do
					assert(run:GetAttribute("RoadClass"),"Entrance without road proof");assert(run:GetAttribute("NeighborClearance")>=8,"Entrance in confined gap")
					entrances+=1
					if p.name=="parking" or p.name=="loading" then assert(F.OpenDepth(m,bay:GetPivot()*CFrame.new(p.x,0,0),p.width+.5,22),"Parking blocked by interior");parking+=1 end
				end
			end end
		end end
		for _,p in root:GetDescendants() do if p:IsA("BasePart") and p:GetAttribute("FacadeSupportBase") then
			assert(p:GetAttribute("FacadeSupportMode")=="grounded-assembly","Planter has unverified ground")
			assert(math.abs(p.Position.Y-p.Size.Y/2-p:GetAttribute("FacadeSupportGroundY")-.02)<.04,"Floating planter");planters+=1
		end end
	end
end
assert(allOwned==report.buildings and allOwned==3,"Glass trial escaped compact pilot")
local original=0;for p,v in _G.FacadePerimeterOriginal do assert(p.Parent and p.CFrame==v.cf and p.Size==v.size);original+=1 end
assert(#workspace.Buildings:GetChildren()==2227)
local roads=0;for _,p in workspace.Roads:GetDescendants() do if p:IsA("BasePart") then roads+=1 end end;assert(roads==1037)
return {passed=true,types=#C.TYPES,labelings=#Names.Labelings,stems=#Names.Stems,nameCases=nameCases,quietRoleCases=quietCases,buildings=allOwned,coveredRuns=faces,entrances=entrances,openParking=parking,groundedPlanters=planters,unchangedSourceParts=original,roadParts=roads,buildingCount=2227}
