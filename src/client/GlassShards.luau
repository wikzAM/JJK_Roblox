-- Client-only short particle bursts. No replicated debris or physics shards.
local Config=require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").GlassConfig)
local Debris=game:GetService("Debris")
local Shards={}
local live=0
function Shards.Emit(cf,size,from,count,options)
	local cam=workspace.CurrentCamera
	if not (options and options.force) and (not cam or (cam.CFrame.Position-cf.Position).Magnitude>Config.DetailRadius) then return 0 end
	count=math.min(count or Config.ShardsPerPane,Config.MaxLiveShardParticles-live)
	if count<=0 then return 0 end
	local p=Instance.new("Part");p.Name="LocalGlassBurst"
	p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false;p.Transparency=1
	p.Size=Vector3.new(math.min(size.X,12),math.min(size.Y,12),.1)
	local away=from and cf.Position-from or cf.LookVector
	if away.Magnitude<.01 then away=cf.LookVector end
	p.CFrame=CFrame.lookAt(cf.Position,cf.Position+away.Unit)
	p.Parent=workspace
	local e=Instance.new("ParticleEmitter");e.Name="FallingGlass"
	e.Enabled=false;e.Rate=0;e.Texture=Config.ShardImage
	e.Speed=NumberRange.new(12,30);e.SpreadAngle=Vector2.new(75,75)
	e.Acceleration=Vector3.new(0,-workspace.Gravity*.6,0);e.Drag=.5
	e.Rotation=NumberRange.new(0,360);e.RotSpeed=NumberRange.new(-180,180)
	e.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.65,.35),NumberSequenceKeypoint.new(1,.25,.1)})
	e.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.12),NumberSequenceKeypoint.new(.65,.2),NumberSequenceKeypoint.new(1,1)})
	e.Color=ColorSequence.new(Color3.fromRGB(203,221,231));e.LightInfluence=.45;e.LightEmission=.15
	-- One downward ray per emitter, never per particle. Fade before most shards
	-- would cross the pavement; this approximates landing, not particle collision.
	local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances={p,workspace:FindFirstChild("LocalFacades"),workspace:FindFirstChild("LocalFacadesFar")}
	local hit=workspace:Raycast(cf.Position,Vector3.new(0,-400,0),params)
	local fall=hit and math.sqrt(math.max(.5,cf.Position.Y-hit.Position.Y)*2/(workspace.Gravity*.6)) or Config.ShardLifetime
	local lifetime=math.clamp(fall,.35,Config.ShardLifetime)
	e.Lifetime=NumberRange.new(lifetime*.7,lifetime);e.Parent=p;e:Emit(count)
	live+=count
	task.delay(lifetime+.1,function()live=math.max(0,live-count)end)
	Debris:AddItem(p,lifetime+.2)
	return count
end
function Shards.Stats()return live end
return Shards
