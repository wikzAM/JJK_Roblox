local ClickInput = require(script.ClickInput)
local FacadeRenderer = require(script.FacadeRenderer)

ClickInput.Init()
task.spawn(FacadeRenderer.Init)   -- waits for Buildings and GlassDamageEvent
task.spawn(require(script.GlassDemo).Init) -- isolated review platform; no input required

print("[Client] All modules initialized.")
