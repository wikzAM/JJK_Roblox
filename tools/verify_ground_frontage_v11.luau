-- Read-only frontage acceptance for revision 11 (glazed alleys). Edit only.
-- Uses each live root's own ManifestRow, so owner-deleted buildings are simply absent.
-- Checks: every recipe face has a live run; only class "front" runs may carry
-- entrance portals; quiet classes (window/alleyQuiet/blind) have zero portals.
local H=game:GetService("HttpService")
local R=require(game.ServerScriptService.Server.GroundFacadeRegistry)
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
local out={buildings=0,faces=0,runs=0,missingRuns=0,classMismatch=0,frontRuns=0,frontPortals=0,frontWithoutPortal=0,
	quietRuns=0,quietPortals=0,byClass={},errors={}}
for _,m in workspace.Buildings:GetChildren() do
	local root=m:FindFirstChild("GroundFacadePilot")
	if not root then continue end
	local row=H:JSONDecode(assert(R.Read(root,"ManifestRow")))
	local runs={}
	for _,run in root:GetChildren() do if run:IsA("Model") and run:GetAttribute("RunPiece") then
		runs[run:GetAttribute("RunPiece").."/"..run:GetAttribute("RunIndex")]=run
	end end
	for _,f in row.faces do
		out.faces+=1
		local run=runs[f.piece.."/"..f.run]
		if not run then
			out.missingRuns+=1
			if #out.errors<20 then table.insert(out.errors,{id=row.id,run=f.piece.."/"..f.run,reason="missing run"}) end
			continue
		end
		out.runs+=1
		local built=run:GetAttribute("FrontageClass")
		out.byClass[built]=(out.byClass[built] or 0)+1
		local portals=0
		for _,bay in run:GetChildren() do if bay:IsA("Model") and bay:GetAttribute("FacadePortals") then
			portals+=#H:JSONDecode(bay:GetAttribute("FacadePortals"))
		end end
		if f.class=="front" then
			out.frontRuns+=1;out.frontPortals+=portals;if portals==0 then out.frontWithoutPortal+=1 end
		else
			-- Pilot may downgrade any class to blind (fit/narrow), never upgrade quiet to front.
			if built~=f.class and built~="blind" then out.classMismatch+=1
				if #out.errors<20 then table.insert(out.errors,{id=row.id,run=f.piece.."/"..f.run,reason="built "..tostring(built).." for "..f.class}) end end
			out.quietRuns+=1;out.quietPortals+=portals
			if portals>0 and #out.errors<20 then table.insert(out.errors,{id=row.id,run=f.piece.."/"..f.run,reason="entrance on quiet "..f.class}) end
		end
	end
	out.buildings+=1
	if out.buildings%50==0 then task.wait() end
end
_G.FrontageV11Audit=out
return out
