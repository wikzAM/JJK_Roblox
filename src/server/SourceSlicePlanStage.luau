--!nonstrict
-- Bridge between the offline plan generator and SourceSliceBuilder.
--
-- tools/source_slice_plan_builder.py writes builder-ready plans as JSON to
-- tools/source_slices/plans/*.json. SourceSliceBuilder.StagePlans wants Lua
-- tables, so this decodes JSON and hands them over. Stage only: there is no
-- Apply path here, exactly as in the sample modules.
--
-- The JSON arrives one of two ways:
--   * MCP / Command Bar: Stage(jsonString) with one plan or an array of plans.
--   * A StringValue parked in ServerStorage, so a large batch does not have to
--     fit in a single command line: StageFromStorage("SourceSlicePlansJson").
--
-- Plans are candidates, not verified geometry. Preview before trusting any of
-- them, and never Apply a batch without reviewing the individual overlays.
local Stage = {}

local Http = game:GetService("HttpService")
local Storage = game:GetService("ServerStorage")
local Builder = require(script.Parent.SourceSliceBuilder)

local REVIEW = "SourceSliceReview_Batch"

local function decode(text)
	assert(type(text) == "string" and #text > 0, "Pass the plan JSON as a string")
	local ok, decoded = pcall(function() return Http:JSONDecode(text) end)
	assert(ok, "Plan JSON did not decode: " .. tostring(decoded))
	-- Accept a bare plan as well as an array of them.
	if decoded.id and decoded.levels then decoded = {decoded} end
	assert(type(decoded) == "table" and #decoded > 0, "No plans in that JSON")
	return decoded
end

-- JSONDecode gives levels[].pieces[][] as arrays of two numbers, which is the
-- shape the builder already expects, so only light structural checks are needed
-- before handing over. The builder does the real validation.
local function check(plans)
	for index, plan in plans do
		assert(type(plan.id) == "string", "Plan " .. index .. " has no id")
		assert(type(plan.origin) == "table", "Plan " .. plan.id .. " has no origin")
		assert(type(plan.levels) == "table" and #plan.levels >= 2,
			"Plan " .. plan.id .. " needs at least 2 levels")
		assert(type(plan.core) == "table", "Plan " .. plan.id .. " has no core")
	end
	return plans
end

function Stage.Hide()
	local folder = workspace:FindFirstChild(REVIEW)
	if folder then folder:Destroy() end
	return true
end

-- Stages into ServerStorage and returns a summary. Nothing enters Workspace
-- unless Preview is called.
function Stage.Stage(text)
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	local plans = check(decode(text))
	local stage, failures = Builder.StagePlans(plans)
	stage:SetAttribute("SourceSlicePlanBatch", true)
	local audit = Builder.Audit(stage)
	local summary = {
		stage = stage.Name,
		staged = #stage:GetChildren(),
		failed = #failures,
		wedges = audit.summary.wedges,
		slabParts = audit.summary.slabParts,
		structuralParts = audit.summary.structuralParts,
		badBuildings = audit.summary.badBuildings,
	}
	if #failures > 0 then
		summary.firstFailure = failures[1].id .. ": " .. failures[1].reason
	end
	print("SOURCE_SLICE_PLAN_BATCH", Http:JSONEncode(summary))
	return summary
end

function Stage.StageFromStorage(name)
	local holder = assert(Storage:FindFirstChild(name or "SourceSlicePlansJson"),
		"No StringValue named " .. tostring(name or "SourceSlicePlansJson") .. " in ServerStorage")
	assert(holder:IsA("StringValue"), "That instance is not a StringValue")
	return Stage.Stage(holder.Value)
end

-- Copies staged buildings into Workspace in review orange so they can be
-- compared against the red FBX and the grey live models.
function Stage.Preview(stageName, ids)
	assert(not game:GetService("RunService"):IsRunning(), "Stop playtest first")
	Stage.Hide()
	local source = assert(Storage:FindFirstChild(stageName), "No stage named " .. tostring(stageName))
	local wanted
	if ids then
		wanted = {}
		for _, id in ids do wanted[id] = true end
	end
	local folder = Instance.new("Folder")
	folder.Name = REVIEW
	folder:SetAttribute("SourceSliceReview", true)
	local shown = {}
	for _, model in source:GetChildren() do
		local id = model:GetAttribute("SourceSliceId")
		if wanted and not wanted[id] then continue end
		local copy = model:Clone()
		for _, part in copy:GetDescendants() do
			if part:IsA("BasePart") then
				part.Color = Color3.fromRGB(255, 140, 40)
				part.Material = Enum.Material.SmoothPlastic
			end
		end
		copy.Parent = folder
		table.insert(shown, id)
	end
	folder.Parent = workspace
	print("SOURCE_SLICE_PLAN_PREVIEW", #shown)
	return {previewed = #shown, ids = shown, folder = REVIEW}
end

return Stage
