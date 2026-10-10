--!nonstrict
-- Exterior mounting contract: local -Z is street-facing. The mounting frame
-- sits 0.75 studs outside the source floor outline; all exterior rear vertices
-- stay at Z <= 0.45, leaving at least 0.30 studs clear of that outline.
-- Interior dressing is a separate layer and never determines exterior fit.
local Mount={StandOff=.75,RearLimit=.45,PaneZ=.15,Revision=8}
local function halfDepth(row)
	local c,s=row.cframe,row.size
	return (math.abs(c.XVector.Z)*s.X+math.abs(c.YVector.Z)*s.Y+math.abs(c.ZVector.Z)*s.Z)/2
end
local function interior(row)
	return row.kind=="preview" or row.name:match("^Preview") or row.name=="RoundPilotis"
		or ((row.kind=="prop" or row.kind=="light") and row.cframe.Z>0.7)
		or row.name=="DeepBookDisplaySill" or row.name=="RoundWasherWindow"
end
function Mount.Layout(layout,options)
	if options and options.mount=="recessed" then return layout end -- isolated legacy gallery option
	local panes={}
	for _,r in layout.parts do if r.material==Enum.Material.Glass or r.name=="SteelDoorLeaf" then
		table.insert(panes,{row=r,position=r.cframe.Position})
	end end
	for _,r in layout.parts do
		if interior(r) then r.layer="interior";continue end
		r.layer="exterior"
		local z=r.cframe.Z
		if r.material==Enum.Material.Glass or r.name=="SteelDoorLeaf" then z=Mount.PaneZ
		end
		z=math.min(z,Mount.RearLimit-halfDepth(r))
		r.cframe+=Vector3.zAxis*(z-r.cframe.Z)
	end
	for _,p in layout.portals or {} do if p.name~="parking" and p.name~="loading" then p.recess=Mount.PaneZ end end
	if layout.door then layout.door.recess=Mount.PaneZ end
	-- A shallow, noncolliding interior backing stops a flush core reading as
	-- beige wall through the glass. It is owned by its pane and hidden/removed
	-- with states 3/4. Detailed interior dressing may extend freely inward.
	for _,p in panes do if p.row.material==Enum.Material.Glass then
		local pane=p.row
		table.insert(layout.parts,{name="InteriorWindowBacking",cframe=pane.cframe*CFrame.new(0,0,.20),
			size=Vector3.new(pane.size.X,pane.size.Y,.05),color=Color3.fromRGB(38,49,53),
			material=Enum.Material.SmoothPlastic,kind="preview",layer="interior",transparency=0})
	end end
	layout.mountRevision=Mount.Revision
	return layout
end
return Mount
