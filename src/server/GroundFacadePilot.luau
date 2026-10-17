-- Edit-only complete-perimeter trial; source structure is never changed.
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Kit=require(Shared.GroundFacadeKit)
local Catalog=require(Shared.GroundFacadeCatalog)
local Frontage=require(script.Parent.GroundFacadeFrontage)
local Placement=require(script.Parent.GroundFacadePlacement)
local GlassDamage=require(script.Parent.GlassDamageService)
local Http=game:GetService("HttpService")
local Registry=require(script.Parent.GroundFacadeRegistry)
local Pilot={}
local OWNER="2026-10-08-ground-pilot" -- GlassGeometry allow-list contract.
local function find(id)
	for _,m in workspace.Buildings:GetChildren() do if (m:GetAttribute("SourceSliceId") or m:GetAttribute("FacadeSourceId"))==id then return m end end
	error("Missing pilot building: "..id)
end
local function concrete(parent,name,cf,size,palette)
	local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=cf;p.Anchored=true;p.CanTouch=false
	p.Material=Enum.Material.Concrete;p.Color=Catalog.PALETTES[palette].wall;p:AddTag("NoCSG");p.Parent=parent;return p
end
local function supportedProps(root,palette,gap)
	local count=0
	for _,bay in root:GetDescendants() do if bay:IsA("Model") and bay:GetAttribute("FacadeType") then
		local groups={}
		for _,p in bay:GetDescendants() do if p:IsA("BasePart") and p:GetAttribute("FacadeSupportGroup") then
			local key=p:GetAttribute("FacadeSupportGroup");groups[key]=groups[key] or {parts={}}
			table.insert(groups[key].parts,p);if p:GetAttribute("FacadeSupportBase") then groups[key].base=p end
		end end
		for _,g in groups do
			local base=assert(g.base,"Support group lacks base");local bottom=base.Position.Y-base.Size.Y/2
			local high,low=-math.huge,math.huge
			for _,x in {-base.Size.X/2,base.Size.X/2} do for _,z in {-base.Size.Z/2,base.Size.Z/2} do
				local y=Frontage.Ground(base.CFrame,x,z);if y then high=math.max(high,y);low=math.min(low,y) end
			end end
			if high==-math.huge then
				if gap>.05 then concrete(root,"PlanterSupportPlinth",base.CFrame*CFrame.new(0,-base.Size.Y/2-gap/2,0),Vector3.new(base.Size.X,gap,base.Size.Z),palette) end
				base:SetAttribute("FacadeSupportMode","footing-plinth")
			else
				for _,p in g.parts do p.CFrame+=Vector3.yAxis*(high+.02-bottom) end
				if high-low>.08 then concrete(root,"PlanterTerrainPlinth",base.CFrame*CFrame.new(0,-base.Size.Y/2-(high-low)/2,0),Vector3.new(base.Size.X,high-low,base.Size.Z),palette) end
				base:SetAttribute("FacadeSupportGroundY",high);base:SetAttribute("FacadeSupportMode","grounded-assembly")
				assert(math.abs(base.Position.Y-base.Size.Y/2-high-.02)<.03,"Floating planter")
			end
			count+=1
		end
	end end
	return count
end
-- Read-only driveway plan shared by bay validation and construction. The final
-- toe can differ from the doorway sample; validate the exact wedge before any
-- portal is accepted, rather than failing the complete building while building.
local function drivewayGeometry(cf,p)
	local entryGround=Frontage.Ground(cf,p.x,-2)
	if not entryGround then return nil,"Driveway entry ground unknown" end
	local rise=math.max(0,cf.Y-entryGround)
	if rise>(Frontage.MAX_VEHICLE_RISE or 4) then return nil,"Entry rise exceeds bounded approach" end
	if rise<=.2 or (p.y or 0)>=.1 then return {needed=false} end
	local length=math.max(4,rise*5)
	local toe=math.huge
	for _,x in {p.x-p.width*.45,p.x,p.x+p.width*.45} do
		local ground=Frontage.Ground(cf,x,-length)
		if not ground then return nil,"Driveway toe ground unknown" end
		toe=math.min(toe,ground)
	end
	if toe>cf.Y+.2 then return nil,"Driveway toe rises above entry" end
	rise=math.max(.2,cf.Y-toe)
	if rise>(Frontage.MAX_VEHICLE_RISE or 4) or rise/length>.25 then return nil,"Oversized vehicle ramp rejected" end
	local ground=math.huge
	for _,x in {p.x-p.width/2,p.x,p.x+p.width/2} do for _,z in {-length,-length/2,0} do
		local y=Frontage.Ground(cf,x,z)
		if not y then return nil,"Driveway support ground unknown" end
		ground=math.min(ground,y)
	end end
	local thickness=math.max(.2,cf.Y-rise-ground+.2)
	return {needed=true,rise=rise,length=length,toe=toe,thickness=thickness}
end
local function safePortal(scene,m,cf,p,gap)
	local car=p.name=="parking" or p.name=="loading"
	local reach=car and 20 or math.max(6,math.ceil(gap/.5)*.8+2)
	if gap>Frontage.MAX_ENTRY_RISE then return false,"Entry rise exceeds bounded approach" end
	local low,high=math.huge,-math.huge
	for _,x in {p.x-p.width*.4,p.x,p.x+p.width*.4} do
		for d=2,reach,1 do
			if Frontage.Occupied(scene,(cf*CFrame.new(x,2,-d)).Position,nil) then return false,"Approach intersects a building" end
			local ground=Frontage.Ground(cf,x,-d)
			if not ground then return false,"Approach ground unknown" end
			low=math.min(low,ground);high=math.max(high,ground)
		end
	end
	local allowedRange=car and 3 or Frontage.MAX_FRONT_GROUND_RANGE
	if cf.Y-low>Frontage.MAX_ENTRY_RISE or high-low>allowedRange or high>cf.Y+.2 then return false,"Approach exceeds elevation limits" end
	if car then
		local driveway,why=drivewayGeometry(cf,p)
		if not driveway then return false,why end
	end
	if car or p.name=="openShop" then
		return Frontage.OpenDepth(m,cf*CFrame.new(p.x,0,0),p.width+.5,22)
	end
	return true,"Clear approach"
end
local function validateBays(scene,m,cf,width,key,profile,opts,gap,vetoes)
	local cursor=-width/2
	for i,b in Kit.PlanRun(width,key,profile,opts) do
		local bcf=cf*CFrame.new(cursor+b.width/2,0,0)
		local blocked,blocker=false,nil
		if not b.infill and b.role~="blind" then blocked,blocker=Placement.NeighborBlocked(m,scene,bcf,b,opts) end
		if blocked then
			opts.bayRoles[i]="blind";table.insert(vetoes,{bay=i,type=b.id,reason="Neighbor geometry covers opening",blocker=blocker})
		elseif not b.infill and b.role=="entrance" then
			local o=table.clone(opts);o.width=b.width;o.seed=b.seed;o.role=b.role;o.mirror=b.seed%2==0
			local l=Kit.Layout(b.id,o)
			for _,p in l.portals or (l.door and {l.door} or {}) do
				local clear,why=safePortal(scene,m,bcf,p,gap)
				if not clear then opts.bayRoles[i]="window";table.insert(vetoes,{bay=i,type=b.id,reason=why}) end
			end
		end
		cursor+=b.width
	end
end
local function build(row,scene)
	local m=find(row.id);assert(not m:GetAttribute("CrownInteresting") and not m:HasTag("Landmark") and not m:GetAttribute("Landmark"),"Landmark excluded")
	assert(m:GetAttribute("StructuralOnly")==true,"Trial requires an ordinary generated building")
	local root=Instance.new("Folder");root.Name="GroundFacadePilot";root:SetAttribute("Owner",OWNER);root:SetAttribute("PerimeterRevision",9);root:SetAttribute("Palette",row.palette)
	local owned={};local r={id=row.id,palette=row.palette,faces={},parts=0,panes=0,supportedPlanters=0};local maxGap=0
	local okay,err=pcall(function()
	for _,f in row.faces do
		local cf=CFrame.new(table.unpack(f.frame));local width,h=f.width,f.height
		-- Owner explicitly chose the ordinary building nearer 109. Actual landmark
		-- metadata/structure checks replace the old blanket 1,200-stud exclusion.
		local key=row.id.."/"..f.piece.."/"..f.run;local gap=f.groundGap or 0;maxGap=math.max(maxGap,gap)
		local profile=f.class=="front" and (f.profile or "tokyo") or f.class
		local opts={height=h,targetWidth=28,palette=row.palette,facadeType=f.type,nameSeed=row.nameSeed,ads="normal",allowEntrance=f.class=="front",sitePiece=f.piece,siteRun=f.run,bayRoles=table.clone(f.bayRoles or {})}
		local holder,bays;local vetoes={};local portals=0
		local sourceCF=cf;local outset=0;local fitReason="Opaque/narrow infill"
		if h>=10.5 and h<=24 and width>=2 and width<=1000 then
			local fit,why=Placement.Fit(m,scene,cf,width,key,profile,opts)
			if not fit then
				profile="blind";opts.facadeType=nil;opts.allowEntrance=false;fitReason=why
			else
				outset=fit;fitReason=why;cf=cf*CFrame.new(0,0,-outset)
				local ground=Frontage.Ground(cf,0,-2);gap=ground and math.max(0,cf.Y-ground) or gap
			end
		end
		if h<10.5 or h>24 or width<2 or width>1000 then
			holder=Instance.new("Model");holder.Name="GroundFacadeRun_blind";holder.WorldPivot=cf;holder.Parent=root
			concrete(holder,"NarrowPerimeterInfill",cf*CFrame.new(0,h/2,0),Vector3.new(width,h,.7),row.palette);bays={{infill=true,width=width,role="blind"}};profile="blind"
		else
			validateBays(scene,m,cf,width,key,profile,opts,gap,vetoes)
			if #vetoes>0 then
				local fit,why=Placement.Fit(m,scene,sourceCF,width,key,profile,opts)
				if not fit then
					profile="blind";outset=0;opts.bayRoles=nil;opts.facadeType=nil;opts.allowEntrance=false
				else outset=math.max(outset,fit) end -- Never pull an approved frontage inward.
				fitReason=why;cf=sourceCF*CFrame.new(0,0,-outset)
				if fit then
					local ground=Frontage.Ground(cf,0,-2);gap=ground and math.max(0,cf.Y-ground) or gap
					validateBays(scene,m,cf,width,key,profile,opts,gap,vetoes)
				end
			end
			holder,bays=Kit.BuildRun(root,width,key,profile,cf,opts)
		end
		holder:SetAttribute("RunPiece",f.piece);holder:SetAttribute("RunIndex",f.run);holder:SetAttribute("FrontageClass",profile);holder:SetAttribute("FrontageReason",f.reason);holder:SetAttribute("NeighborClearance",f.clearance)
		holder:SetAttribute("FacadeExpectedHeight",h);holder:SetAttribute("FacadeRunWidth",width);holder:SetAttribute("FacadeRunFrame",cf)
		holder:SetAttribute("FacadeSourceFrame",sourceCF);holder:SetAttribute("FacadeOutset",outset);holder:SetAttribute("FacadeFitReason",fitReason)
		root:SetAttribute("MaxOutset",math.max(root:GetAttribute("MaxOutset") or 0,outset))
		for _,x in {-width/2,width/2} do concrete(holder,"FacadeCornerClosure",cf*CFrame.new(x,h/2,0),Vector3.new(.45,h,.6),row.palette) end
		-- Join back to the actual footprint at every end, including the base
		-- 0.75-stud stand-off. Adjacent offset planes otherwise miss at corners.
		local totalOffset=.75+outset
		local outlineCF=sourceCF*CFrame.new(0,0,.75)
		for _,x in {-width/2,width/2} do
			concrete(holder,"FacadeOutsetReturn",outlineCF*CFrame.new(x,h/2,-totalOffset/2),Vector3.new(.45,h,totalOffset+.8),row.palette)
		end
		if f.road then holder:SetAttribute("RoadClass",f.road.class);holder:SetAttribute("RoadDistance",f.road.distance) end
		-- Ground-facing wall/footing panels follow the sampled terrain, rather than
		-- extending one centre sample across an entire sloping elevation.
		local segments=math.max(1,math.ceil(width/4));local sw=width/segments
		local bandFirst,bandLast,bandLow,bandHigh
		local function flushFooting()
			if not bandFirst then return end
			local x=-width/2+((bandFirst+bandLast)/2-.5)*sw
			-- Extend downward to the deepest sample, never float a merged band.
			concrete(holder,"FacadeFooting",cf*CFrame.new(x,-bandHigh/2,0),Vector3.new((bandLast-bandFirst+1)*sw+.02,bandHigh,.8),row.palette)
			bandFirst=nil
		end
		for i=1,segments do
			local x=-width/2+(i-.5)*sw;local low=math.huge
			for _,dx in {-sw/2,0,sw/2} do local y=Frontage.Ground(cf,x+dx,-.5);if y then low=math.min(low,y) end end
			local depth=low<math.huge and math.max(0,cf.Y-low+.2) or gap
			if depth>.1 then
				-- Bound the range of the ENTIRE band, rather than chaining small
				-- differences until a gradual slope accidentally becomes one wall.
				if bandFirst and math.max(bandHigh,depth)-math.min(bandLow,depth)>.02 then flushFooting() end
				if not bandFirst then bandFirst=i;bandLow=depth;bandHigh=depth
				else bandLow=math.min(bandLow,depth);bandHigh=math.max(bandHigh,depth) end
				bandLast=i
			else flushFooting() end
		end
		flushFooting()
		for _,bay in holder:GetChildren() do if bay:IsA("Model") and bay:GetAttribute("FacadePortals") then
			for _,p in Http:JSONDecode(bay:GetAttribute("FacadePortals")) do
				portals+=1
				local bcf=bay:GetPivot();local y=Frontage.Ground(bcf,p.x,-2);local rise=y and math.max(0,bcf.Y-y) or gap
				if p.name=="parking" or p.name=="loading" then
					local driveway,why=drivewayGeometry(bcf,p)
					assert(driveway,why) -- Backstop if the surveyed ground changes mid-build.
					if driveway.needed then
						local length,toe=driveway.length,driveway.toe;rise=driveway.rise
						assert(rise<=Frontage.MAX_ENTRY_RISE and rise/length<=.25,"Oversized vehicle ramp rejected")
						local wedge=Instance.new("WedgePart");wedge.Name="GarageApproachRamp";wedge.Size=Vector3.new(p.width,rise,length)
						wedge.CFrame=bcf*CFrame.new(p.x,-rise/2,-length/2);wedge.Anchored=true;wedge.CanTouch=false;wedge.Material=Enum.Material.Concrete
						wedge.Color=Catalog.PALETTES[row.palette].wall;wedge:AddTag("NoCSG");wedge:SetAttribute("FacadeApproachRise",rise);wedge:SetAttribute("FacadeApproachLength",length);wedge:SetAttribute("FacadeDrivewayToeY",toe);wedge.Parent=holder
						-- Embed an opaque base beneath the complete wedge volume on any
						-- remaining small grade; nothing is a hovering angled sheet.
						local thickness=driveway.thickness
						concrete(holder,"GarageRampSolidBase",bcf*CFrame.new(p.x,-rise-thickness/2,-length/2),Vector3.new(p.width,thickness,length),row.palette)
					end
				elseif rise>.2 and (p.y or 0)<.1 then
					local n=math.ceil(rise/.5);for i=1,n do local v=rise*i/n
						local z=-(n-i+.5)*.8;local ground=math.huge;local stepWidth=math.max(3,p.width)
						for _,dx in {-stepWidth/2,0,stepWidth/2} do for _,dz in {-.4,0,.4} do local gy=Frontage.Ground(bcf,p.x+dx,z+dz);if gy then ground=math.min(ground,gy) end end end
						local top=bcf.Y-rise+v;local height=math.max(.12,top-ground+.1)
						concrete(holder,"EntryApproachStep",bcf*CFrame.new(p.x,top-bcf.Y-height/2,z),Vector3.new(stepWidth,height,.8),row.palette)
					end
				end
			end
		end end
		f.bayRoles=table.clone(opts.bayRoles or {}) -- Persist automatic vetoes for stable replay.
		owned[f.piece.."/"..f.run]=true
		table.insert(r.faces,{piece=f.piece,run=f.run,class=profile,reason=f.reason,clearance=f.clearance,road=f.road,width=width,height=h,frame={cf:GetComponents()},sourceFrame=f.frame,outset=outset,fitReason=fitReason,portals=portals,vetoes=vetoes,types=bays})
	end
	r.supportedPlanters=supportedProps(root,row.palette,maxGap)
	for _,p in root:GetDescendants() do if p:IsA("BasePart") then r.parts+=1;if p:HasTag("GlassPane") then r.panes+=1 end end end
	end)
	if not okay then root:Destroy();error(err) end
	return m,root,owned,r
end
function Pilot.Clear()
	local reg=game.ServerStorage:FindFirstChild("GroundFacadePilotManifest");if not reg then return end
	assert(reg:GetAttribute("Owner")==OWNER,"Unowned registry")
	for _,row in Http:JSONDecode(Registry.Read(reg,"Manifest") or "[]") do
		local m=find(row.id);local f=m:FindFirstChild("GroundFacadePilot")
		if f then
			assert(f:GetAttribute("Owner")==OWNER,"Unowned facade child")
			for key in Http:JSONDecode(m:GetAttribute("GroundFacadeOwnedRuns") or "{}") do GlassDamage.RepairRun(m,"ground/"..row.id.."/"..key.."/") end
			m:SetAttribute("GroundFacadeOwnedRuns",nil);f:Destroy()
			m:SetAttribute("GroundFacadeMaxOutset",nil)
		end
	end
	reg:Destroy()
end
function Pilot.Apply(rows,scene)
	assert(not game:GetService("RunService"):IsRunning(),"Edit-time only");assert(scene,"Supply frontage index")
	local staged={};local report={buildings=#rows,parts=0,panes=0,supportedPlanters=0,rows={},revision=9}
	local ok,err=pcall(function() for _,row in rows do local m,f,owned,r=build(row,scene)
		table.insert(staged,{model=m,root=f,owned=owned});table.insert(report.rows,r)
		report.parts+=r.parts;report.panes+=r.panes;report.supportedPlanters+=r.supportedPlanters
		task.wait() -- Bound main-thread work to one building.
	end end)
	if not ok then for _,s in staged do s.root:Destroy() end;error(err) end
	local old=game.ServerStorage:FindFirstChild("GroundFacadePilotManifest")
	if old then
		assert(old:GetAttribute("Owner")==OWNER,"Unowned pilot")
		local archive=game.ServerStorage:FindFirstChild("GroundFacadePilotArchive") or Instance.new("Folder");archive.Name="GroundFacadePilotArchive";archive.Parent=game.ServerStorage
		local snapshot=Instance.new("Folder");snapshot.Name="BeforePerimeter_"..os.time();snapshot.Parent=archive;old:Clone().Parent=snapshot
		for _,row in Http:JSONDecode(Registry.Read(old,"Manifest")) do local f=find(row.id):FindFirstChild("GroundFacadePilot");if f then local clone=f:Clone();clone.Name=row.id;clone:SetAttribute("SourceSliceId",row.id);clone.Parent=snapshot end;task.wait() end
		Pilot.Clear()
	end
	for _,s in staged do s.root.Parent=s.model;s.model:SetAttribute("GroundFacadeOwnedRuns",Http:JSONEncode(s.owned));s.model:SetAttribute("GroundFacadeMaxOutset",s.root:GetAttribute("MaxOutset") or 0);task.wait() end
	local reg=Instance.new("Folder");reg.Name="GroundFacadePilotManifest";reg:SetAttribute("Owner",OWNER);Registry.Write(reg,"Manifest",Http:JSONEncode(rows));Registry.Write(reg,"Report",Http:JSONEncode(report));reg:SetAttribute("State","ready");reg.Parent=game.ServerStorage
	game:GetService("ChangeHistoryService"):SetWaypoint("Compact ground facade perimeters");return report
end

-- Recoverable per-building city rollout. The registry's Checkpoint is atomic;
-- committed journal entries describe replacements since its last checkpoint.
local function liveRegistry()
	local reg=game.ServerStorage:FindFirstChild("GroundFacadePilotManifest")
	if reg then assert(reg:GetAttribute("Owner")==OWNER,"Unowned pilot registry")
	else reg=Instance.new("Folder");reg.Name="GroundFacadePilotManifest";reg:SetAttribute("Owner",OWNER);reg.Parent=game.ServerStorage end
	local checkpoint=Registry.Read(reg,"Checkpoint")
	local data=checkpoint and Http:JSONDecode(checkpoint) or {
		manifest=Http:JSONDecode(Registry.Read(reg,"Manifest") or "[]"),
		report=Http:JSONDecode(Registry.Read(reg,"Report") or '{"rows":[]}'),
	}
	local rows,reports={},{ }
	for _,row in data.manifest do rows[row.id]=row end
	for _,row in data.report.rows or {} do reports[row.id]=row end
	local journal=reg:FindFirstChild("CommitJournal")
	if journal then for _,entry in journal:GetChildren() do
		if entry:GetAttribute("Committed")==true then
			local id=entry:GetAttribute("SourceSliceId")
			if entry:GetAttribute("Kind")=="remove" then rows[id]=nil;reports[id]=nil
			else rows[id]=Http:JSONDecode(Registry.Read(entry,"ManifestRow"));reports[id]=Http:JSONDecode(Registry.Read(entry,"ReportRow")) end
		end
	end else journal=Instance.new("Folder");journal.Name="CommitJournal";journal.Parent=reg end
	return reg,journal,rows,reports
end
local function checkpoint(reg,journal,rows,reports,state,incremental)
	local manifest,reportRows={},{}
	for id,row in rows do
		assert(reports[id],"Manifest is missing report row: "..id)
		table.insert(manifest,row);table.insert(reportRows,reports[id])
	end
	table.sort(manifest,function(a,b)return a.id<b.id end);table.sort(reportRows,function(a,b)return a.id<b.id end)
	local report={revision=9,buildings=#manifest,parts=0,panes=0,supportedPlanters=0,rows=reportRows}
	for _,r in reportRows do report.parts+=r.parts or 0;report.panes+=r.panes or 0;report.supportedPlanters+=r.supportedPlanters or 0 end
	if not incremental then
	Registry.Write(reg,"Checkpoint",Http:JSONEncode({manifest=manifest,report=report}))
	Registry.Write(reg,"Manifest",Http:JSONEncode(manifest));Registry.Write(reg,"Report",Http:JSONEncode(report))
	end
	reg:SetAttribute("Revision",9);reg:SetAttribute("State",state or "updating");reg:SetAttribute("Buildings",#manifest)
	if not incremental then journal:ClearAllChildren() end
	return report
end
local function startArchive(reg,label)
	local archive=game.ServerStorage:FindFirstChild("GroundFacadePilotArchive") or Instance.new("Folder")
	archive.Name="GroundFacadePilotArchive";archive.Parent=game.ServerStorage
	local batch=Instance.new("Folder");batch.Name=label.."_"..Http:GenerateGUID(false);batch:SetAttribute("Owner",OWNER);batch:SetAttribute("Revision",9);batch:SetAttribute("State","updating")
	batch.Parent=archive
	local previous=reg:Clone();previous.Name="RegistryBefore";previous.Parent=batch
	return batch
end
local function invalidate(scene,model)
	if scene then for _,b in scene.buildings do if b.model==model then b.opaque=nil end end end
end
local function repairRuns(model,id,encoded)
	for key in Http:JSONDecode(encoded or "{}") do GlassDamage.RepairRun(model,"ground/"..id.."/"..key.."/") end
end
local function journalEntry(journal,id,kind,row,r)
	-- One latest entry per ID, so replay order never matters.
	local prior=journal:FindFirstChild(id);if prior then prior:Destroy() end
	local entry=Instance.new("Folder");entry.Name=id;entry:SetAttribute("SourceSliceId",id);entry:SetAttribute("Kind",kind)
	if row then Registry.Write(entry,"ManifestRow",Http:JSONEncode(row));Registry.Write(entry,"ReportRow",Http:JSONEncode(r)) end
	return entry
end
function Pilot.Upsert(rows,scene,options)
	assert(not game:GetService("RunService"):IsRunning(),"Edit-time only");assert(scene and type(rows)=="table","Supply rows and fresh frontage index")
	options=options or {};local models,seen={},{}
	-- Validate every supplied target BEFORE making backups or replacing geometry.
	for index,row in rows do
		assert(type(row.id)=="string" and not seen[row.id] and type(row.faces)=="table","Unique valid source row required");seen[row.id]=true
		local m=find(row.id);models[row.id]=m
		assert(m:GetAttribute("StructuralOnly")==true and not m:GetAttribute("CrownInteresting") and not m:GetAttribute("Landmark") and not m:HasTag("Landmark"),"Protected/nonordinary target: "..row.id)
		for _,flag in {"StationInfrastructure","FacadeExcluded"} do assert(not m:GetAttribute(flag) and not m:HasTag(flag),"Excluded target: "..row.id) end
		if options.city then local floors=m:GetAttribute("SourceSlicePlan") and m:GetAttribute("GeneratedFloors") or m:GetAttribute("FacadeFloorCount") or m:GetAttribute("GeneratedFloors");assert((floors or math.huge)<=15,"City rollout only allows <=15 floors") end
		assert(Catalog.PALETTES[row.palette],"Invalid palette: "..tostring(row.palette))
		local old=m:FindFirstChild("GroundFacadePilot");assert(not old or old:GetAttribute("Owner")==OWNER,"Unowned facade root")
		if index%25==0 then task.wait() end
	end
	local reg,journal,merged,reports=liveRegistry()
	-- Fold any committed interrupted work before snapshotting this invocation.
	local folded=checkpoint(reg,journal,merged,reports,"preparing",options.incremental)
	if #rows==0 then reg:SetAttribute("State","ready");return folded,{updated=0,errors={},archive=options.archive} end
	local archive=options.archive or startArchive(reg,"BeforeUpsert")
	assert(archive:GetAttribute("Owner")==OWNER and archive:IsDescendantOf(game.ServerStorage.GroundFacadePilotArchive),"Unowned incremental archive")
	local errors={};local updated=0
	reg:SetAttribute("Expected",#rows);reg:SetAttribute("Completed",0);reg:SetAttribute("State","updating")
	for index,row in rows do
		local m=models[row.id];local old=m:FindFirstChild("GroundFacadePilot")
		local oldRuns=m:GetAttribute("GroundFacadeOwnedRuns");local oldOutset=m:GetAttribute("GroundFacadeMaxOutset")
		local fresh,record,owned,entry,held
		local ok,err=pcall(function()
			local builtModel;builtModel,fresh,owned,record=build(row,scene);assert(builtModel==m,"Source target changed during rollout")
			Registry.Write(fresh,"ManifestRow",Http:JSONEncode(row));Registry.Write(fresh,"ReportRow",Http:JSONEncode(record))
			entry=journalEntry(journal,row.id,"upsert",row,record)
			if old then
				held=Instance.new("Folder");held.Name=row.id;held:SetAttribute("SourceSliceId",row.id);held:SetAttribute("GroundFacadeOwnedRuns",oldRuns);held:SetAttribute("GroundFacadeMaxOutset",oldOutset)
				local target=Instance.new("ObjectValue");target.Name="Target";target.Value=m;target.Parent=held;held.Parent=archive
				old.Parent=held
			end
			fresh.Parent=m;m:SetAttribute("GroundFacadeOwnedRuns",Http:JSONEncode(owned));m:SetAttribute("GroundFacadeMaxOutset",fresh:GetAttribute("MaxOutset") or 0)
			-- A single committed flag is written only after all geometry/metadata is live.
			entry:SetAttribute("Committed",true);entry.Parent=journal
		end)
		if not ok then
			if fresh then fresh:Destroy() end
			if old and old.Parent~=m then old.Parent=m end
			m:SetAttribute("GroundFacadeOwnedRuns",oldRuns);m:SetAttribute("GroundFacadeMaxOutset",oldOutset)
			if entry then entry:Destroy() end;if held then held:Destroy() end
			table.insert(errors,{id=row.id,reason=tostring(err)})
		else
			merged[row.id]=row;reports[row.id]=record;updated+=1
			-- Reset only stable ground-cell damage for this deliberately rebuilt root.
			local repaired,why=pcall(repairRuns,m,row.id,oldRuns)
			if not repaired then table.insert(errors,{id=row.id,reason="Geometry committed; damage reset failed: "..tostring(why)}) end
		end
		invalidate(scene,m)
		reg:SetAttribute("Completed",index);reg:SetAttribute("Updated",updated);reg:SetAttribute("Errors",Http:JSONEncode(errors))
		if index%100==0 or not ok then checkpoint(reg,journal,merged,reports,"updating",options.incremental) end
		task.wait() -- Never retain an entire city's unparented geometry.
	end
	local report=checkpoint(reg,journal,merged,reports,#errors==0 and "ready" or "readyWithErrors",options.incremental)
	archive:SetAttribute("State","complete");archive:SetAttribute("Updated",updated);archive:SetAttribute("Errors",Http:JSONEncode(errors))
	game:GetService("ChangeHistoryService"):SetWaypoint("Ground facade v9 incremental city rollout")
	return report,{updated=updated,errors=errors,archive=archive}
end
function Pilot.RemoveHeld(models,reason)
	assert(not game:GetService("RunService"):IsRunning(),"Edit-time only");assert(type(models)=="table" and type(reason)=="string" and #reason>0,"Explicit models and removal reason required")
	local seen={};for _,m in models do
		assert(typeof(m)=="Instance" and m:IsA("Model") and not seen[m],"Unique explicit models required");seen[m]=true
		local root=m:FindFirstChild("GroundFacadePilot");assert(not root or root:GetAttribute("Owner")==OWNER,"Unowned facade root")
		assert(not root or type(m:GetAttribute("SourceSliceId") or m:GetAttribute("FacadeSourceId"))=="string","Owned root without source identity")
	end
	local reg,journal,merged,reports=liveRegistry();checkpoint(reg,journal,merged,reports,"preparing")
	local archive=startArchive(reg,"HeldFacades");archive:SetAttribute("Reason",reason)
	local removed,errors=0,{}
	for index,m in models do
		local id=m:GetAttribute("SourceSliceId") or m:GetAttribute("FacadeSourceId");local root=m:FindFirstChild("GroundFacadePilot")
		if id and (root or merged[id]) then
			local oldRuns=m:GetAttribute("GroundFacadeOwnedRuns");local oldOutset=m:GetAttribute("GroundFacadeMaxOutset")
			local entry=journalEntry(journal,id,"remove");local held
			local ok,err=pcall(function()
				held=Instance.new("Folder");held.Name=id;held:SetAttribute("SourceSliceId",id);held:SetAttribute("GroundFacadeOwnedRuns",oldRuns);held:SetAttribute("GroundFacadeMaxOutset",oldOutset);held:SetAttribute("Reason",reason)
				local target=Instance.new("ObjectValue");target.Name="Target";target.Value=m;target.Parent=held;held.Parent=archive
				if root then root.Parent=held end
				m:SetAttribute("GroundFacadeOwnedRuns",nil);m:SetAttribute("GroundFacadeMaxOutset",nil)
				entry:SetAttribute("Committed",true);entry.Parent=journal
			end)
			if ok then merged[id]=nil;reports[id]=nil;removed+=1
				local repaired,why=pcall(repairRuns,m,id,oldRuns);if not repaired then table.insert(errors,{id=id,reason=tostring(why)}) end
			else
				if root then root.Parent=m end;m:SetAttribute("GroundFacadeOwnedRuns",oldRuns);m:SetAttribute("GroundFacadeMaxOutset",oldOutset)
				if held then held:Destroy() end;entry:Destroy();table.insert(errors,{id=id,reason=tostring(err)})
			end
		end
		if index%25==0 then checkpoint(reg,journal,merged,reports,"updating") end
		task.wait()
	end
	local report=checkpoint(reg,journal,merged,reports,#errors==0 and "ready" or "readyWithErrors")
	archive:SetAttribute("State","complete");archive:SetAttribute("Removed",removed);archive:SetAttribute("Errors",Http:JSONEncode(errors))
	return report,{removed=removed,errors=errors,archive=archive}
end

function Pilot.Focus(index)
	local reg=assert(game.ServerStorage:FindFirstChild("GroundFacadePilotManifest"),"Apply first");local r=Http:JSONDecode(Registry.Read(reg,"Report")).rows[index or 1]
	local face;for _,f in r.faces do if f.portals>0 then face=f;break end end;face=face or r.faces[1]
	local cf=CFrame.new(table.unpack(face.frame));local target=(cf*CFrame.new(0,5,0)).Position
	workspace.CurrentCamera.Focus=CFrame.new(target);workspace.CurrentCamera.CFrame=CFrame.lookAt((cf*CFrame.new(-10,7,-38)).Position,target);game:GetService("Selection"):Set({find(r.id).GroundFacadePilot})
end
return Pilot
