--!nonstrict
-- Builds building facades on THIS client, near the camera, and breaks their
-- glass when a hit passes through. The server stores no facade parts at all:
-- ~109k strips map-wide would cost ~700 MB of saved place, and only the ~10k
-- within a camera's reach are ever seen. Layout comes from the shared
-- FacadeLayout (the building's SourceSlicePlan), so every client builds the same
-- facade and breaks the same panes.
--
--   near (BUILD_RADIUS)   one glass strip per wall run per storey, set back
--                         between the slabs; opaque piers on short runs;
--                         parapets where the storey above sets back
--   hit                   FacadeHitEvent(start, finish, radius) from HitHandler:
--                         the strips the capsule touches split into ~12-stud
--                         panes -- gone inside the radius (with local shards),
--                         cracked in the next 6 studs, intact beyond
--
-- Facade parts collide for the local player (you cannot walk through glass)
-- but are CanQuery/CanTouch false, so they never block ClickInput or the
-- server's own queries.
local FacadeRenderer = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Layout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FacadeLayout"))

local BUILD_RADIUS = 700     -- studs: facades are built for buildings within this of the camera
local DROP_RADIUS = 850      -- studs: and dropped beyond this (the gap stops thrashing at the edge)
local FRAME_BUDGET = 0.002   -- seconds of building per frame
local MAX_SPEED = 400        -- studs/s: above this the camera is flying past; do not build
local PANE = 12              -- studs: pane width when a strip is split by a hit
local CRACK_BAND = 6         -- studs beyond the hit radius where panes crack instead of vanishing
local SHARDS_PER_PANE = 3
-- HitHandler's HOLE_RADIUS is 50: one hit knocked out ~109 panes and threw 327
-- unanchored shards at once. Cap the shards per hit; the hole is the same.
local MAX_SHARDS_PER_HIT = 60
local SHARD_LIFETIME = 4

local folder             -- local-only: created by this client, so it never replicates
local farFolder
local built = {}         -- model -> {parts = {part -> strip}, frame = CFrame}
local far = {}           -- model -> holder Model of its coarse far shell (built once, never unloaded)
local pool = {}
local hits = {}          -- this session's hit capsules, re-applied when a building is rebuilt

local function acquire()
	local part = table.remove(pool)
	if not part then
		part = Instance.new("Part")
		part.Anchored = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	part.CanCollide = true
	return part
end

local function release(part)
	part.Parent = nil
	table.insert(pool, part)
end

local function paint(part, kind, style)
	if kind == "glass" then
		part.Material = Enum.Material.Glass
		part.Color = style.glass
		part.Transparency = style.transparency
		part.Reflectance = style.reflectance
	else   -- pier / parapet
		part.Material = Layout.PIER.material
		part.Color = Layout.PIER.color
		part.Transparency = 0
		part.Reflectance = 0
	end
end

-- distance from a point to the segment a-b
local function toSegment(p, a, b)
	local ab = b - a
	local t = ab:Dot(ab) > 0 and math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
	return (p - (a + ab * t)).Magnitude
end

local function shards(cf, size, style, from)
	for _ = 1, SHARDS_PER_PANE do
		local s = Instance.new("WedgePart")
		s.Size = Vector3.new(0.2, math.random() * 2 + 1, math.random() * 2 + 1)
		s.CFrame = cf * CFrame.new((math.random() - 0.5) * size.X, (math.random() - 0.5) * size.Y, 0)
			* CFrame.Angles(math.random() * 6.28, math.random() * 6.28, 0)
		s.Material = Enum.Material.Glass
		s.Color = style.glass
		s.Transparency = 0.3
		s.CanQuery = false
		s.CanTouch = false
		s.CanCollide = false
		s.CastShadow = false
		local away = (s.Position - from)
		away = away.Magnitude > 0 and away.Unit or Vector3.yAxis
		s.AssemblyLinearVelocity = away * (20 + math.random() * 30) + Vector3.new(0, 10, 0)
		s.AssemblyAngularVelocity = Vector3.new(math.random() * 10, math.random() * 10, math.random() * 10)
		s.Parent = folder
		Debris:AddItem(s, SHARD_LIFETIME)
	end
end

-- Break every glass strip of one building that a capsule touches. Returns the
-- number of panes removed.
local function breakBuilding(entry, a, b, r, budget)
	local removed = 0
	for part, strip in entry.parts do
		if strip.kind == "glass" and part.Parent then
			-- quick reject: the strip's centre is further than its half-length plus the reach
			if toSegment(part.Position, a, b) - strip.size.X / 2 < r + CRACK_BAND then
				local cf, size = part.CFrame, part.Size
				local n = math.max(1, math.floor(size.X / PANE + 0.5))
				local w = size.X / n
				local style = entry.style
				entry.parts[part] = nil
				release(part)
				for i = 1, n do
					local pcf = cf * CFrame.new(-size.X / 2 + (i - 0.5) * w, 0, 0)
					local d = toSegment(pcf.Position, a, b)
					if d < r then
						removed += 1
						if budget and budget.n > 0 then
							budget.n -= SHARDS_PER_PANE
							shards(pcf, Vector3.new(w, size.Y, size.Z), style, (a + b) / 2)
						end
					else
						local pane = acquire()
						pane.Size = Vector3.new(w, size.Y, size.Z)
						pane.CFrame = pcf
						paint(pane, "glass", style)
						if d < r + CRACK_BAND then
							pane.Transparency = 0.55
							pane.Color = style.glass:Lerp(Color3.new(1, 1, 1), 0.35)
							pane.Reflectance = 0.05
						end
						pane.Parent = entry.model
						-- a cracked or intact pane is still a strip of its own for the next hit
						entry.parts[pane] = {kind = "glass", size = pane.Size}
					end
				end
			end
		end
	end
	return removed
end

-- Build one building's facade into PARENT. Used by the runtime loop and by the
-- edit-mode preview (which passes its own folder), so the preview shows exactly
-- what clients build.
function FacadeRenderer.BuildInto(parent, model)
	local frame, strips = Layout.ForModel(model)
	if not frame then return nil end
	local entry = {parts = {}, frame = frame, style = Layout.StyleOf(model:GetAttribute("SourceSliceId") or model.Name)}
	local holder = Instance.new("Model")
	holder.Name = model.Name
	entry.model = holder
	for _, s in strips do
		local part = acquire()
		part.Size = s.size
		part.CFrame = frame * s.cframe
		paint(part, s.kind, entry.style)
		part.Parent = holder
		entry.parts[part] = s
	end
	holder.Parent = parent
	-- damage this client has already seen stays: re-apply earlier hits, quietly
	for _, h in hits do
		local piv = model:GetPivot().Position
		if toSegment(piv, h[1], h[2]) < h[3] + 400 then breakBuilding(entry, h[1], h[2], h[3], nil) end
	end
	return entry
end

-- The coarse far shell (FacadeLayout.BuildFarCoarse): ~11 tall panels per
-- building, ~22k for the whole map. Opaque SmoothPlastic in the building's
-- tint -- Glass is the expensive material to render, and at a distance its
-- see-through quality is invisible anyway. No collision, queries or shadows.
function FacadeRenderer.BuildFarInto(parent, model)
	local frame = Layout.FrameOf(model)
	local encoded = model:GetAttribute("SourceSlicePlan")
	if not frame or type(encoded) ~= "string" then return nil end
	local style = Layout.StyleOf(model:GetAttribute("SourceSliceId") or model.Name)
	local holder = Instance.new("Model")
	holder.Name = model.Name
	for _, s in Layout.BuildFarCoarse(game:GetService("HttpService"):JSONDecode(encoded)) do
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = style.glass
		part.Reflectance = style.reflectance * 0.5
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = s.size
		part.CFrame = frame * s.cframe
		part.Parent = holder
	end
	holder.Parent = parent
	return holder
end

-- Edit-mode preview: build into a folder AND register the building, so Break
-- can be tried on it without a playtest (screen capture only works in Edit).
function FacadeRenderer.Preview(parent, model)
	folder = folder or parent
	local entry = FacadeRenderer.BuildInto(parent, model)
	built[model] = entry
	return entry
end

function FacadeRenderer.Drop(model)
	local entry = built[model]
	if not entry then return end
	for part in entry.parts do release(part) end
	entry.model:Destroy()
	built[model] = nil
	if far[model] and farFolder then far[model].Parent = farFolder end   -- the far shell comes back
end

-- A hit: break the glass of every built building near the capsule.
function FacadeRenderer.Break(a, b, r)
	table.insert(hits, {a, b, r})
	local removed = 0
	local budget = {n = MAX_SHARDS_PER_HIT}
	for model, entry in built do
		if toSegment(model:GetPivot().Position, a, b) < r + 400 then
			removed += breakBuilding(entry, a, b, r, budget)
		end
	end
	return removed
end

function FacadeRenderer.Stats()
	local buildings, parts = 0, 0
	for _, entry in built do
		buildings += 1
		for _ in entry.parts do parts += 1 end
	end
	return buildings, parts, #pool
end

function FacadeRenderer.Init()
	folder = Instance.new("Folder")
	folder.Name = "LocalFacades"
	folder.Parent = workspace
	farFolder = Instance.new("Folder")
	farFolder.Name = "LocalFacadesFar"
	farFolder.Parent = workspace

	-- glass broken before this player joined: replay the server's capped log
	-- first, so buildings come up already broken (quietly, no shards)
	local state = ReplicatedStorage:WaitForChild("FacadeState", 10)
	local logged = state and state:GetAttribute("Hits")
	if type(logged) == "string" then
		local ok, rows = pcall(function() return game:GetService("HttpService"):JSONDecode(logged) end)
		if ok and type(rows) == "table" then
			for _, h in rows do
				table.insert(hits, {Vector3.new(h[1], h[2], h[3]), Vector3.new(h[4], h[5], h[6]), h[7]})
			end
		end
	end

	local buildingsFolder = workspace:WaitForChild("Buildings")
	local candidates, farQueue = {}, {}
	local function consider(model)
		if model:IsA("Model") and model:GetAttribute("SourceSlicePlan") and not candidates[model] then
			candidates[model] = true
			table.insert(farQueue, model)   -- every building gets a far shell, including late arrivals
			-- the server changed this building (collapse, Regenerate): it bumps
			-- FacadeVersion, and the facade and far shell are rebuilt from the new plan
			model:GetAttributeChangedSignal("FacadeVersion"):Connect(function()
				FacadeRenderer.Drop(model)
				if far[model] then far[model]:Destroy(); far[model] = nil end
				table.insert(farQueue, model)
			end)
		end
	end
	for _, m in buildingsFolder:GetChildren() do consider(m) end
	buildingsFolder.ChildAdded:Connect(consider)
	buildingsFolder.ChildRemoved:Connect(function(m)
		candidates[m] = nil
		FacadeRenderer.Drop(m)
		if far[m] then far[m]:Destroy(); far[m] = nil end
	end)

	local event = ReplicatedStorage:WaitForChild("FacadeHitEvent", 30)
	if event then
		event.OnClientEvent:Connect(function(a, b, r)
			if typeof(a) == "Vector3" and typeof(b) == "Vector3" and type(r) == "number" then
				FacadeRenderer.Break(a, b, r)
			end
		end)
	end

	local queue, lastScan, lastPos = {}, 0, nil
	RunService.Heartbeat:Connect(function(dt)
		local cam = workspace.CurrentCamera
		if not cam then return end
		local pos = cam.CFrame.Position
		local speed = lastPos and (pos - lastPos).Magnitude / math.max(dt, 1e-3) or 0
		lastPos = pos
		local now = os.clock()
		if now - lastScan > 0.5 then
			lastScan = now
			queue = {}
			for model in candidates do
				local d = (model:GetPivot().Position - pos).Magnitude
				if built[model] then
					if d > DROP_RADIUS then FacadeRenderer.Drop(model) end
				elseif d < BUILD_RADIUS then
					table.insert(queue, {model, d})
				end
			end
			table.sort(queue, function(x, y) return x[2] < y[2] end)   -- closest first
		end
		if speed > MAX_SPEED then return end
		local start = os.clock()
		while #queue > 0 and os.clock() - start < FRAME_BUDGET do
			local model = table.remove(queue, 1)[1]
			if not built[model] and model.Parent then
				built[model] = FacadeRenderer.BuildInto(folder, model)
				if built[model] and far[model] then far[model].Parent = nil end   -- near replaces far
			end
		end
		-- far shells for the whole map, once, in whatever budget the near work left
		while #farQueue > 0 and os.clock() - start < FRAME_BUDGET do
			local model = table.remove(farQueue)
			if model.Parent and not far[model] then
				far[model] = FacadeRenderer.BuildFarInto(farFolder, model)
				if far[model] and built[model] then far[model].Parent = nil end
			end
		end
	end)
end

return FacadeRenderer
