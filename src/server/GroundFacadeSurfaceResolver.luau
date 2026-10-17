--!nonstrict
-- Edit-only shared-surface ownership. Source slices can repeat the same boundary
-- at different heights. Clip only generated facade parts, never source structure.
local S={VERSION=1}
local OWNER="2026-10-08-ground-pilot"
local EPS=.025
local function isBayPreview(p)
	return p:GetAttribute("FacadeBayInteriorPart")==true
		and p:GetAttribute("FacadeLayer")=="interior" and p:GetAttribute("FacadePieceKind")=="preview"
end
local function flatPane(p)
	local V=require(game.ReplicatedStorage.Shared.GlassVisual)
	V.SetInteriorView(p,false)
	local intact=(p:GetAttribute("GlassState") or 1)<=2
	for _,back in p:GetChildren() do if back:IsA("BasePart") and back.Name=="InteriorWindowBacking" then
		local baseline=back:GetAttribute("InteriorBeforeTransparency") or 0
		back.Transparency=intact and baseline or 1
		back:SetAttribute("GlassFilmTransparency",back:GetAttribute("InteriorBeforeFilmTransparency") or baseline)
	end end
end
-- Trimming a run can remove glazing or change its width. Replan ALL bays in
-- that root, rather than keeping stale recipes on the untouched neighboring run.
-- Exact old previews and recipe attributes remain recoverable in this archive.
local function invalidateBayRecipes(root,archive,stagedOriginals)
	local needs=root:GetAttribute("FacadeBayInteriorsVersion")~=nil or root.Parent:GetAttribute("FacadeBayInteriorsVersion")~=nil
	if not needs then for _,bay in root:GetDescendants() do
		if bay:IsA("Model") and bay:GetAttribute("FacadeType") and (bay:GetAttribute("FacadeBayInteriorPlan") or bay:HasTag("FacadeInteriorBay") or bay:FindFirstChild("BayInterior")) then needs=true break end
	end end
	if not needs then return 0,0 end
	local saved=Instance.new("Folder");saved.Name="BayInteriorInvalidation"
	saved:SetAttribute("Kind","BayInteriorInvalidation")
	saved:SetAttribute("RootCompletionVersion",root:GetAttribute("FacadeBayInteriorsVersion"))
	saved:SetAttribute("ModelCompletionVersion",root.Parent:GetAttribute("FacadeBayInteriorsVersion"))
	local ref=Instance.new("ObjectValue");ref.Name="Root";ref.Value=root;ref.Parent=saved
	saved.Parent=archive
	local count,previews=0,0
	for _,bay in root:GetDescendants() do if bay:IsA("Model") and bay:GetAttribute("FacadeType") then
		local snapshot=Instance.new("Folder");snapshot.Name="BayRecipe"
		local target=Instance.new("ObjectValue");target.Name="Bay";target.Value=bay;target.Parent=snapshot
		snapshot:SetAttribute("WasTagged",bay:HasTag("FacadeInteriorBay"))
		for key,value in bay:GetAttributes() do if key:sub(1,17)=="FacadeBayInterior" then
			snapshot:SetAttribute(key,value);bay:SetAttribute(key,nil)
		end end
		snapshot.Parent=saved
		local preview=bay:FindFirstChild("BayInterior")
		if preview then
			assert(preview:IsA("Folder") and preview:GetAttribute("EditPreview")==true
				and preview:GetAttribute("FacadeBayInteriorVersion")==2,"Unexpected bay preview; preserve archive")
			preview.Parent=snapshot;previews+=1
		end
		bay:RemoveTag("FacadeInteriorBay")
		for _,pane in bay:GetChildren() do
			if pane:IsA("BasePart") and pane:HasTag("GlassPane") and not stagedOriginals[pane] then flatPane(pane) end
		end
		count+=1
	end end
	root:SetAttribute("FacadeBayInteriorsVersion",nil);root.Parent:SetAttribute("FacadeBayInteriorsVersion",nil)
	return count,previews
end
local function bounds(p,cf)
	local q=cf:ToObjectSpace(p.CFrame);local s=p.Size
	local half=(Vector3.new(math.abs(q.XVector.X),math.abs(q.XVector.Y),math.abs(q.XVector.Z))*s.X
		+Vector3.new(math.abs(q.YVector.X),math.abs(q.YVector.Y),math.abs(q.YVector.Z))*s.Y
		+Vector3.new(math.abs(q.ZVector.X),math.abs(q.ZVector.Y),math.abs(q.ZVector.Z))*s.Z)/2
	return {q.X-half.X,q.X+half.X,q.Y-half.Y,q.Y+half.Y},q
end
local function intersect(a,b)
	return math.min(a[2],b[2])-math.max(a[1],b[1])>.001 and math.min(a[4],b[4])-math.max(a[3],b[3])>.001
end
function S.Subtract(a,b)
	if not intersect(a,b) then return {a} end
	local x0,x1=math.max(a[1],b[1]),math.min(a[2],b[2])
	local y0,y1=math.max(a[3],b[3]),math.min(a[4],b[4]);local out={}
	for _,r in {{a[1],x0,a[3],a[4]},{x1,a[2],a[3],a[4]},{x0,x1,a[3],y0},{x0,x1,y1,a[4]}} do
		if r[2]-r[1]>=.05 and r[4]-r[3]>=.05 then table.insert(out,r) end
	end
	return out
end
local function priority(a,b)
	if a.portals~=b.portals then return a.portals>b.portals end
	if a.panes~=b.panes then return a.panes>b.panes end
	if math.abs(a.cf.Y-b.cf.Y)>.05 then return a.cf.Y<b.cf.Y end
	return a.key<b.key
end
function S.Plan(buildings)
	local H=game:GetService("HttpService");local runs,grid={},{}
	for _,m in buildings:GetChildren() do
		local root=m:FindFirstChild("GroundFacadePilot")
		if root and root:GetAttribute("Owner")==OWNER then for _,r in root:GetChildren() do
			local cf,w,h=r:GetAttribute("FacadeRunFrame"),r:GetAttribute("FacadeRunWidth"),r:GetAttribute("FacadeExpectedHeight")
			if not cf or not w or not h then continue end
			local row={run=r,cf=cf,w=w,h=h,id=#runs+1,panes=0,portals=0,low=0,masks={},key=m.Name.."/"..r:GetAttribute("RunPiece").."/"..r:GetAttribute("RunIndex")}
			for _,p in r:GetDescendants() do
				if p:IsA("BasePart") and not isBayPreview(p) then local b=bounds(p,cf);row.low=math.min(row.low,b[3]);if p:HasTag("GlassPane") then row.panes+=1 end
				elseif p:IsA("Model") then row.portals+=#H:JSONDecode(p:GetAttribute("FacadePortals") or "[]") end
			end
			table.insert(runs,row)
			local a,b=cf.Position-cf.XVector*w/2,cf.Position+cf.XVector*w/2
			for x=math.floor(math.min(a.X,b.X)/64),math.floor(math.max(a.X,b.X)/64) do for z=math.floor(math.min(a.Z,b.Z)/64),math.floor(math.max(a.Z,b.Z)/64) do
				local key=x.."/"..z;grid[key]=grid[key] or {};table.insert(grid[key],row)
			end end
		end end
	end
	local seen,pairs={},0
	for _,bucket in grid do for i=1,#bucket do for j=i+1,#bucket do
		local a,b=bucket[i],bucket[j];local key=math.min(a.id,b.id).."/"..math.max(a.id,b.id)
		if seen[key] then continue end;seen[key]=true
		if a.run.Parent==b.run.Parent or a.cf.ZVector:Dot(b.cf.ZVector)<.99999 then continue end
		local q=a.cf:PointToObjectSpace(b.cf.Position)
		if math.abs(q.Z)>.04 or not intersect({-a.w/2,a.w/2,0,a.h},{q.X-b.w/2,q.X+b.w/2,q.Y,q.Y+b.h}) then continue end
		local winner,loser=a,b;if priority(b,a) then winner,loser=b,a end
		local at=loser.cf:PointToObjectSpace(winner.cf.Position)
		table.insert(loser.masks,{at.X-winner.w/2-EPS,at.X+winner.w/2+EPS,at.Y+winner.low-EPS,at.Y+winner.h+EPS})
		pairs+=1
	end end end
	local affected={};for _,r in runs do if #r.masks>0 then table.insert(affected,r) end end
	table.sort(affected,function(a,b)return a.key<b.key end)
	return {runs=affected,pairs=pairs,totalRuns=#runs}
end
local function clipRects(p,row,limit)
	local b,q=bounds(p,row.cf);local rects={b}
	if limit then
		b={math.max(b[1],limit[1]),math.min(b[2],limit[2]),math.max(b[3],limit[3]),math.min(b[4],limit[4])}
		if b[2]-b[1]<.05 or b[4]-b[3]<.05 then return {} end;rects={b}
	end
	for _,mask in row.masks do local nextRects={} for _,r in rects do for _,piece in S.Subtract(r,mask) do table.insert(nextRects,piece) end end;rects=nextRects end
	return rects,q
end
local function fragments(p,row,limit)
	local rects,q=clipRects(p,row,limit);local out={}
	-- Only aligned native boxes are split. All current duplicate surfaces satisfy
	-- this contract; preflight rejects an unsupported partial cut without mutation.
	local axes={q.XVector,q.YVector,q.ZVector}
	local ix,iy
	for i,v in axes do if math.abs(v.X)>.99999 then ix=i end;if math.abs(v.Y)>.99999 then iy=i end end
	assert(#rects==0 or (ix and iy and p:IsA("Part") and p.Shape==Enum.PartType.Block),"Unsupported shared-surface fragment: "..p:GetFullName())
	local original=bounds(p,row.cf)
	for i,r in rects do
		local clone=p:Clone()
		for _,child in clone:GetChildren() do if child:IsA("BasePart") then child:Destroy() end end
		local size={p.Size.X,p.Size.Y,p.Size.Z};size[ix]=r[2]-r[1];size[iy]=r[4]-r[3]
		clone.Size=Vector3.new(table.unpack(size))
		clone.CFrame=p.CFrame+row.cf:VectorToWorldSpace(Vector3.new((r[1]+r[2]-original[1]-original[2])/2,(r[3]+r[4]-original[3]-original[4])/2,0))
		clone:SetAttribute("FacadeSharedSurfaceVersion",S.VERSION)
		if clone:HasTag("GlassPane") then clone:SetAttribute("GlassPaneId",(p:GetAttribute("GlassPaneId") or p.Name).."/surface"..i) end
		for _,child in p:GetChildren() do if child:IsA("BasePart") then for _,c in fragments(child,row,r) do c.Parent=clone end end end
		table.insert(out,clone)
	end
	return out
end
function S.ApplyRun(row,archive)
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	assert(row.run:IsDescendantOf(workspace.Buildings) and row.run.Parent:GetAttribute("Owner")==OWNER,"Unowned run")
	assert(archive:IsDescendantOf(game.ServerStorage) and archive:GetAttribute("Owner")=="facade-surface-repair-v1","Unowned archive")
	local staged={};local ok,err=pcall(function()
		for _,p in row.run:GetDescendants() do if p:IsA("BasePart") and not isBayPreview(p) and not p.Parent:IsA("BasePart") then
			local b=bounds(p,row.cf);local touched=false
			for _,mask in row.masks do if intersect(b,mask) then touched=true break end end
			if touched then table.insert(staged,{original=p,parent=p.Parent,parts=fragments(p,row)}) end
		end end
		-- Validate previews before clearing recipes or moving live geometry.
		if #staged>0 then for _,p in row.run.Parent:GetDescendants() do
			if p.Name=="BayInterior" and p.Parent:IsA("Model") and p.Parent:GetAttribute("FacadeType") then
				assert(p:IsA("Folder") and p:GetAttribute("EditPreview")==true and p:GetAttribute("FacadeBayInteriorVersion")==2,"Unexpected bay preview")
			end
		end end
	end)
	if not ok then for _,s in staged do for _,p in s.parts do p:Destroy() end end;error(err) end
	if #staged==0 then return {originals=0,fragments=0,invalidatedBays=0,archivedPreviews=0} end
	local root=row.run.Parent
	local stagedOriginals={};for _,s in staged do stagedOriginals[s.original]=true end
	local invalidated,previews=invalidateBayRecipes(root,archive,stagedOriginals)
	local removed,added=0,0
	for _,s in staged do
		local holder=Instance.new("Folder");holder.Name="OriginalPart";holder.Parent=archive
		local target=Instance.new("ObjectValue");target.Name="OriginalParent";target.Value=s.parent;target.Parent=holder
		for _,p in s.parts do
			-- Clones were staged before invalidation; normalize only replacements,
			-- preserving the exact pre-trim original pane inside its backup holder.
			if p:HasTag("GlassPane") then flatPane(p) end
			p.Parent=s.parent;added+=1
			local reference=Instance.new("ObjectValue");reference.Name="Replacement";reference.Value=p;reference.Parent=holder
		end
		s.original.Parent=holder;removed+=1
	end
	row.run:SetAttribute("FacadeSharedSurfaceVersion",S.VERSION)
	row.run:SetAttribute("FacadeSharedSurfaceMasks",game:GetService("HttpService"):JSONEncode(row.masks))
	return {originals=removed,fragments=added,invalidatedBays=invalidated,archivedPreviews=previews}
end
function S.ApplyInstalled()
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	local plan=S.Plan(workspace.Buildings)
	local archive=Instance.new("Folder");archive.Name="FacadeSharedSurfaceBackup_"..game:GetService("HttpService"):GenerateGUID(false)
	archive:SetAttribute("Owner","facade-surface-repair-v1");archive.Parent=game.ServerStorage
	local out={pairs=plan.pairs,runs=#plan.runs,originals=0,fragments=0,archive=archive.Name}
	for _,row in plan.runs do
		local r=S.ApplyRun(row,archive);out.originals+=r.originals;out.fragments+=r.fragments;task.wait()
	end
	return out
end
function S.VerifyInstalled()
	local H=game:GetService("HttpService");local out={runs=0,parts=0,remaining=0}
	for _,m in workspace.Buildings:GetChildren() do
		local root=m:FindFirstChild("GroundFacadePilot")
		if root and root:GetAttribute("Owner")==OWNER then for _,run in root:GetChildren() do
			local raw=run:GetAttribute("FacadeSharedSurfaceMasks")
			if raw then
				out.runs+=1;local masks=H:JSONDecode(raw);local cf=run:GetAttribute("FacadeRunFrame")
				for _,p in run:GetDescendants() do if p:IsA("BasePart") and not isBayPreview(p) then
					out.parts+=1;local b=bounds(p,cf)
					for _,mask in masks do if intersect(b,mask) then out.remaining+=1 break end end
				end end
			end
		end end
		task.wait()
	end
	return out
end
function S.Restore(archive)
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	assert(archive:IsDescendantOf(game.ServerStorage) and archive:GetAttribute("Owner")=="facade-surface-repair-v1","Unowned archive")
	local restored=0;local runs={};local invalidatedRoots={}
	for _,holder in archive:GetChildren() do
		-- Room snapshots remain archived. Restored facade geometry must pass the
		-- normal fresh preparation/SAT pipeline before room recipes are enabled.
		if holder:GetAttribute("Kind")=="BayInteriorInvalidation" then continue end
		local target=holder:FindFirstChild("OriginalParent")
		assert(target and target.Value and target.Value:IsDescendantOf(workspace.Buildings),"Original parent missing; preserve archive")
		local run=target.Value
		while run and not run:GetAttribute("FacadeRunFrame") do run=run.Parent end
		if run then
			runs[run]=true
			local root=run.Parent
			if not invalidatedRoots[root] then invalidateBayRecipes(root,archive,{});invalidatedRoots[root]=true end
		end
		for _,ref in holder:GetChildren() do if ref:IsA("ObjectValue") and ref.Name=="Replacement" and ref.Value then ref.Value:Destroy() end end
		for _,p in holder:GetChildren() do if p:IsA("BasePart") then
			if p:HasTag("GlassPane") then flatPane(p) end
			p.Parent=target.Value;restored+=1
		end end
		task.wait()
	end
	for run in runs do run:SetAttribute("FacadeSharedSurfaceVersion",nil);run:SetAttribute("FacadeSharedSurfaceMasks",nil) end
	return restored
end
return S
