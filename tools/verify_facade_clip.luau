-- Edit-only v8 audit. Source snapshot stays in Studio; no geometry export.
local H=game:GetService("HttpService")
local F=require(game.ServerStorage.FacadeClipRuntime.GroundFacadeFrontage)
local expected=H:JSONDecode(assert(game.ServerStorage:FindFirstChild("GroundFacadePilotManifest")):GetAttribute("Manifest"))
local expectedRuns=0;for _,row in expected do expectedRuns+=#row.faces end
assert(_G.ClipOriginal and next(_G.ClipOriginal),"Capture the original source snapshot before editing")
local out={buildings=0,runs=0,panes=0,exteriorParts=0,coverageRays=0,volumeChecks=0,blocked={},holes={},portals=0,stairs=0,planters=0,unchanged=0}
for _,m in workspace.Buildings:GetChildren() do
	local root=m:FindFirstChild("GroundFacadePilot")
	if not root then continue end
	out.buildings+=1
	assert(m:GetAttribute("StructuralOnly") and not m:GetAttribute("Landmark") and not m:GetAttribute("CrownInteresting"))
	local source={}
	for _,p in m:GetDescendants() do if p:IsA("BasePart") and p.CanQuery and p.Transparency<.95 and not p:IsDescendantOf(root) then table.insert(source,p) end end
	local overlap=OverlapParams.new();overlap.FilterType=Enum.RaycastFilterType.Include;overlap.FilterDescendantsInstances=source
	for _,run in root:GetChildren() do if run:IsA("Model") then
		out.runs+=1;local cf=run:GetAttribute("FacadeRunFrame");local w,h=run:GetAttribute("FacadeRunWidth"),run:GetAttribute("FacadeExpectedHeight")
		local portals={}
		for _,bay in run:GetChildren() do if bay:IsA("Model") and bay:GetAttribute("FacadePortals") then
			for _,p in H:JSONDecode(bay:GetAttribute("FacadePortals")) do
				out.portals+=1
				if p.name=="parking" or p.name=="loading" or p.name=="openShop" then
					local q=cf:PointToObjectSpace((bay:GetPivot()*CFrame.new(p.x,0,0)).Position)
					table.insert(portals,{x=q.X,width=p.width,height=p.height,y=p.y or 0})
					assert(F.OpenDepth(m,bay:GetPivot()*CFrame.new(p.x,0,0),p.width+.5,22),"Parking core obstruction")
				end
			end
		end end
		local rp=RaycastParams.new();rp.FilterType=Enum.RaycastFilterType.Include;rp.FilterDescendantsInstances={run}
		local n=math.max(2,math.ceil(w/2))
		for i=0,n do for _,y in {.25,h*.25,h*.5,h*.75,h-.1} do
			local x=-w/2+.1+(w-.2)*i/n;local open=false
			for _,p in portals do if math.abs(x-p.x)<p.width/2+.01 and y>p.y-.01 and y<p.y+p.height+.01 then open=true end end
			if not open then
				out.coverageRays+=1
				if not workspace:Raycast((cf*CFrame.new(x,y,-2)).Position,cf.ZVector*3,rp) then table.insert(out.holes,{id=m:GetAttribute("SourceSliceId"),piece=run:GetAttribute("RunPiece"),run=run:GetAttribute("RunIndex"),x=x,y=y}) end
			end
		end end
		for _,p in run:GetDescendants() do if p:IsA("BasePart") then
			if p:GetAttribute("FacadeLayer")=="exterior" then
				out.exteriorParts+=1
				for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
					local q=cf:PointToObjectSpace((p.CFrame*CFrame.new(p.Size*Vector3.new(x,y,z)/2)).Position)
					assert(q.Z<=.452,"Exterior inset: "..p:GetFullName())
				end end end
			end
			if p:HasTag("GlassPane") then
				out.panes+=1;out.volumeChecks+=1
				for _,hit in workspace:GetPartsInPart(p,overlap) do table.insert(out.blocked,{pane=p:GetFullName(),source=hit:GetFullName()}) end
				local backing=p:FindFirstChild("InteriorWindowBacking");assert(backing and not backing.CanQuery and not backing.CanCollide and backing:GetAttribute("GlassAttachedOverlay"))
			elseif p.Name=="EntryApproachStep" then
				out.stairs+=1
				for _,x in {-p.Size.X/2,0,p.Size.X/2} do for _,z in {-p.Size.Z/2,0,p.Size.Z/2} do local ground=F.Ground(p.CFrame,x,z);assert(ground and p.Position.Y-p.Size.Y/2<=ground+.12,"Floating stair") end end
			elseif p:GetAttribute("FacadeSupportBase") then
				out.planters+=1;assert(math.abs(p.Position.Y-p.Size.Y/2-p:GetAttribute("FacadeSupportGroundY")-.02)<.05,"Floating planter")
			end
		end end
	end end
	task.wait()
end
for p,v in _G.ClipOriginal or {} do assert(p.Parent and p.CFrame==v[1] and p.Size==v[2] and p.Color==v[3],"Original changed");out.unchanged+=1;if out.unchanged%1000==0 then task.wait() end end
_G.ClipAudit=out
assert(out.buildings==#expected and out.runs==expectedRuns,"Incomplete regional perimeter")
assert(#out.holes==0,"A perimeter sample is uncovered")
assert(#out.blocked==0,"Glass intersects original structure")
return out
