local Registry=require(script.Parent.GroundFacadeRegistry)
-- Edit-only preservation of owner-selected station and elevated walkway geometry.
-- Originals stay in ServerStorage; Rebuild creates a separate infrastructure layer.
local Archive={VERSION=1}
local H=game:GetService("HttpService")
local Storage=game:GetService("ServerStorage")
local function editOnly() assert(not game:GetService("RunService"):IsRunning(),"Stop Play first") end
local function folder(parent,name)
	local f=parent:FindFirstChild(name) or Instance.new("Folder");f.Name=name;f.Parent=parent;return f
end
function Archive.Capture(selection)
	editOnly();assert(type(selection)=="table" and #selection>0 and #selection<=64,"Explicit station selection required")
	local models,seen={},{}
	for _,m in selection do
		assert(m:IsA("Model") and m.Parent==workspace.Buildings,"Select complete city models only")
		if not seen[m] then seen[m]=true;table.insert(models,m) end
	end
	local root=folder(Storage,"StationInfrastructureArchive")
	local backup=Instance.new("Folder");backup.Name="Selected_"..H:GenerateGUID(false);backup:SetAttribute("CreatedUTC",os.date("!%Y-%m-%dT%H:%M:%SZ"));backup.Parent=root
	local old=Storage:FindFirstChild("GroundFacadePilotManifest");if old then old:Clone().Parent=backup end
	local ids,manifest={},{}
	for _,m in models do
		local parts=0;for _,p in m:GetDescendants() do if p:IsA("BasePart") then parts+=1 end end
		local id=m:GetAttribute("SourceSliceId");if id then ids[id]=true end
		table.insert(manifest,{name=m.Name,id=id,originalParent="Workspace.Buildings",parts=parts})
	end
	backup:SetAttribute("Manifest",H:JSONEncode(manifest));backup:SetAttribute("Purpose","Station and city walkway reference geometry; excluded from ordinary facades")
	-- Move, rather than discard or reconstruct, every selected original model.
	for _,m in models do m.Parent=backup;task.wait() end
	if old then
		local rows={};for _,r in H:JSONDecode(Registry.Read(old,"Manifest")) do if not ids[r.id] then table.insert(rows,r) end end
		local report=H:JSONDecode(Registry.Read(old,"Report"));local rr={};local parts,panes,planters=0,0,0
		for _,r in report.rows do if not ids[r.id] then table.insert(rr,r);parts+=r.parts or 0;panes+=r.panes or 0;planters+=r.supportedPlanters or 0 end end
		report.rows=rr;report.buildings=#rows;report.parts=parts;report.panes=panes;report.supportedPlanters=planters
		Registry.Write(old,"Manifest",H:JSONEncode(rows));Registry.Write(old,"Report",H:JSONEncode(report))
	end
	backup:SetAttribute("State","preserved");game:GetService("ChangeHistoryService"):SetWaypoint("Preserve selected station infrastructure")
	return backup,manifest
end
function Archive.Rebuild(backup)
	editOnly();assert(backup and backup.Parent==Storage:FindFirstChild("StationInfrastructureArchive") and backup:GetAttribute("State")=="preserved","Choose a preserved station archive")
	local parent=folder(workspace,"StationInfrastructure")
	local old=parent:FindFirstChild(backup.Name);assert(not old,"Already rebuilt; remove that owned reconstruction before repeating")
	local result=Instance.new("Folder");result.Name=backup.Name;result:SetAttribute("SourceArchive",backup.Name);result.Parent=parent
	for _,m in backup:GetChildren() do if m:IsA("Model") then
		local clone=m:Clone();local facade=clone:FindFirstChild("GroundFacadePilot");if facade then facade:Destroy() end
		clone:SetAttribute("GroundFacadeOwnedRuns",nil);clone:SetAttribute("GroundFacadeMaxOutset",nil)
		clone:SetAttribute("StationInfrastructure",true);clone:SetAttribute("FacadeExcluded",true);clone:AddTag("StationInfrastructure")
		clone.Parent=result;task.wait()
	end end
	return result
end
return Archive
