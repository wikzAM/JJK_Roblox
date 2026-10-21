-- Studio edit-time tool (run through MCP as a temporary ModuleScript).
-- Builds side-by-side copies of buildings in Workspace.SlabPilot:
--   Pilot_Orig_<name>    untouched clone
--   Pilot_Reduced_<name> clone whose Interior "Slab" parts are rebuilt by SlabReducer
-- Originals in Workspace.Buildings are never modified.
local HttpService = game:GetService("HttpService")

local Pilot = {}

local function makeBox(p, template: BasePart, origin: CFrame, y: number, t: number): Part
	local part = Instance.new("Part")
	local ux, uz = p.ux, p.uz
	local cf = CFrame.fromMatrix(Vector3.new(p.cx, y, p.cz), Vector3.new(ux, 0, uz), Vector3.yAxis)
	part.CFrame = origin * cf
	part.Size = Vector3.new(p.sx, t, p.sz)
	return part
end

local function makeWedge(p, origin: CFrame, y: number, t: number): WedgePart
	local A = Vector3.new(p.a[1], y, p.a[2])
	local B = Vector3.new(p.b[1], y, p.b[2])
	local C = Vector3.new(p.c[1], y, p.c[2])
	local lenZ, lenY = (A - B).Magnitude, (C - A).Magnitude
	local zAxis, yAxis = (A - B).Unit, (C - A).Unit
	local xAxis = yAxis:Cross(zAxis)
	local center = A + yAxis * (lenY / 2) - zAxis * (lenZ / 2)
	local w = Instance.new("WedgePart")
	w.CFrame = origin * CFrame.fromMatrix(center, xAxis, yAxis, zAxis)
	w.Size = Vector3.new(t, lenY, lenZ)
	return w
end

local function copyLook(dst: BasePart, src: BasePart)
	dst.Anchored = true
	dst.Material = src.Material
	dst.Color = src.Color
	dst.CastShadow = src.CastShadow
	dst.CanCollide = src.CanCollide
	dst.CanQuery = src.CanQuery
	dst.CanTouch = src.CanTouch
	dst.TopSurface = Enum.SurfaceType.Smooth
	dst.BottomSurface = Enum.SurfaceType.Smooth
	dst.Name = "Slab"
	dst:SetAttribute("PolygonSlab", true)
	dst:SetAttribute("SlabReduced", true)
end

-- Rebuild the slabs of one building model in place. Returns before/after counts.
function Pilot.ReduceModel(model: Model, Reducer, opts): (number, number, string?)
	local planS = model:GetAttribute("SourceSlicePlan")
	local origin = model:GetAttribute("SourceSliceOriginCFrame")
	if not planS or typeof(origin) ~= "CFrame" then
		return 0, 0, "no plan"
	end
	local plan = HttpService:JSONDecode(planS)
	local interior = model:FindFirstChild("Interior")
	if not interior then
		return 0, 0, "no interior"
	end
	-- Existing slab heights and the floor model that owns each height.
	local byY, template = {}, nil
	local before = 0
	for _, d in interior:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Slab" then
			before += 1
			template = template or d
			local key = math.floor(d.Position.Y * 10 + 0.5)
			byY[key] = byY[key] or { y = d.Position.Y, parent = d.Parent, parts = {} }
			table.insert(byY[key].parts, d)
		end
	end
	local ys = {}
	for _, v in byY do
		table.insert(ys, v)
	end
	table.sort(ys, function(a, b)
		return a.y < b.y
	end)
	if #ys ~= #plan.levels then
		return before, before, string.format("level mismatch %d slab heights vs %d plan levels", #ys, #plan.levels)
	end
	local after = 0
	for i, level in plan.levels do
		local slot = ys[i]
		local t = level.thickness
		-- Plan-local height of this level's slab centre, matched to the existing slab.
		local yLocal = (origin:PointToObjectSpace(Vector3.new(origin.X, slot.y, origin.Z))).Y
		local prims = Reducer.reduceLevel(level.pieces, opts)
		local made = {}
		for _, p in prims do
			local part = if p.kind == "box" then makeBox(p, template, origin, yLocal, t) else makeWedge(p, origin, yLocal, t)
			copyLook(part, template)
			table.insert(made, part)
		end
		for _, old in slot.parts do
			old:Destroy()
		end
		for _, part in made do
			part.Parent = slot.parent
		end
		after += #made
	end
	return before, after, nil
end

-- names: building names in Workspace.Buildings. Lays pairs out off-map.
function Pilot.Run(names: { string }, Reducer, opts, layout)
	local folder = workspace:FindFirstChild("SlabPilot") or Instance.new("Folder")
	folder.Name = "SlabPilot"
	folder.Parent = workspace
	local results = {}
	local baseX, baseZ, pitch, gap = layout.baseX, layout.baseZ, layout.pitch, layout.gap
	for i, name in names do
		local src = workspace.Buildings:FindFirstChild(name)
		if not src then
			table.insert(results, name .. ": missing")
			continue
		end
		local orig = src:Clone()
		orig.Name = "Pilot_Orig_" .. name
		local red = src:Clone()
		red.Name = "Pilot_Reduced_" .. name
		local before, after, err = Pilot.ReduceModel(red, Reducer, opts)
		local cf, size = src:GetBoundingBox()
		local row = Vector3.new(baseX, cf.Position.Y, baseZ + (i - 1) * pitch)
		local delta = row - cf.Position
		orig:PivotTo(orig:GetPivot() + delta)
		red:PivotTo(red:GetPivot() + delta + Vector3.new(gap, 0, 0))
		orig.Parent = folder
		red.Parent = folder
		table.insert(results, string.format("%s: slabs %d -> %d%s", name, before, after, err and (" (" .. err .. ")") or ""))
		task.wait()
	end
	return results
end

return Pilot
