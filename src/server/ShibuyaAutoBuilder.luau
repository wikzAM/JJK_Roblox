--!nonstrict
-- Edit-time reconstruction from imported triangle geometry, not collision hulls.
-- local a=require(game.ServerScriptService.Server.ShibuyaAutoBuilder)
-- local plans=a.Preview(a.Scan()); a.Generate(plans)
-- Outputs structural interiors through BuildingGenerator's stored-grid path.
local HttpService = game:GetService("HttpService")
local Auto = {}
local SLAB = 1.5 / 0.28
local CLEAR = 3.5 / 0.28

function Auto.Scan()
	return require(script.Parent.ShibuyaGeometry).Scan()
end

local function sections(triangles, y)
	local segments = {}
	for _, t in triangles do
		local hits = {}
		for i = 1, 3 do
			local a, b = t[i], t[i % 3 + 1]
			if (a.Y <= y and b.Y > y) or (b.Y <= y and a.Y > y) then
				table.insert(hits, a:Lerp(b, (y - a.Y) / (b.Y - a.Y)))
			end
		end
		if #hits == 2 and (hits[1] - hits[2]).Magnitude > 0.001 then
			table.insert(segments, hits)
		end
	end
	return segments
end

-- Require paired crossings in BOTH axes. Open facades cannot fill a block.
local function inside(segments, x, z)
	local right, left, front, back = 0, 0, 0, 0
	for _, seg in segments do
		local a, b = seg[1], seg[2]
		if (a.Z > z) ~= (b.Z > z) then
			local xx = a.X + (z - a.Z) * (b.X - a.X) / (b.Z - a.Z)
			if xx > x then right += 1 else left += 1 end
		end
		if (a.X > x) ~= (b.X > x) then
			local zz = a.Z + (x - a.X) * (b.Z - a.Z) / (b.X - a.X)
			if zz > z then front += 1 else back += 1 end
		end
	end
	return right % 2 == 1 and left % 2 == 1 and front % 2 == 1 and back % 2 == 1
end

local function frameFor(g)
	local longest, angle = 0, 0
	for _, t in g.triangles do
		for i = 1, 3 do
			local d = t[i % 3 + 1] - t[i]
			local length = Vector2.new(d.X, d.Z).Magnitude
			if math.abs(d.Y) < 0.1 and length > longest then
				longest, angle = length, -math.atan2(d.Z, d.X)
			end
		end
	end
	local frame = CFrame.new((g.min + g.max) / 2) * CFrame.Angles(0, angle, 0)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, t in g.triangles do
		for _, p in t do local v = frame:PointToObjectSpace(p); lo = lo:Min(v); hi = hi:Max(v) end
	end
	frame *= CFrame.new((lo + hi) / 2)
	local triangles = {}
	for _, t in g.triangles do
		table.insert(triangles, {frame:PointToObjectSpace(t[1]), frame:PointToObjectSpace(t[2]), frame:PointToObjectSpace(t[3])})
	end
	return frame, hi - lo, triangles
end

function Auto.Sample(g)
	if #g.triangles < 8 then return nil, "Open facade or tiny fragment" end
	local cf, size, triangles = frameFor(g)
	if math.min(size.X, size.Z) < 12 or size.Y < 2 * SLAB + CLEAR then return nil, "Too small" end
	local floors = math.floor((size.Y - 2 * SLAB - CLEAR) / (SLAB + CLEAR)) + 1
	local ground = size.Y - 2 * SLAB - (floors - 1) * (SLAB + CLEAR)
	local cell = math.max(3, math.max(size.X, size.Z) / 24)
	local nx, nz = math.ceil(size.X / cell), math.ceil(size.Z / cell)
	local grid = {cell=cell,nx=nx,nz=nz,minX=-size.X/2,minZ=-size.Z/2,floors=floors,ground=ground,clearUpper=CLEAR,occ={},occTight={}}
	local occupied, filledFloors = 0, 0
	for k = 1, floors do
		local bottom = -size.Y / 2 + (k == 1 and 0 or SLAB + ground + (k - 2) * (SLAB + CLEAR))
		local clear = k == 1 and ground or CLEAR
		local low = sections(triangles, bottom + SLAB + 0.03)
		local high = sections(triangles, math.min(size.Y / 2 - 0.03, bottom + SLAB + clear + SLAB - 0.03))
		local loose, tight = table.create(nx*nz,"0"), table.create(nx*nz,"0")
		local count = 0
		for i = 1, nx do
			for j = 1, nz do
				local x0, z0 = grid.minX + (i-1)*cell, grid.minZ + (j-1)*cell
				local x1, z1 = math.min(x0+cell,size.X/2), math.min(z0+cell,size.Z/2)
				local function fits(layer)
					return inside(layer,x0+0.05,z0+0.05) and inside(layer,x1-0.05,z0+0.05)
						and inside(layer,x0+0.05,z1-0.05) and inside(layer,x1-0.05,z1-0.05)
						and inside(layer,(x0+x1)/2,(z0+z1)/2)
				end
				local idx = (i-1)*nz+j
				if fits(low) then
					loose[idx] = "1"; count += 1
					if fits(high) then tight[idx] = "1" end
				end
			end
		end
		grid.occ[k], grid.occTight[k] = table.concat(loose), table.concat(tight)
		occupied += count
		if count >= 4 then filledFloors += 1 end
	end
	if filledFloors < math.ceil(floors * 0.6) or not grid.occ[1]:find("1") then return nil, "No continuous enclosed interior" end
	if occupied * cell * cell / floors < 150 then return nil, "Insufficient usable floor area" end
	return {cf=cf,size=size,grid=grid,cells=occupied}
end

local function sourceKey(g)
	local p = (g.min+g.max)/2
	return string.format("%d_%d_%d_%d",g.meshIndex,math.round(p.X*10),math.round(p.Y*10),math.round(p.Z*10))
end

function Auto.Preview(components)
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	local plans, rejected = {}, 0
	local existing = {}
	for _, b in workspace.Buildings:GetChildren() do
		if b:IsA("Model") and b:FindFirstChild("Interior") then
			local cf, size = b:GetBoundingBox()
			table.insert(existing,{cf=cf,size=size,key=b:GetAttribute("ShibuyaSourceKey")})
		end
	end
	for i,g in components do
		local key, overlaps = sourceKey(g), false
		for _, b in existing do
			local p=b.cf.Position
			if b.key==key or (p.X>=g.min.X and p.X<=g.max.X and p.Z>=g.min.Z and p.Z<=g.max.Z
				and p.Y>=g.min.Y and p.Y<=g.max.Y) then overlaps=true; break end
		end
		if not overlaps then
			local plan = Auto.Sample(g)
			if plan then plan.key=key; plan.component=i; table.insert(plans,plan) else rejected += 1 end
		end
		if i % 40 == 0 then print("SHIBUYA_PREVIEW_PROGRESS",i,#components,#plans); task.wait() end
	end
	print("SHIBUYA_PREVIEW_DONE",#plans,"ready",rejected,"rejected")
	return plans
end

function Auto.Generate(plans, generator, first, last)
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	generator = generator or require(script.Parent.BuildingGenerator)
	local generated, failed = 0, 0
	for i=first or 1,math.min(last or #plans,#plans) do
		local p=plans[i]
		local name="BuildingAuto_"..p.key
		if workspace.Buildings:FindFirstChild(name) then continue end
		local b=Instance.new("Model")
		b.Name=name
		b:SetAttribute("ShibuyaSourceKey",p.key)
		b:SetAttribute("StructuralOnly",true)
		b:SetAttribute("FloorCountBasis","Estimated from imported height at 5m floor pitch")
		b:SetAttribute("InteriorBBoxCFrame",p.cf)
		b:SetAttribute("InteriorBBoxSize",p.size)
		b:SetAttribute("InteriorGrid",HttpService:JSONEncode(p.grid))
		local ok,result=pcall(generator.Generate,b)
		if ok and result then b.Parent=workspace.Buildings; generated+=1
		else b:Destroy(); failed+=1; warn("SHIBUYA_FAILED",name,result) end
		if i%10==0 then print("SHIBUYA_GENERATE_PROGRESS",i,#plans,generated,failed); task.wait() end
	end
	print("SHIBUYA_GENERATE_DONE",generated,failed)
	return generated,failed
end

return Auto
