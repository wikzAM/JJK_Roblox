--!nonstrict
-- Read-only synthetic checks; require(...ShibuyaMassingVerification).Run().
local Verification={}

function Verification.Run()
	local Massing=require(script.Parent.ShibuyaMassing)
	local passed={}
	assert(Massing.GeometricKey("4_4510_4915_-8852")=="4510_4915_-8852","negative Z identity suffix")
	assert(Massing.GeometricKey("4_-4510_-4915_-8852")=="-4510_-4915_-8852","all-negative identity suffix")
	assert(Massing.GeometricKey("4_4510_4915_8852")=="4510_4915_8852","positive identity suffix")
	assert(Massing.GeometricKey("4_4510_bad_-8852")==nil,"invalid identity suffix")
	table.insert(passed,"signed identity suffixes")
	local function component()
		return {meshIndex=900,min=Vector3.new(math.huge,math.huge,math.huge),
			max=Vector3.new(-math.huge,-math.huge,-math.huge),triangles={}}
	end
	local function triangle(g,a,b,c)
		table.insert(g.triangles,{a,b,c})
		for _,p in {a,b,c} do g.min=g.min:Min(p); g.max=g.max:Max(p) end
	end
	local function wall(g,a,b,bottom,top,frame)
		frame=frame or CFrame.identity
		local p=frame:PointToWorldSpace(Vector3.new(a.X,bottom,a.Y))
		local q=frame:PointToWorldSpace(Vector3.new(b.X,bottom,b.Y))
		local r=frame:PointToWorldSpace(Vector3.new(b.X,top,b.Y))
		local s=frame:PointToWorldSpace(Vector3.new(a.X,top,a.Y))
		triangle(g,p,q,r); triangle(g,p,r,s)
	end
	local function prism(g,points,bottom,top,frame,caps)
		frame=frame or CFrame.identity
		for i,p in points do wall(g,p,points[i % #points+1],bottom,top,frame) end
		if caps then
			for _,y in {bottom,top} do
				for i=2,#points-1 do
					local vertices={}
					for _,p in {points[1],points[i],points[i+1]} do
						table.insert(vertices,frame:PointToWorldSpace(Vector3.new(p.X,y,p.Y)))
					end
					triangle(g,vertices[1],vertices[2],vertices[3])
				end
			end
		end
	end
	local function rect(x,z,w,d)
		return {Vector2.new(x,z),Vector2.new(x+w,z),Vector2.new(x+w,z+d),Vector2.new(x,z+d)}
	end
	local function roofRect(g,x,z,w,d,y)
		triangle(g,Vector3.new(x,y,z),Vector3.new(x+w,y,z),Vector3.new(x+w,y,z+d))
		triangle(g,Vector3.new(x,y,z),Vector3.new(x+w,y,z+d),Vector3.new(x,y,z+d))
	end
	local function accept(label,g,check,options)
		local p,reason=Massing.Analyze(g,options)
		assert(p,label..": "..tostring(reason))
		check(p); table.insert(passed,label)
	end
	local function reject(label,g,expected)
		local p,reason=Massing.Analyze(g)
		assert(not p,label..": unexpectedly accepted")
		if expected then assert(reason==expected,label..": "..tostring(reason)) end
		table.insert(passed,label)
	end
	local g=component()
	prism(g,rect(-50,-30,100,60),0,100,CFrame.new(400,34,-200)*CFrame.Angles(0,0.37,0),true)
	accept("rotated rectangle",g,function(p)
		assert(#p.points==4 and #p.tiers==1 and math.abs(p.area-6000)<0.1)
		assert(math.abs(p.frame.Position.Y-34)<0.01 and math.abs(p.height-100)<0.01)
	end)
	g=component()
	prism(g,{Vector2.new(0,0),Vector2.new(100,0),Vector2.new(100,40),Vector2.new(40,40),Vector2.new(40,100),Vector2.new(0,100)},0,100)
	accept("concave L preserves recess",g,function(p)
		assert(#p.points==6 and math.abs(p.area-6400)<0.1 and #p.tiers==1)
	end)
	g=component()
	prism(g,{Vector2.new(0,0),Vector2.new(100,0),Vector2.new(20,60)},0,100)
	accept("triangular plan",g,function(p) assert(#p.points==3 and math.abs(p.area-3000)<0.1) end)
	g=component()
	wall(g,Vector2.new(0,0),Vector2.new(49,0),0,100)
	wall(g,Vector2.new(49.8,0),Vector2.new(100,0),0,100)
	wall(g,Vector2.new(100,0),Vector2.new(100,60),0,100)
	wall(g,Vector2.new(100,60),Vector2.new(0,60),0,100)
	wall(g,Vector2.new(0,60),Vector2.new(0,0),0,100)
	accept("tiny straight seam repair",g,function(p) assert(#p.points==4 and p.seamRepairs>0) end)
	g=component()
	local clipped=rect(0,0,100,60)
	for i,a in clipped do
		local b=clipped[i % #clipped+1]; local direction=(b-a).Unit
		wall(g,a+direction*2,b-direction*2,0,100)
	end
	accept("bounded measured corner repair",g,function(p)
		assert(#p.points==4 and math.abs(p.area-6000)<0.1 and p.seamRepairs>=4)
	end,{MaxCornerGap=6,MaxCornerExtension=4})
	g=component()
	wall(g,Vector2.new(0,0),Vector2.new(100,0),0,100)
	wall(g,Vector2.new(100,0.83746),Vector2.new(100,1.78671),0,100)
	wall(g,Vector2.new(100,1.78671),Vector2.new(100,60),0,100)
	wall(g,Vector2.new(100,60),Vector2.new(0,60),0,100)
	wall(g,Vector2.new(0,60),Vector2.new(0,0),0,100)
	accept("sub-stud corner beside tiny triangle edge",g,function(p)
		assert(#p.points==4 and math.abs(p.area-6000)<0.1 and p.seamRepairs>0)
	end)
	g=component()
	wall(g,Vector2.new(0,0),Vector2.new(49,0),0,100)
	wall(g,Vector2.new(50.5,0.4),Vector2.new(100,0.4),0,100)
	wall(g,Vector2.new(100,0),Vector2.new(100,60),0,100)
	wall(g,Vector2.new(100,60),Vector2.new(0,60),0,100)
	wall(g,Vector2.new(0,60),Vector2.new(0,0),0,100)
	accept("small displaced parallel facade seam",g,function(p)
		assert(#p.points==4 and math.abs(p.area-6000)<0.1 and p.seamRepairs>0)
	end)
	g=component()
	local points=rect(0,0,100,60)
	for i=1,3 do wall(g,points[i],points[i+1],0,100) end
	reject("missing entire facade",g,"no persistent building body")
	roofRect(g,0,0,100,60,100)
	accept("complete roof recovers one missing facade",g,function(p)
		assert(p.method=="verified planar roof" and #p.points==4 and math.abs(p.area-6000)<0.1)
		assert(p.roofEvidence.validSamples==6 and p.roofEvidence.facadeSupport>=0.8)
	end)
	g=component()
	wall(g,Vector2.new(0,0),Vector2.new(100,0),0,100)
	wall(g,Vector2.new(100,60),Vector2.new(0,60),0,100)
	roofRect(g,0,0,100,60,100)
	local unsupported,unsupportedReason=Massing.AnalyzeRoof(g)
	assert(not unsupported and unsupportedReason=="no roof with verified facade support","roof without enough facades")
	table.insert(passed,"roof does not invent several facades")
	g=component()
	for i=1,3 do wall(g,points[i],points[i+1],0,100) end
	roofRect(g,0,0,100,20,100); roofRect(g,0,20,45,40,100); roofRect(g,45,20,55,40,100)
	accept("roof triangle T junctions cancel correctly",g,function(p)
		assert(p.method=="verified planar roof" and #p.points==4 and math.abs(p.area-6000)<0.1)
	end)
	g=component()
	local outer=rect(0,0,100,100); local inner=rect(30,30,40,40)
	for i=1,3 do wall(g,outer[i],outer[i+1],0,100) end
	for i,p in inner do wall(g,p,inner[i % #inner+1],0,100) end
	roofRect(g,0,0,100,30,100); roofRect(g,0,70,100,30,100)
	roofRect(g,0,30,30,40,100); roofRect(g,70,30,30,40,100)
	reject("open courtyard walls do not become filled roof",g,"no persistent building body")
	g=component(); prism(g,rect(0,0,100,100),0,100); prism(g,rect(30,30,40,40),0,100)
	reject("courtyard preserved by rejection",g,"courtyard or internal loop")
	g=component(); prism(g,rect(0,0,100,100),0,100); prism(g,rect(110,0,30,30),0,100)
	reject("disconnected wings",g,"multiple substantial bodies")
	g=component(); prism(g,rect(0,0,100,80),0,60,nil,true); prism(g,rect(20,20,60,40),60,120,nil,true)
	accept("persistent podium setback",g,function(p)
		assert(#p.tiers==2 and math.abs(p.tiers[1].top-60)<1)
		assert(math.abs(p.tiers[2].top-120)<0.01)
	end)
	g=component(); prism(g,rect(0,0,100,80),0,100,nil,true); prism(g,rect(40,30,20,20),100,114,nil,true)
	accept("rooftop equipment trimmed with roof evidence",g,function(p)
		assert(#p.tiers==1 and math.abs(p.height-100)<0.01 and math.abs(p.roofTrim-14)<0.01)
	end)
	g=component(); prism(g,rect(0,0,100,80),0,60,nil,true); prism(g,rect(70,20,60,40),60,120,nil,true)
	reject("offset upper body",g,"offset or expanding upper body")
	print("SHIBUYA_MASSING_TESTS_PASSED",#passed,table.concat(passed,"; "))
	return passed
end

return Verification
