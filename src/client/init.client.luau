local ClickInput = require(script.ClickInput)
local FacadeRenderer = require(script.FacadeRenderer)

ClickInput.Init()
task.spawn(FacadeRenderer.Init)   -- waits for Buildings and FacadeHitEvent; must not hold up the rest

print("[Client] All modules initialized.")
