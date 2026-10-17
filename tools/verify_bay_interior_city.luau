-- Read-only analytic solid-overlap check for every prepared shared bay recipe.
local H=game:GetService("HttpService")
local grid,rows={},{}
local function overlaps(a,b)
	if math.min(a.top,b.top)-math.max(a.bottom,b.bottom)<.01 then return false end
	for _,polygon in {a.poly,b.poly} do for i,p in polygon do
		local q=polygon[i%#polygon+1];local edge=q-p;local axis=Vector2.new(-edge.Y,edge.X).Unit
		local al,ah,bl,bh=math.huge,-math.huge,math.huge,-math.huge
		for _,v in a.poly do local d=v:Dot(axis);al=math.min(al,d);ah=math.max(ah,d) end
		for _,v in b.poly do local d=v:Dot(axis);bl=math.min(bl,d);bh=math.max(bh,d) end
		if math.min(ah,bh)-math.max(al,bl)<.01 then return false end
	end end
	return true
end
local out={prepared=0,panes=0,previews=0,legacyPaneCells=0,overlaps=0,examples={}}
for _,bay in game.CollectionService:GetTagged("FacadeInteriorBay") do
	if not bay:IsDescendantOf(workspace.Buildings) then continue end
	local c=H:JSONDecode(bay:GetAttribute("FacadeBayInteriorPlan"));local cf=bay:GetPivot()
	local row={bay=bay,poly={},bottom=cf.Y+c.bottom,top=cf.Y+c.top,index=#rows+1}
	local lo,hi=Vector2.one*math.huge,-Vector2.one*math.huge
	for _,v in {{c.left,c.start},{c.right,c.start},{c.backRight,c.start+c.depth},{c.backLeft,c.start+c.depth}} do
		local p=cf:PointToWorldSpace(Vector3.new(v[1],0,v[2]));local q=Vector2.new(p.X,p.Z)
		table.insert(row.poly,q);lo=lo:Min(q);hi=hi:Max(q)
	end
	table.insert(rows,row);out.prepared+=1
	if bay:FindFirstChild("BayInterior") then out.previews+=1 end
	for _,p in bay:GetChildren() do if p:IsA("BasePart") and p:HasTag("GlassPane") then out.panes+=1;if p:GetAttribute("GlassInteriorStaticVersion") then out.legacyPaneCells+=1 end end end
	for x=math.floor(lo.X/32),math.floor(hi.X/32) do for z=math.floor(lo.Y/32),math.floor(hi.Y/32) do local key=x.."/"..z;grid[key]=grid[key] or {};table.insert(grid[key],row) end end
end
local seen,conflicts={},{}
for _,bucket in grid do for i=1,#bucket do for j=i+1,#bucket do
	local a,b=bucket[i],bucket[j];local key=math.min(a.index,b.index).."/"..math.max(a.index,b.index)
	if not seen[key] then seen[key]=true;if overlaps(a,b) then
		out.overlaps+=1;table.insert(conflicts,{a=a.bay,b=b.bay})
		if #out.examples<20 then table.insert(out.examples,{a=a.bay:GetFullName(),b=b.bay:GetFullName()}) end
	end end
end end end
_G.BayInteriorConflicts=conflicts
_G.BayInteriorCityAudit=out
return out
