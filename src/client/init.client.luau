local ClickInput = require(script.ClickInput)
local FacadeRenderer = require(script.FacadeRenderer)

ClickInput.Init()
task.spawn(FacadeRenderer.Init)   -- waits for Buildings and GlassDamageEvent
task.spawn(require(script.GroundFacadeInteriors).Init) -- explicit small opt-in trial
task.spawn(require(script.GlassDemo).Init) -- isolated review platform; no input required
task.spawn(require(script.UpperFacadeRenderer).Init) -- client-built upper-floor facades near the camera
task.spawn(require(script.DummyTracker).Init) -- dummy marker + G to summon
task.spawn(require(script.PlayerMovement).Init) -- no automatic player ragdolls

print("[Client] All modules initialized.")
