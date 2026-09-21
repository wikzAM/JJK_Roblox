--!nonstrict
-- Explicit, durable replacement ownership. Capture never guesses spatial matches.
-- Restore previews before Apply or saving. Originals are archived, never deleted.
local Replacement = {}
local Storage = game:GetService("ServerStorage")
local Http = game:GetService("HttpService")
local History = game:GetService("ChangeHistoryService")
local Collection = game:GetService("CollectionService")
local BINDINGS = "SourceSliceBindings"
local VERSION = 1

local function editOnly()
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
end

local function buildings()
	return assert(workspace:FindFirstChild("Buildings"), "Workspace.Buildings is missing")
end

local function reference(parent, name, value)
	local link = Instance.new("ObjectValue")
	link.Name, link.Value, link.Parent = name, value, parent
	return link
end

local function identity(model)
	for _, name in {"SourceSliceId", "SourceSliceBuildingId", "ShibuyaSourceKey"} do
		local value = model:GetAttribute(name)
		if type(value) == "string" and value ~= "" then return name, value end
	end
	return nil
end

local function allowedSource(model)
	return model:IsA("Model") and (model.Name:match("^BuildingSmooth_")
		or model.Name:match("^BuildingSourceSlice_"))
end

local function copyAttributes(object, parent)
	local attributes = Instance.new("Folder")
	attributes.Name = "Attributes"
	for name, value in object:GetAttributes() do attributes:SetAttribute(name, value) end
	attributes.Parent = parent
end

local function sameAttributes(object, saved)
	local expected, actual = saved:GetAttributes(), object:GetAttributes()
	for name, value in expected do
		assert(actual[name] == value, "Bound model attribute changed: " .. object.Name .. "." .. name)
	end
	for name in actual do assert(expected[name] ~= nil, "Bound model gained attribute: " .. object.Name .. "." .. name) end
end

local function counts(model)
	local result = {Descendants = 0, Parts = 0, Structural = 0, Cores = 0, Wedges = 0}
	for _, object in model:GetDescendants() do
		result.Descendants += 1
		if object:IsA("BasePart") then
			result.Parts += 1
			if not Collection:HasTag(object, "NoCSG") then result.Structural += 1 end
			if Collection:HasTag(object, "BuildingCore") then result.Cores += 1 end
			if object:IsA("WedgePart") then result.Wedges += 1 end
		end
	end
	return result
end

local PART_PROPERTIES = {"CFrame", "Size", "Anchored", "CanCollide", "CanQuery", "CanTouch",
	"Transparency", "Reflectance", "CastShadow", "CollisionGroup", "Color", "Massless"}

local function snapshot(model, parent, name)
	local row = reference(parent, name, model)
	row:SetAttribute("Name", model.Name)
	row:SetAttribute("Pivot", model:GetPivot())
	local idAttribute, id = identity(model)
	assert(id, "Missing source identity on " .. model.Name)
	row:SetAttribute("IdAttribute", idAttribute)
	row:SetAttribute("Id", id)
	reference(row, "OriginalParent", model.Parent)
	copyAttributes(model, row)
	for key, value in counts(model) do row:SetAttribute("Count" .. key, value) end
	local parts = Instance.new("Folder")
	parts.Name, parts.Parent = "Parts", row
	for _, object in model:GetDescendants() do
		if not object:IsA("BasePart") then continue end
		local saved = reference(parts, string.format("Part%06d", #parts:GetChildren() + 1), object)
		saved:SetAttribute("Name", object.Name)
		saved:SetAttribute("ClassName", object.ClassName)
		saved:SetAttribute("Material", object.Material.Name)
		if object:IsA("Part") then saved:SetAttribute("Shape", object.Shape.Name) end
		for _, property in PART_PROPERTIES do saved:SetAttribute(property, object[property]) end
		reference(saved, "OriginalParent", object.Parent)
	end
	return row
end

local function samePivot(a, b)
	if typeof(a) ~= "CFrame" or typeof(b) ~= "CFrame" then return false end
	local relative = a:ToObjectSpace(b)
	return relative.Position.Magnitude <= 0.03
		and relative.RightVector:Dot(Vector3.xAxis) > 0.99999
		and relative.UpVector:Dot(Vector3.yAxis) > 0.99999
end

local function checkSnapshot(row, expectedParent)
	assert(row:IsA("ObjectValue") and row.Value and row.Value:IsA("Model"), "Bound model reference is missing")
	local model = row.Value
	assert(model.Parent == expectedParent, "Bound model moved: " .. model.Name)
	assert(model.Name == row:GetAttribute("Name"), "Bound model renamed")
	assert(samePivot(model:GetPivot(), row:GetAttribute("Pivot")), "Bound model pivot changed: " .. model.Name)
	assert(row:FindFirstChild("Attributes") and row:FindFirstChild("Parts"), "Incomplete model snapshot")
	sameAttributes(model, row.Attributes)
	for key, value in counts(model) do
		assert(row:GetAttribute("Count" .. key) == value, "Bound model structure count changed: " .. model.Name)
	end
	local seen, total = {}, 0
	for _, saved in row.Parts:GetChildren() do
		assert(saved:IsA("ObjectValue") and saved.Value and saved.Value:IsA("BasePart"), "Bound structural part is missing")
		local part = saved.Value
		assert(not seen[part] and part:IsDescendantOf(model), "Duplicate or relocated bound structural part")
		seen[part], total = true, total + 1
		assert(saved:FindFirstChild("OriginalParent") and part.Parent == saved.OriginalParent.Value,
			"Bound structural part parent changed")
		assert(part.Name == saved:GetAttribute("Name") and part.ClassName == saved:GetAttribute("ClassName"),
			"Bound structural part identity changed")
		assert(part.Material.Name == saved:GetAttribute("Material"), "Bound structural part material changed")
		if part:IsA("Part") then assert(part.Shape.Name == saved:GetAttribute("Shape"), "Bound part shape changed") end
		for _, property in PART_PROPERTIES do
			assert(part[property] == saved:GetAttribute(property), "Bound structural part changed: " .. part.Name .. "." .. property)
		end
	end
	assert(total == row:GetAttribute("CountParts"), "Bound structural snapshot is incomplete")
	return model
end

local function stageModels(stage)
	local result = {}
	for _, child in stage:GetChildren() do
		if child.Name == BINDINGS and child:IsA("Folder") then continue end
		assert(child:IsA("Model") and child.Name:match("^Building"), "Unexpected object in source-slice stage")
		table.insert(result, child)
	end
	assert(#result > 0, "Source-slice stage is empty")
	return result
end

local function auditStage(stage)
	local audit = require(script.Parent.SourceSliceBuilder).Audit(stage)
	assert(type(audit) == "table", "Source-slice builder did not return an audit")
	local summary = audit.summary or audit
	assert(summary.badBuildings == 0, "Source-slice stage failed the builder audit")
	return audit
end

local function bound(stage)
	assert(stage and stage:IsA("Folder") and stage.Parent == Storage, "Pass a stage directly in ServerStorage")
	local binding = stage:FindFirstChild(BINDINGS)
	assert(binding and binding:IsA("Folder") and binding:GetAttribute("Version") == VERSION,
		"Capture an explicit replacement source set first")
	assert(not binding:GetAttribute("Applied"), "Source-slice stage was already applied")
	assert(binding:FindFirstChild("Sources") and binding:FindFirstChild("Outputs"), "Replacement binding is incomplete")
	return binding
end

local function validate(stage, binding)
	assert(not binding:GetAttribute("PreviewActive") and not binding:FindFirstChild("PreviewState"),
		"Restore the source-slice preview before applying or recapturing")
	local live = buildings()
	local sources, outputs, sourceSet, sourceIds, outputIds, names = {}, {}, {}, {}, {}, {}
	local rows = binding.Sources:GetChildren()
	assert(#rows > 0 and #rows == binding:GetAttribute("SourceCount"), "Replacement source set changed")
	for _, row in rows do
		assert(row:FindFirstChild("OriginalParent") and row.OriginalParent.Value == live, "Original building folder changed")
		local model = checkSnapshot(row, live)
		assert(allowedSource(model), "Bound source is not a smooth/source-slice building")
		local id = row:GetAttribute("Id")
		assert(not sourceSet[model] and not sourceIds[id], "Duplicate replacement source or source ID")
		sourceSet[model], sourceIds[id] = true, true
		table.insert(sources, model)
	end
	local modelSet = {}
	for _, model in stageModels(stage) do modelSet[model] = true end
	local outputRows = binding.Outputs:GetChildren()
	assert(#outputRows > 0 and #outputRows == binding:GetAttribute("OutputCount"), "Replacement output set changed")
	for _, row in outputRows do
		assert(row:FindFirstChild("OriginalParent") and row.OriginalParent.Value == stage, "Staged output parent binding changed")
		local model = checkSnapshot(row, stage)
		assert(modelSet[model] and not names[model.Name], "Duplicate or unexpected staged building")
		modelSet[model] = nil
		local id = row:GetAttribute("Id")
		assert(not outputIds[id], "Duplicate replacement output ID")
		outputIds[id], names[model.Name] = true, true
		table.insert(outputs, model)
	end
	assert(next(modelSet) == nil, "Unbound building was added to stage")
	for _, child in live:GetChildren() do
		if sourceSet[child] then continue end
		assert(not names[child.Name], "Replacement name collides with an unbound live building: " .. child.Name)
		local _, id = identity(child)
		assert(not id or not outputIds[id], "Replacement ID is already owned by an unbound live building")
	end
	return sources, outputs
end

function Replacement.Capture(stage, sources)
	editOnly()
	assert(stage and stage:IsA("Folder") and stage.Parent == Storage, "Pass a stage directly in ServerStorage")
	assert(not stage:FindFirstChild(BINDINGS), "Stage already has a replacement binding; create a new stage to rebind")
	assert(type(sources) == "table" and #sources > 0, "Pass a nonempty explicit source-model list")
	local entries = 0
	for index in sources do
		assert(type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #sources, "Source list must be a dense array")
		entries += 1
	end
	assert(entries == #sources, "Source list must be a dense array")
	auditStage(stage)
	local outputs = stageModels(stage)
	local binding = Instance.new("Folder")
	binding.Name = BINDINGS
	binding:SetAttribute("Version", VERSION)
	binding:SetAttribute("Token", Http:GenerateGUID(false))
	binding:SetAttribute("SourceCount", #sources)
	binding:SetAttribute("OutputCount", #outputs)
	binding:SetAttribute("PreviewActive", false)
	local sourceRows, outputRows = Instance.new("Folder"), Instance.new("Folder")
	sourceRows.Name, sourceRows.Parent = "Sources", binding
	outputRows.Name, outputRows.Parent = "Outputs", binding
	local ok, err = pcall(function()
		local live = buildings()
		local seen, ids = {}, {}
		for index, source in sources do
			assert(typeof(source) == "Instance" and allowedSource(source) and source.Parent == live,
				"Every explicit source must be a live smooth/source-slice building")
			local _, id = identity(source)
			assert(id and not ids[id] and not seen[source], "Missing or duplicate replacement source identity")
			ids[id], seen[source] = true, true
			snapshot(source, sourceRows, string.format("Source%04d", index))
		end
		for index, output in outputs do snapshot(output, outputRows, string.format("Output%04d", index)) end
		binding.Parent = stage
		validate(stage, binding)
	end)
	if not ok then binding:Destroy(); error(err, 0) end
	return {sources = #sources, outputs = #outputs, binding = binding}
end

function Replacement.Restore(stage)
	editOnly()
	local binding = bound(stage)
	local state = binding:FindFirstChild("PreviewState")
	if not state then
		assert(not binding:GetAttribute("PreviewActive"), "Preview recovery state is missing")
		return false
	end
	local hidden = assert(state:FindFirstChild("HiddenOriginals"), "Preview original holding folder is missing")
	local live = buildings()
	-- Validate every destination before moving anything. Keep recovery state on failure.
	for _, row in binding.Sources:GetChildren() do
		assert(row.Value and row.OriginalParent.Value == live, "Preview original or destination is missing")
		assert(row.Value.Parent == hidden or row.Value.Parent == live, "Preview original was moved elsewhere")
	end
	for _, row in binding.Sources:GetChildren() do row.Value.Parent = live end
	assert(#hidden:GetChildren() == 0, "Preview holding folder contains an unexpected original; retained for recovery")
	local link = state:FindFirstChild("PreviewFolder")
	if link and link.Value then
		local preview = link.Value
		assert(preview:IsA("Folder") and preview:GetAttribute("SourceSlicePreviewToken") == binding:GetAttribute("Token"),
			"Preview folder ownership changed; retained for recovery")
		preview:Destroy() -- disposable preview clones only
	end
	state:Destroy()
	binding:SetAttribute("PreviewActive", false)
	return true
end

function Replacement.Preview(stage, mode)
	editOnly()
	mode = mode or "after"
	assert(mode == "before" or mode == "after", "Preview mode must be before or after")
	local binding = bound(stage)
	if binding:FindFirstChild("PreviewState") then Replacement.Restore(stage) end
	local sources, outputs = validate(stage, binding)
	if mode == "before" then return {mode = mode, sources = #sources, outputs = #outputs} end
	auditStage(stage)
	local state, hidden, preview = Instance.new("Folder"), Instance.new("Folder"), Instance.new("Folder")
	state.Name, state.Parent = "PreviewState", binding
	hidden.Name, hidden.Parent = "HiddenOriginals", state
	preview.Name = "ShibuyaSourceSlicePreview_" .. binding:GetAttribute("Token")
	preview:SetAttribute("SourceSlicePreviewToken", binding:GetAttribute("Token"))
	reference(state, "PreviewFolder", preview)
	local ok, err = pcall(function()
		for _, output in outputs do
			local copy = assert(output:Clone(), "Staged building is not archivable")
			copy:SetAttribute("SourceSlicePreviewClone", true)
			copy.Parent = preview
		end
		for _, source in sources do source.Parent = hidden end
		preview.Parent = workspace
		binding:SetAttribute("PreviewActive", true)
	end)
	if not ok then
		local restored, restoreError = pcall(Replacement.Restore, stage)
		error(tostring(err) .. (restored and "" or "; preview recovery required: " .. tostring(restoreError)), 0)
	end
	return {mode = mode, sources = #sources, outputs = #outputs, folder = preview}
end

function Replacement.Apply(stage)
	editOnly()
	local binding = bound(stage)
	local sources, outputs = validate(stage, binding)
	local audit = auditStage(stage)
	-- Audit may yield; recheck all durable snapshots immediately before mutation.
	sources, outputs = validate(stage, binding)
	History:SetWaypoint("Before source-slice replacement")
	local live, archive = buildings(), Instance.new("Folder")
	archive.Name = "ShibuyaBeforeSourceSlice_" .. Http:GenerateGUID(false)
	archive:SetAttribute("ReplacementToken", binding:GetAttribute("Token"))
	archive:SetAttribute("ReplacedSourceCount", #sources)
	archive:SetAttribute("GeneratedBuildingCount", #outputs)
	archive.Parent = Storage
	local moved = {}
	local ok, err = pcall(function()
		for _, source in sources do
			source.Parent = archive
			table.insert(moved, {object = source, parent = live})
		end
		for _, output in outputs do
			output.Parent = live
			table.insert(moved, {object = output, parent = stage})
		end
	end)
	if not ok then
		local rollbackErrors = {}
		for index = #moved, 1, -1 do
			local item = moved[index]
			local restored, why = pcall(function() item.object.Parent = item.parent end)
			if not restored then table.insert(rollbackErrors, tostring(why)) end
		end
		if #archive:GetChildren() == 0 then archive:Destroy() end
		error(tostring(err) .. (#rollbackErrors == 0 and "; all moves rolled back"
			or "; originals retained, rollback requires attention: " .. table.concat(rollbackErrors, "; ")), 0)
	end
	reference(binding, "Archive", archive)
	binding:SetAttribute("Applied", true)
	stage:SetAttribute("SourceSliceReplacementApplied", true)
	History:SetWaypoint("Source-slice replacement")
	return archive, audit
end

return Replacement
