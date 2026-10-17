-- Edit-only metadata reconciliation after surface trimming / static inlets.
-- No source geometry changes and no giant aggregate checkpoint rewrite.
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
local H=game:GetService("HttpService")
local R=require(game.ServerScriptService.Server.GroundFacadeRegistry)
local reg=game.ServerStorage.GroundFacadePilotManifest
local journal=assert(reg:FindFirstChild("CommitJournal"))
local out={buildings=0,parts=0,panes=0,inlets=0,bayInteriors=0,previewRooms=0,updated=0}
for _,m in workspace.Buildings:GetChildren() do
	local root=m:FindFirstChild("GroundFacadePilot")
	if not root or root:GetAttribute("Owner")~="2026-10-08-ground-pilot" then continue end
	local manifest=H:JSONDecode(assert(R.Read(root,"ManifestRow")))
	local record=H:JSONDecode(assert(R.Read(root,"ReportRow")))
	local parts,panes,inlets,bayInteriors,previewRooms=0,0,0,0,0;local masks={}
	for _,p in root:GetDescendants() do if p:IsA("BasePart") then
		parts+=1;if p:HasTag("GlassPane") then panes+=1 end
		if p:GetAttribute("GlassInteriorStaticVersion") then inlets+=1 end
	elseif p:IsA("Model") and p:GetAttribute("FacadeBayInteriorVersion")==2 then bayInteriors+=1
	elseif p.Name=="BayInterior" and p:GetAttribute("EditPreview") then previewRooms+=1 end end
	for _,run in root:GetChildren() do
		local raw=run:GetAttribute("FacadeSharedSurfaceMasks")
		if raw then masks[run:GetAttribute("RunPiece").."/"..run:GetAttribute("RunIndex")]=H:JSONDecode(raw) end
	end
	local existingJournal=journal:FindFirstChild(manifest.id)
	local changed=record.parts~=parts or record.panes~=panes or record.staticInlets~=inlets or record.bayInteriors~=bayInteriors or record.previewRooms~=previewRooms or (existingJournal and existingJournal:GetAttribute("Kind")=="remove")
	if next(masks) or manifest.surfaceOwnershipRevision then
		changed=changed or (next(masks) and manifest.surfaceOwnershipRevision~=1) or not next(masks)
		manifest.surfaceOwnershipRevision=next(masks) and 1 or nil
		for _,row in {manifest,record} do for _,f in row.faces do
			local current=masks[f.piece.."/"..f.run]
			-- Equal part counts do not imply equal clipping recipes.
			changed=changed or H:JSONEncode(f.sharedSurfaceMasks or {})~=H:JSONEncode(current or {})
			f.sharedSurfaceMasks=current
		end end
	end
	if changed then
		record.parts=parts;record.panes=panes;record.staticInlets=inlets;record.bayInteriors=bayInteriors;record.previewRooms=previewRooms
		local encodedManifest,encodedReport=H:JSONEncode(manifest),H:JSONEncode(record)
		R.Write(root,"ManifestRow",encodedManifest);R.Write(root,"ReportRow",encodedReport)
		local entry=existingJournal
		if not entry then entry=Instance.new("Folder");entry.Name=manifest.id;entry:SetAttribute("SourceSliceId",manifest.id);entry:SetAttribute("Kind","upsert") end
		entry:SetAttribute("SourceSliceId",manifest.id);entry:SetAttribute("Kind","upsert")
		R.Write(entry,"ManifestRow",encodedManifest);R.Write(entry,"ReportRow",encodedReport)
		entry:SetAttribute("Committed",true);entry.Parent=journal;out.updated+=1
	end
	out.buildings+=1;out.parts+=parts;out.panes+=panes;out.inlets+=inlets;out.bayInteriors+=bayInteriors;out.previewRooms+=previewRooms
	task.wait()
end
reg:SetAttribute("SurfaceRepairCurrentTotals",H:JSONEncode(out))
return out
