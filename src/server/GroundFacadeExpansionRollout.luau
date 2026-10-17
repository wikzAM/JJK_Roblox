--!nonstrict
-- Explicit Edit-only driver. No automatic startup, background mutation or map rebuild.
local H=game:GetService("HttpService")
local Storage=game:GetService("ServerStorage")
local Section=require(script.Parent.GroundFacadeSection)
local Pilot=require(script.Parent.GroundFacadePilot)
local Registry=require(script.Parent.GroundFacadeRegistry)
local BayInteriors=require(script.Parent.GroundFacadeBayInteriors)
local Layout=require(game:GetService("ReplicatedStorage").Shared.FacadeLayout)
local Driver={VERSION=2,BATCH_SIZE=10,MIN_STEP_GAP=30}
local OWNER="2026-10-08-ground-pilot"
local busy=false
local lastCompletedStep=-math.huge
local contexts=setmetatable({},{__mode="k"})
local REMOVED="fbx_12_24502_3155_-12717"
local removedIds={REMOVED,"fbx_4_-11393_1017_-4367","fbx_4_-11596_863_-4573","fbx_4_-12223_1142_-5207"}
local function connected()
	return game:GetService("NetworkClient"):FindFirstChildWhichIsA("ClientReplicator")~=nil
end
local function guard()
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	assert(connected(),"Editing server disconnected; reopen TestJJK and call Prepare again")
end
local function exclusive(fn)
	assert(not busy,"An expansion driver operation is already running")
	busy=true
	local okay,a,b,c=pcall(fn)
	busy=false -- Always release, including survey/build/metadata failures.
	if not okay then error(a,2) end
	return a,b,c
end
local function policy()
	local excluded={
		["fbx_5_6952_1857_6146"]=true,["orph_703_1736"]=true,["orph_706_1735"]=true,
	}
	for _,id in removedIds do excluded[id]=true end
	return {maxFootprintArea=30000,zones={
		{id="crossing",center=Vector2.new(11,572),radius=500},
		{id="109-district",center=Vector2.new(683,596),radius=275},
	},excludedIds=excluded}
end
local function sourceMoved(model,row)
	local current=Layout.FrameOf(model)
	if not current or type(row.frame)~="table" or #row.frame~=12 then return true end
	local surveyed=CFrame.new(table.unpack(row.frame))
	return (current.Position-surveyed.Position).Magnitude>.02
		or current.XVector.Unit:Dot(surveyed.XVector.Unit)<.999999
		or current.YVector.Unit:Dot(surveyed.YVector.Unit)<.999999
		or current.ZVector.Unit:Dot(surveyed.ZVector.Unit)<.999999
end
local function extraHold(model,row)
	for _,flag in {"StationInfrastructure","FacadeExcluded"} do
		if model:HasTag(flag) then return "protected-tag-"..flag end
	end
	for _,face in row.faces do
		if type(face.height)~="number" or face.height~=face.height or face.height>24 then return "oversized-ground-storey" end
	end
	return nil
end
local function registry()
	local reg=Storage:FindFirstChild("GroundFacadePilotManifest")
	assert(reg and reg:GetAttribute("Owner")==OWNER,"Missing/unowned facade registry")
	return reg
end
local function progress(ctx,state,details)
	local record={version=Driver.VERSION,session=ctx.session,state=state,
		queued=#ctx.rows,cursor=ctx.cursor,remaining=math.max(0,#ctx.rows-ctx.cursor+1),
		updated=ctx.updated,skipped=ctx.skipped,batches=ctx.batches,
		cloudPersistenceConfirmed=false,details=details}
	local encoded=H:JSONEncode(record)
	Registry.Write(ctx.archive,"ExpansionProgress",encoded)
	Registry.Write(ctx.reg,"ExpansionProgress",encoded)
	if not connected() then
		ctx.disconnected=true;record.state="disconnected"
		record.resume="Reopen TestJJK and Prepare fresh; metadata writes do not prove cloud persistence"
	end
	return record
end
function Driver.Prepare()
	return exclusive(function()
		guard()
		local opts=policy()
		-- A fresh survey is mandatory after reconnect. Never resume stale _G rows.
		local rows,scene,report=Section.SelectCity(opts)
		guard()
		local missing,held,ids={},{},{}
		local byId={};for _,b in scene.buildings do byId[b.id]=b.model end
		local installed=0
		for _,row in rows do
			local m=byId[row.id]
			local why=extraHold(m,row)
			if why then table.insert(held,{id=row.id,reason=why})
			elseif m:FindFirstChild("GroundFacadePilot") then installed+=1
			else table.insert(missing,row);table.insert(ids,row.id) end
		end
		local reg=registry()
		local parent=Storage:FindFirstChild("GroundFacadePilotArchive")
		assert(parent and parent:IsA("Folder"),"Missing facade archive container")
		local archive=Instance.new("Folder")
		archive.Name="Expansion_"..H:GenerateGUID(false);archive:SetAttribute("Owner",OWNER)
		archive:SetAttribute("ExpansionDriverVersion",Driver.VERSION);archive.Parent=parent
		local scope={version=Driver.VERSION,eligible=report.eligible,held=report.held,
			alreadyInstalled=installed,queued=#missing,queuedIds=ids,additionalHolds=held,
			heldBuildings=report.heldBuildings,reasonCounts=report.reasonCounts,
			policy={maxFloors=15,maxFootprintArea=30000,crossing={11,572,500},district109={683,596,275},excludedIds=opts.excludedIds},
			deferredBoxRepairs={"fbx_6_16012_2445_-12199","fbx_11_13048_1764_5668"},
			intentionallyRemovedId=REMOVED,intentionallyRemovedIds=removedIds}
		Registry.Write(archive,"ExpansionScope",H:JSONEncode(scope))
		Registry.Write(reg,"ExpansionScope",H:JSONEncode(scope))
		local ctx={rows=missing,scene=scene,report=report,options=opts,reg=reg,archive=archive,
			session=archive.Name,cursor=1,updated=0,skipped=0,batches=0,disconnected=false}
		contexts[ctx]=true
		progress(ctx,#missing==0 and "complete" or "prepared")
		assert(not ctx.disconnected,"Disconnected while preparing metadata; reopen and Prepare again")
		return ctx,scope
	end)
end
function Driver.Step(ctx)
	return exclusive(function()
		assert(contexts[ctx],"Unknown context; call Prepare on this module instance")
		assert(not ctx.disconnected,"Context invalidated by disconnect; reopen and Prepare again")
		assert(not ctx.failed,"Context invalidated by interrupted build; call Prepare again")
		if not connected() then ctx.disconnected=true end
		guard()
		local delay=Driver.MIN_STEP_GAP-(os.clock()-lastCompletedStep)
		if delay>0 then task.wait(delay) end -- Let Team Create replicate the previous bounded commit.
		if not connected() then ctx.disconnected=true end
		guard()
		local batch,skips={},{}
		local byId={};for _,b in ctx.scene.buildings do byId[b.id]=b.model end
		local nextCursor=ctx.cursor
		-- Bound both scans and mutations, including models changed since Prepare.
		for i=ctx.cursor,math.min(#ctx.rows,ctx.cursor+Driver.BATCH_SIZE-1) do
			local row=ctx.rows[i];local m=byId[row.id];local why
			if not m or m.Parent~=workspace.Buildings then why="no-longer-live"
			elseif m:FindFirstChild("GroundFacadePilot") then why="already-installed"
			else
				local allowed,reason=Section.Eligible(m,ctx.options)
				why=not allowed and reason or extraHold(m,row)
				if not why and sourceMoved(m,row) then
					ctx.failed=true
					return progress(ctx,"source-moved",{id=row.id,resume="Prepare fresh to resurvey moved building and neighborhood"})
				end
			end
			if why then table.insert(skips,{id=row.id,reason=why}) else table.insert(batch,row) end
			nextCursor=i+1
		end
		local result={updated=0,errors={}}
		if #batch>0 then
			local okay,reportOrError,info=pcall(Pilot.Upsert,batch,ctx.scene,{city=true,incremental=true,
				archive=ctx.archive,keepReplacedGeometry=false})
			if not okay then
				ctx.failed=true;ctx.disconnected=not connected()
				error("Build interrupted; Prepare fresh before resuming: "..tostring(reportOrError))
			end
			result=info
			if not connected() then
				ctx.disconnected=true
				return {state="disconnected",updatedLocally=result.updated,errors=result.errors,interiorsPrepared=false}
			end
			-- Prepare only roots just committed by this call, including any successful
			-- subset of a partial Upsert. Never silently leave expansion without v2 glass.
			local built={}
			for _,row in batch do
				local m=byId[row.id];local root=m:FindFirstChild("GroundFacadePilot")
				if root and root:GetAttribute("Owner")==OWNER then table.insert(built,m) end
			end
			local prepared,interiorResult=pcall(BayInteriors.ApplyBatch,built,{preview=false})
			if not prepared then
				ctx.failed=true;ctx.disconnected=not connected()
				return progress(ctx,"interior-errors",{updatedLocally=result.updated,error=tostring(interiorResult),resume="Repair unprepared roots, then Prepare fresh"})
			end
			result.interiors=interiorResult
		end
		lastCompletedStep=os.clock()
		-- Never issue a subsequent build from a disconnected local datamodel.
		if not connected() then
			ctx.disconnected=true
			return {state="disconnected",resume="Reopen TestJJK, then Prepare fresh; local commits are not cloud persistence proof",updatedLocally=result.updated,errors=result.errors}
		end
		ctx.updated+=result.updated;ctx.skipped+=#skips;ctx.batches+=1
		if #result.errors>0 then
			ctx.failed=true -- Stop on errors; fresh preparation discovers partial commits.
			return progress(ctx,"batch-errors",{errors=result.errors,skips=skips})
		end
		ctx.cursor=nextCursor
		return progress(ctx,ctx.cursor>#ctx.rows and "complete" or "ready",{skips=skips,interiors=result.interiors})
	end)
end
return Driver
