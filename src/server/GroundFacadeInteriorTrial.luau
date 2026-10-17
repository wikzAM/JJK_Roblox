-- Compatibility entry point. The owner clarified that recesses belong to whole
-- facade bays. Never recreate the obsolete per-window trapezoidal cells.
local T={}
function T.Apply(models,options)
	return require(script.Parent.GroundFacadeBayInteriors).ApplyBatch(models,options)
end
return T
