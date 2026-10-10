-- Standalone demonstration place. No combat, city, terrain or generator modules.
local gallery=Instance.new("Folder");gallery.Name="GroundFacadeDraftGallery"
gallery:SetAttribute("Origin",CFrame.new(0,0,100));gallery.Parent=workspace
require(script.Parent.GlassDemoDrafts).Generate()
local spawn=Instance.new("SpawnLocation");spawn.Name="DemoSpawn";spawn.Anchored=true
spawn.Position=Vector3.new(156,2,-18);spawn.Size=Vector3.new(6,1,6);spawn.Parent=workspace
