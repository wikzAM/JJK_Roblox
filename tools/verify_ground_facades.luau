-- Edit-time invariant check. Paste/run with Studio MCP or the command bar.
-- Uses the fresh runtime group installed with the gallery. Creates no geometry.
local R=game.ServerStorage.GroundFacadeDraftRuntime
local K=require(R.GroundFacadeKit)
local C=require(R.GroundFacadeCatalog)
local layouts,entrances,spans=0,0,0
local signatures={}
local function bounds(r)
	local low=Vector3.new(math.huge,math.huge,math.huge)
	local high=Vector3.new(-math.huge,-math.huge,-math.huge)
	for _,x in {-1,1} do for _,y in {-1,1} do for _,z in {-1,1} do
		local q=r.cframe*Vector3.new(x*r.size.X/2,y*r.size.Y/2,z*r.size.Z/2)
		low=low:Min(q);high=high:Max(q)
	end end end
	return low,high
end
for _,s in C.TYPES do
	for _,width in {s.minWidth,s.width,s.maxWidth} do
		for _,height in {s.minHeight or 10.5,s.height or 12.5,s.maxHeight or 24} do
			for _,mirror in {false,true} do
				local opts={width=width,height=height,mirror=mirror,seed=72}
				local L=K.Layout(s.id,opts);local repeatL=K.Layout(s.id,opts)
				assert(#L.parts==#repeatL.parts,"Unstable part count: "..s.id)
				local signature={}
				for i,r in L.parts do
					local low,high=bounds(r)
					assert(low.X>=-width/2-.025 and high.X<=width/2+.025,"Outside bay: "..s.id.." / "..r.name)
					assert(r.size.X>=.05 and r.size.Y>=.05 and r.size.Z>=.05,"Undersize part")
					assert(r.size==repeatL.parts[i].size and r.cframe==repeatL.parts[i].cframe,"Non-deterministic layout")
					if r.kind~="sign" and r.kind~="light" then table.insert(signature,tostring(r.size)..tostring(r.cframe)..tostring(r.material)..tostring(r.shape)) end
				end
				if width==s.width and height==(s.height or 12.5) and not mirror then
					local sig=table.concat(signature,"|");assert(not signatures[sig],"Duplicate physical designs");signatures[sig]=s.id
				end
				layouts+=1
			end
		end
		for _,mirror in {false,true} do
			local L=K.Layout(s.id,{width=width,seed=99,mirror=mirror})
			local portals=L.portals or (L.door and {L.door} or {})
			for _,d in portals do
				local y0=d.y or 0
				for _,r in L.parts do
					if r.kind=="wall" or r.kind=="glass" or r.kind=="prop" then
						local low,high=bounds(r)
						local blocked=high.X>d.x-d.width/2+.15 and low.X<d.x+d.width/2-.15
							and high.Y>y0+.3 and low.Y<y0+math.min(6,d.height-.3)
							and high.Z>-.6 and low.Z<math.min(d.recess+.1,3)
						assert(not blocked,"Blocked entrance: "..s.id.." / "..r.name)
					end
				end
			end
			entrances+=1
		end
	end
end
for profile in C.PROFILES do
	for _,width in {12,20,36,60,96,144,210} do
		local opts={height=(profile=="atrium" or profile=="twoStorey") and 29.5 or 12.5}
		local key="verify/"..profile;local B=K.PlanRun(width,key,profile,opts);local again=K.PlanRun(width,key,profile,opts)
		local sum,count=0,0
		for i,b in B do
			sum+=b.width;if b.role=="entrance" then count+=1 end
			assert(b.id==again[i].id and b.seed==again[i].seed and b.role==again[i].role,"Unstable composition")
		end
		assert(math.abs(sum-width)<.001,"Stitched width mismatch")
		if profile=="office" or profile=="hotel" or profile=="residential" or profile=="twoStorey" or profile=="atrium" then assert(count<=1,"Multiple coordinated entries") end
		spans+=1
	end
end
assert(not pcall(function()K.BuildRun(nil,96,"unsafe","atrium",nil,{height=29.5})end),"Missing void guard")
local a=K.Layout("18_PosterKonbini",{seed=42,adSeed=1})
local b=K.Layout("18_PosterKonbini",{seed=42,adSeed=2})
local changed=false
for i,r in a.parts do
	assert(r.size==b.parts[i].size and r.cframe==b.parts[i].cframe,"Ad seed changed architecture")
	if r.ad and r.text~=b.parts[i].text then changed=true end
end
assert(changed,"Ad seed did not vary posters")
local stockParts=0
for _,model in game.ServerStorage.GroundFacadeDraftLibrary:GetChildren() do
	assert(model:GetAttribute("FacadeKitVersion")==C.VERSION,"Stale stock template")
	assert(model:GetPivot()==CFrame.identity,"Stock pivot moved off baseline")
	for _,p in model:GetDescendants() do
		if p:IsA("BasePart") then
			assert(p.Anchored and (p.CanQuery or p.Name=="PrivacyFilm" or p:GetAttribute("GlassAttachedOverlay")) and not p.CanTouch and p:HasTag("NoCSG"),"Wrong stock part flags")
			assert(p:GetAttribute("FacadePieceKind")~="preview","Vignette leaked into stock")
			stockParts+=1
		end
		assert(not p:IsA("Light"),"Review lighting leaked into stock")
	end
end
local D=require(R.GroundFacadeDrafts)
local g,l=D.Generate();assert(g==workspace.GroundFacadeDraftGallery and l==game.ServerStorage.GroundFacadeDraftLibrary,"Replay duplicated roots")
return {layoutCases=layouts,entranceCases=entrances,spanCases=spans,physicalTypes=#C.TYPES,stockParts=stockParts,adSeedIndependent=true,replaySafe=true}
