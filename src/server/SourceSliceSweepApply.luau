--!nonstrict
-- Apply one chunk of the whole-map sweep: stage, bind, replace, crown.
--
-- The four hand-driven sectors were applied with ad-hoc execute_luau calls, and
-- that is how a stage was once mislabelled and nearly replaced the wrong 46
-- greys. ~1,000 buildings cannot be done that way. This is the same sequence --
-- Builder.StagePlans -> Replacement.Capture -> Replacement.Apply -> crowns --
-- with the two rules that incident produced built in:
--
--   1. The LOCK FOLDER IS THE FIRST STATEMENT. execute_luau replays; a replayed
--      call finds the lock and returns the first run's summary instead of
--      building a second stage over the same ground.
--   2. THE STAGE IS NEVER FOUND BY SEARCHING. StagePlans returns the folder and
--      that handle is held; counts are asserted against the plan list before
--      anything is bound or moved.
--
-- The chunk comes over HTTP from tools/source_slice_sink.py rather than through
-- the call, because a chunk with its crowns is megabytes.
--
--   require(...SourceSliceSweepApply).Run("chunk_01")
--   require(...SourceSliceSweepApply).Status()
--
-- Edit mode only. Nothing here runs at game start.
local Sweep = {}

local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local Run = game:GetService("RunService")
local Collection = game:GetService("CollectionService")

local Builder = require(script.Parent.SourceSliceBuilder)
local Replacement = require(script.Parent.SourceSliceReplacement)
local CrownParapet = require(script.Parent.CrownParapet)
local TriangleShell = require(script.Parent.TriangleShell)

local SINK = "http://127.0.0.1:58999/get/tools/source_slices/sweep/chunks/"
local LOCK_PREFIX = "SweepApplyLock_"
local SHELL_THICKNESS = 10.0   -- picked by eye against 4; at 4 the faces still read separately
local NO_CSG = "NoCSG"

local function editOnly()
	assert(not Run:IsRunning(), "Edit mode only -- stop the playtest first")
end

local function buildings()
	local folder = workspace:FindFirstChild("Buildings")
	assert(folder, "workspace.Buildings is missing")
	return folder
end

local function fetch(chunk)
	local url = SINK .. chunk .. ".json"
	local ok, body = pcall(function() return Http:GetAsync(url, true) end)
	assert(ok, "Could not reach the sink at " .. url .. " -- is tools/source_slice_sink.py running? "
		.. tostring(body))
	local decoded
	ok, decoded = pcall(function() return Http:JSONDecode(body) end)
	assert(ok, "Chunk JSON did not decode: " .. tostring(decoded))
	assert(type(decoded.plans) == "table" and #decoded.plans > 0, "Chunk carries no plans")
	return decoded
end

-- A plan is skipped, not failed, when the ground it covers is already done or
-- has moved under it. Sectors overlapped and re-offered live buildings before;
-- a sweep re-run after a partial apply does the same thing.
local function selectable(chunk, live)
	local kept, skipped = {}, {}
	for _, plan in chunk.plans do
		local reason
		if live:FindFirstChild("BuildingSourceSlice_" .. plan.id) then
			reason = "already live"
		else
			for _, name in plan.sourceInfo.replaces do
				local grey = live:FindFirstChild(name)
				if not grey then
					reason = "grey missing: " .. name
					break
				end
			end
		end
		if reason then
			table.insert(skipped, plan.id .. " (" .. reason .. ")")
		else
			table.insert(kept, plan)
		end
	end
	return kept, skipped
end

local function sourcesFor(plans, live)
	local sources, seen = {}, {}
	for _, plan in plans do
		for _, name in plan.sourceInfo.replaces do
			assert(not seen[name], "Two plans in this chunk claim " .. name)
			seen[name] = true
			table.insert(sources, live:FindFirstChild(name))
		end
	end
	return sources
end

local function centroid(triangles)
	local sum, n = Vector3.zero, 0
	for _, triangle in triangles do
		for _, v in triangle do
			sum += Vector3.new(v[1], v[2], v[3])
			n += 1
		end
	end
	assert(n > 0, "Empty crown")
	return sum / n
end

-- Parapet by default, filled wedge shell where the crown earned it. The split
-- is decided offline (source_slice_crown_parapets.py) and arrives in the chunk.
local function crown(model, id, chunk, metrics)
	local parapet = chunk.parapets and chunk.parapets[id]
	local triangles = chunk.crowns and chunk.crowns[id]
	local interesting = parapet and parapet.interesting

	-- Tall AND interesting: build nothing and say so. A shell here costs 355
	-- parts against a parapet's 10 and reads as gapped plates, because the scan
	-- it is cut from is 86% open edges. These roofs get designed by hand, so the
	-- building carries the note instead of a guess.
	if parapet and parapet.manual then
		model:SetAttribute("CrownNeedsManualDesign",
			(parapet.why ~= "" and parapet.why or "interesting rooftop")
			.. string.format(" | %.0f stud building, %.0f stud crown band",
				parapet.buildingHeight or 0, parapet.bandHeight or 0))
		metrics.manual += 1
		return
	end

	if interesting and type(triangles) == "table" and #triangles > 0 then
		model:SetAttribute("CrownInteresting", parapet.why ~= "" and parapet.why or "interesting")
		local ok, err = pcall(function()
			local _, made = TriangleShell.Build(model, triangles, {
				thickness = SHELL_THICKNESS,
				-- The outer face stays on the triangle and the thickness grows
				-- inward, so filling does not fatten the silhouette.
				fillToward = centroid(triangles),
				tag = NO_CSG,
			})
			metrics.shellParts += made.wedges
		end)
		if ok then
			metrics.shells += 1
			return
		end
		metrics.crownFailed += 1
		metrics.notes[#metrics.notes + 1] = id .. " shell: " .. tostring(err)
		return
	end

	if type(parapet) == "table" and type(parapet.pieces) == "table" and #parapet.pieces > 0 then
		local ok, err = pcall(function()
			-- CrownParapet.Build returns metrics ONLY; TriangleShell.Build
			-- returns (parts, metrics). Do not unify these from memory.
			local made = CrownParapet.Build(model, parapet, {tag = NO_CSG})
			metrics.parapetParts += made.parts
		end)
		if ok then
			metrics.parapets += 1
			return
		end
		metrics.crownFailed += 1
		metrics.notes[#metrics.notes + 1] = id .. " parapet: " .. tostring(err)
		return
	end
	metrics.crownless += 1
end

function Sweep.Status()
	local rows = {}
	for _, child in Storage:GetChildren() do
		if child.Name:sub(1, #LOCK_PREFIX) == LOCK_PREFIX then
			table.insert(rows, string.format("%s %s %s", child.Name:sub(#LOCK_PREFIX + 1),
				child:GetAttribute("Done") and "done" or "IN FLIGHT",
				tostring(child:GetAttribute("Summary"))))
		end
	end
	table.sort(rows)
	return table.concat(rows, "\n")
end

-- Stage and bind a chunk, show it, and stop. Nothing is replaced and no grey
-- moves, so the map owner can look at a neighbourhood before it is committed.
-- Follow with Sweep.Commit(chunkName), or Sweep.Discard(chunkName).
function Sweep.Preview(chunkName)
	return Sweep.Run(chunkName, {preview = true})
end

function Sweep.Commit(chunkName)
	editOnly()
	local lock = Storage:FindFirstChild(LOCK_PREFIX .. chunkName)
	assert(lock, "No lock for " .. chunkName .. " -- nothing was staged")
	assert(not lock:GetAttribute("Done"), chunkName .. " is already applied")
	-- The stage is named on the lock by the run that created it. Still never a
	-- search: this is the handle that run recorded, not a guess about which
	-- folder looks right.
	local stageName = lock:GetAttribute("Stage")
	assert(type(stageName) == "string", "That lock records no stage")
	local stage = assert(Storage:FindFirstChild(stageName), "Stage " .. stageName .. " is gone")

	Replacement.Restore(stage)          -- take the preview out of Workspace first
	local archive = Replacement.Apply(stage)
	lock:SetAttribute("Archive", archive.Name)

	local live = buildings()
	local chunk = fetch(chunkName)
	local metrics = {shells = 0, parapets = 0, crownless = 0, crownFailed = 0,
		shellParts = 0, parapetParts = 0, manual = 0, notes = {}}
	local record = assert(lock:FindFirstChild("StagedIds"), "That lock records no staged plans")
	local staged = Http:JSONDecode(record.Value)
	local crowned = 0
	for _, id in staged do
		local model = live:FindFirstChild("BuildingSourceSlice_" .. id)
		if model and not model:GetAttribute("SweepCrowned") then
			crown(model, id, chunk, metrics)
			model:SetAttribute("SweepCrowned", true)
			crowned += 1
			if crowned % 5 == 0 then task.wait() end
		end
	end
	local summary = string.format("committed %d crowned | %d shells (%d parts), "
		.. "%d parapets (%d parts), %d left for manual design, %d bare, %d failed",
		crowned, metrics.shells, metrics.shellParts, metrics.parapets,
		metrics.parapetParts, metrics.manual, metrics.crownless, metrics.crownFailed)
	lock:SetAttribute("Summary", summary)
	lock:SetAttribute("Done", true)
	lock:SetAttribute("Finished", os.time())
	return chunkName .. ": " .. summary
end

-- Throw away a previewed chunk: restore the preview, destroy the stage and the
-- lock, so the chunk can be regenerated and run again from scratch.
function Sweep.Discard(chunkName)
	editOnly()
	local lock = assert(Storage:FindFirstChild(LOCK_PREFIX .. chunkName), "No such lock")
	assert(not lock:GetAttribute("Done"), "That chunk is applied; use the archive to roll back")
	local stageName = lock:GetAttribute("Stage")
	local stage = type(stageName) == "string" and Storage:FindFirstChild(stageName)
	if stage then
		-- A Run that failed AFTER Apply -- during crowning, say -- leaves the lock
		-- open over a stage whose greys are already archived. Destroying that
		-- stage would take the binding, and the binding is the only record of
		-- which archive holds them. Refuse; the archive is the way back.
		assert(not stage:GetAttribute("SourceSliceReplacementApplied"),
			"Stage " .. stageName .. " is already applied -- its greys are in "
			.. "ServerStorage.ShibuyaBeforeSourceSlice_*. Roll that back instead of discarding.")
		pcall(function() Replacement.Restore(stage) end)
		stage:Destroy()
	end
	lock:Destroy()
	return "discarded " .. chunkName
end

-- The entry a rim needs, read back from the plan the building was built from.
-- Every source-slice model carries its canonical plan as SourceSlicePlan, so a
-- retrofit never depends on chunk files being present.
local function rimEntryFor(model)
	local raw = model:GetAttribute("SourceSlicePlan")
	if type(raw) ~= "string" then return nil end
	local plan = Http:JSONDecode(raw)
	local last = plan.levels[#plan.levels]
	return {yaw = plan.origin.yaw or 0, ox = plan.origin.x, oz = plan.origin.z,
		y = plan.origin.y + last.y + (last.thickness or 0), pieces = last.pieces}
end

-- Replace every SOLID parapet with a rim. Skips buildings still carrying a shell
-- crown (the older, hand-approved sector crowns) and those left for manual
-- design. Idempotent: a building that already has a rim is left alone, so a
-- replayed call does nothing twice.
function Sweep.RimAll(options)
	editOnly()
	options = options or {}   -- options.replace: rebuild existing rims too (e.g. after a height change)
	local live = buildings()
	local metrics = {buildings = 0, removed = 0, rimParts = 0, skippedShell = 0,
		skippedManual = 0, already = 0, failed = 0}
	local notes = {}
	for index, model in live:GetChildren() do
		if not model.Name:match("^BuildingSourceSlice_") then continue end
		if model:GetAttribute("CrownNeedsManualDesign") then
			metrics.skippedManual += 1
			continue
		end
		local solid, hasShell, hasRim = {}, false, false
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				if d:GetAttribute("ShellWedge") then hasShell = true
				elseif d:GetAttribute("ParapetRim") then hasRim = true
				elseif d:GetAttribute("CrownParapet") then table.insert(solid, d) end
			end
		end
		if hasShell then metrics.skippedShell += 1; continue end
		if hasRim and not options.replace then metrics.already += 1; continue end
		if hasRim then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d:GetAttribute("ParapetRim") then table.insert(solid, d) end
			end
		end
		local entry = rimEntryFor(model)
		if not entry then metrics.failed += 1; continue end
		local ok, made = pcall(CrownParapet.BuildRim, model, entry, {tag = NO_CSG})
		if ok and made.parts > 0 then
			for _, d in solid do d:Destroy() end
			metrics.removed += #solid
			metrics.rimParts += made.parts
			metrics.buildings += 1
		else
			metrics.failed += 1
			if #notes < 5 then table.insert(notes, model.Name .. ": " .. tostring(ok and made.lastError or made)) end
		end
		if index % 25 == 0 then task.wait() end
	end
	return string.format("rims on %d buildings (%d solid parts -> %d rim parts) | already %d, shell kept %d, manual %d, failed %d%s",
		metrics.buildings, metrics.removed, metrics.rimParts, metrics.already, metrics.skippedShell,
		metrics.skippedManual, metrics.failed, #notes > 0 and (" | " .. table.concat(notes, "; ")) or "")
end

-- Rebuild LIVE buildings from regenerated plans (a "rebuild_NN" chunk). Each new
-- building is built and audited on its own before anything moves; the old model
-- goes to an archive folder, never deleted, and the new one gets a rim. The
-- plan's greys were archived by the original apply, so this swaps building for
-- building rather than going through Replacement.Capture, which binds greys.
function Sweep.Rebuild(chunkName, options)
	editOnly()
	options = options or {}
	-- options.inPlace: DESTROY the old model instead of archiving it. Chosen by
	-- the map owner once the place was backed up (GitHub release
	-- place-files-2026-09-21 + Roblox version history): Studio holds ~26 KB a
	-- part, and archiving ~2,000 old buildings would exceed the machine's memory.
	-- Every old plan is still in the repo, so any building rebuilds exactly.
	local lock = Storage:FindFirstChild(LOCK_PREFIX .. chunkName)
	if lock then
		return string.format("REPLAY %s: %s", chunkName, tostring(lock:GetAttribute("Summary")))
	end
	lock = Instance.new("Folder")
	lock.Name = LOCK_PREFIX .. chunkName
	lock.Parent = Storage

	local live = buildings()
	local chunk = fetch(chunkName)
	local archive = Instance.new("Folder")
	archive.Name = "SweepRebuiltOld_" .. chunkName
	archive.Parent = Storage
	local rebuilt, rejected, missing = 0, {}, 0
	for index, plan in chunk.plans do
		local old = live:FindFirstChild("BuildingSourceSlice_" .. plan.id)
		if not old then
			missing += 1
			continue
		end
		local ok, fresh = pcall(Builder.Build, plan)
		if ok then
			local audit = Builder.Audit(fresh)
			if audit.summary.badBuildings > 0 then
				ok, fresh = false, tostring(audit.badModels[1].reasons[1])
			end
		end
		if not ok then
			table.insert(rejected, plan.id .. " :: " .. tostring(fresh))
			continue
		end
		-- Carry the notes a human may have left on the old building.
		for _, key in {"CrownNeedsManualDesign", "CrownInteresting"} do
			local value = old:GetAttribute(key)
			if value ~= nil then fresh:SetAttribute(key, value) end
		end
		if options.inPlace then
			old:Destroy()
		else
			old.Parent = archive
		end
		fresh.Parent = live
		if not fresh:GetAttribute("CrownNeedsManualDesign") then
			local entry = rimEntryFor(fresh)
			if entry then pcall(CrownParapet.BuildRim, fresh, entry, {tag = NO_CSG}) end
		end
		fresh:SetAttribute("SweepCrowned", true)
		rebuilt += 1
		if index % 5 == 0 then task.wait() end
	end
	if options.inPlace then archive:Destroy() end
	local summary = string.format("rebuilt %d, rejected %d, not live %d | old models %s%s",
		rebuilt, #rejected, missing, options.inPlace and "replaced in place" or ("in " .. archive.Name),
		#rejected > 0 and (" | REJECTED: " .. table.concat(rejected, "; ")) or "")
	lock:SetAttribute("Summary", summary)
	lock:SetAttribute("Done", true)
	return chunkName .. ": " .. summary
end

-- ADD buildings the map never had (an "orphans_NN" chunk from
-- source_slice_orphans.py): the FBX has them, but no grey was ever over them,
-- so the grey-driven pipeline never looked. Shibuya PARCO was one. A plan may
-- still list greys inside its footprint (fragments, or greys whose walls never
-- closed); those are archived, not deleted. Each building is audited on its own
-- before anything moves, and gets a rim.
function Sweep.Add(chunkName)
	editOnly()
	local lock = Storage:FindFirstChild(LOCK_PREFIX .. chunkName)
	if lock then
		return string.format("REPLAY %s: %s", chunkName, tostring(lock:GetAttribute("Summary")))
	end
	lock = Instance.new("Folder")
	lock.Name = LOCK_PREFIX .. chunkName
	lock.Parent = Storage

	local live = buildings()
	local chunk = fetch(chunkName)
	local archive = Instance.new("Folder")
	archive.Name = "SweepAddedOverGreys_" .. chunkName
	archive.Parent = Storage
	local added, greys, rejected, already = 0, 0, {}, 0
	for index, plan in chunk.plans do
		if live:FindFirstChild("BuildingSourceSlice_" .. plan.id) then
			already += 1
			continue
		end
		local ok, fresh = pcall(Builder.Build, plan)
		if ok then
			local audit = Builder.Audit(fresh)
			if audit.summary.badBuildings > 0 then
				ok, fresh = false, tostring(audit.badModels[1].reasons[1])
			end
		end
		if not ok then
			table.insert(rejected, plan.id .. " :: " .. tostring(fresh))
			continue
		end
		for _, name in (plan.sourceInfo and plan.sourceInfo.replaces) or {} do
			local grey = live:FindFirstChild(name)
			if grey then
				grey.Parent = archive
				greys += 1
			end
		end
		fresh:SetAttribute("SweepOrphan", true)
		fresh.Parent = live
		local entry = rimEntryFor(fresh)
		if entry then pcall(CrownParapet.BuildRim, fresh, entry, {tag = NO_CSG}) end
		fresh:SetAttribute("SweepCrowned", true)
		added += 1
		if index % 5 == 0 then task.wait() end
	end
	local summary = string.format("added %d, greys archived %d, already live %d, rejected %d%s",
		added, greys, already, #rejected,
		#rejected > 0 and (" | " .. table.concat(rejected, "; ")) or "")
	lock:SetAttribute("Summary", summary)
	lock:SetAttribute("Done", true)
	return chunkName .. ": " .. summary
end

-- Remove every building added by an earlier orphan pass, before adding the
-- regenerated set. Identified by the SweepOrphan attribute Sweep.Add sets.
function Sweep.RemoveOrphans()
	editOnly()
	local n = 0
	for _, m in buildings():GetChildren() do
		if m:GetAttribute("SweepOrphan") then
			m:Destroy()
			n += 1
		end
	end
	return "removed " .. n .. " orphan buildings"
end

function Sweep.Run(chunkName, options)
	editOnly()
	options = options or {}
	assert(type(chunkName) == "string" and #chunkName > 0, "Name the chunk, e.g. chunk_01")

	-- FIRST statement that touches the datamodel: the replay guard.
	local lock = Storage:FindFirstChild(LOCK_PREFIX .. chunkName)
	if lock then
		return string.format("REPLAY %s: %s (%s)", chunkName,
			tostring(lock:GetAttribute("Summary")),
			lock:GetAttribute("Done") and "finished" or "IN FLIGHT -- inspect before rerunning")
	end
	lock = Instance.new("Folder")
	lock.Name = LOCK_PREFIX .. chunkName
	lock:SetAttribute("Started", os.time())
	lock:SetAttribute("Done", false)
	lock.Parent = Storage

	local ok, result = pcall(function()
		local live = buildings()
		local chunk = fetch(chunkName)
		local plans, skipped = selectable(chunk, live)
		if #plans == 0 then
			return string.format("nothing to do: %d plans all skipped", #skipped)
		end

		-- Hold the handle StagePlans returns. Never search for the stage.
		local stage, failures = Builder.StagePlans(plans)
		lock:SetAttribute("Stage", stage.Name)

		-- Audit BEFORE binding. Replacement.Capture audits the stage too, but it
		-- rejects the whole stage, so one building costs a chunk of 25: measured
		-- on chunk_01, 24 were good and a single native-slab overlap of 0.5185
		-- sq studs took all of them down. Drop the failures, name them, and bind
		-- the rest. Nothing is loosened here -- a building that fails the audit
		-- is still never applied.
		local rejected = {}
		local audit = Builder.Audit(stage)
		if #audit.badModels > 0 then
			local bad = {}
			for _, row in audit.badModels do
				bad[row.name] = true
				table.insert(rejected, row.name .. " :: " .. tostring(row.reasons[1]))
				row.model:Destroy()
			end
			local keep = {}
			for _, plan in plans do
				if not bad["BuildingSourceSlice_" .. plan.id] then table.insert(keep, plan) end
			end
			plans = keep
		end
		assert(#plans > 0, "every building in this chunk failed the audit: "
			.. table.concat(rejected, "; "))
		-- Record WHICH plans were staged, not just how many. Commit crowns from
		-- this list: a chunk can contain plans that were skipped because they are
		-- already live, and crowning those would put a second crown on a building
		-- the sector runs already finished.
		local staged = Instance.new("StringValue")
		staged.Name = "StagedIds"
		local ids = table.create(#plans)
		for _, plan in plans do table.insert(ids, plan.id) end
		staged.Value = Http:JSONEncode(ids)
		staged.Parent = lock
		local built = #stage:GetChildren()
		assert(built == #plans, string.format(
			"stage holds %d models for %d plans (%d build failures) -- not binding",
			built, #plans, #failures))

		local sources = sourcesFor(plans, live)
		local binding = Replacement.Capture(stage, sources)
		assert(binding.outputs == #plans, string.format(
			"Capture bound %d outputs for %d plans", binding.outputs, #plans))
		assert(binding.sources == #sources, string.format(
			"Capture bound %d sources for %d greys", binding.sources, #sources))

		if options.preview then
			Replacement.Preview(stage)
			local note = #rejected > 0
				and string.format(" | %d REJECTED by audit: %s", #rejected,
					table.concat(rejected, "; ")) or ""
			return string.format("PREVIEW %d buildings over %d greys, %d skipped%s -- "
				.. "look, then Sweep.Commit(\"%s\") or Sweep.Discard(\"%s\")",
				#plans, #sources, #skipped, note, chunkName, chunkName)
		end

		local archive = Replacement.Apply(stage)
		lock:SetAttribute("Archive", archive.Name)

		local metrics = {shells = 0, parapets = 0, crownless = 0, crownFailed = 0,
			shellParts = 0, parapetParts = 0, manual = 0, notes = {}}
		for index, plan in plans do
			local model = live:FindFirstChild("BuildingSourceSlice_" .. plan.id)
			if model then
				crown(model, plan.id, chunk, metrics)
				model:SetAttribute("SweepCrowned", true)
			else
				metrics.crownless += 1
			end
			if index % 5 == 0 then task.wait() end
		end

		local summary = string.format(
			"%d applied, %d greys archived, %d skipped | crowns: %d shells (%d parts), "
			.. "%d parapets (%d parts), %d left for manual design, %d bare, %d failed",
			#plans, #sources, #skipped, metrics.shells, metrics.shellParts,
			metrics.parapets, metrics.parapetParts, metrics.manual, metrics.crownless,
			metrics.crownFailed)
		if #rejected > 0 then
			summary ..= string.format(" | %d REJECTED by audit: %s", #rejected,
				table.concat(rejected, "; "))
		end
		if #metrics.notes > 0 then
			summary ..= " | " .. table.concat(metrics.notes, "; ")
		end
		return summary
	end)

	if not ok then
		lock:SetAttribute("Summary", "FAILED: " .. tostring(result))
		lock:SetAttribute("Failed", true)
		error(result, 0)
	end
	lock:SetAttribute("Summary", result)
	-- A preview has replaced nothing, so the lock stays open for Commit. It
	-- still guards against a replayed call building a second stage.
	if not options.preview then
		lock:SetAttribute("Done", true)
		lock:SetAttribute("Finished", os.time())
	end
	return chunkName .. ": " .. result
end

return Sweep
