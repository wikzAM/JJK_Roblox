-- Run after ManualSurvey.Points: 3 adjacent roof corners per authored box.
game:GetService("LogService"):ClearOutput()
_G.Manual = require(game.ServerScriptService.Server.ManualShellBuilder)
_G.Authored = _G.Authored or {}
_G.MakeMeasuredBox = function(name, a,b,c, roofOverride)
	assert(a and b and c,"Missing selected corner")
	local roof=roofOverride or (a.Y+b.Y+c.Y)/3
	assert(roofOverride or math.max(a.Y,b.Y,c.Y)-math.min(a.Y,b.Y,c.Y)<5,"Corners are on different roofs; inspect again")
	a=Vector3.new(a.X,roof,a.Z); b=Vector3.new(b.X,roof,b.Z); c=Vector3.new(c.X,roof,c.Z)
	local right=(b-a).Unit
	local width=(b-a).Magnitude
	local back=right:Cross(Vector3.yAxis)
	local depth=(c-a):Dot(back)
	if depth<0 then right=-right; back=-back; a=b; depth=(c-a):Dot(back) end
	local center=a+right*width/2+back*depth/2
	local rp=RaycastParams.new(); rp.FilterType=Enum.RaycastFilterType.Include; rp.FilterDescendantsInstances={workspace.Terrain}
	local ground=assert(workspace:Raycast(center+Vector3.yAxis*1500,-Vector3.yAxis*4000,rp),"Ground missing").Position.Y
	local size=Vector3.new(width,roof-ground,depth)
	local cf=CFrame.fromMatrix(Vector3.new(center.X,(roof+ground)/2,center.Z),right,Vector3.yAxis,back)
	local spec={cf=cf,size=size}
	local staged=_G.Manual.Stage(name,{spec})
	_G.Authored[name]={spec}
	print("AUTHORED",name,"cf",cf,"size",size,"floors",staged:GetAttribute("GeneratedFloors"))
	return staged
end
_G.ManualStages={}
for i=1,3 do
	local p=(i-1)*3
	local ok,result=pcall(_G.MakeMeasuredBox,"BuildingManual_Station_0"..i,_G.P[p+1],_G.P[p+2],_G.P[p+3])
	if ok then table.insert(_G.ManualStages,result) else warn("RECHECK",i,result) end
end
for _,b in _G.ManualStages do
	local cf,size=b:GetBoundingBox()
	for _,old in workspace.Buildings:GetChildren() do
		local ocf,os=old:GetBoundingBox()
		if (ocf.Position-cf.Position).Magnitude<(size.Magnitude+os.Magnitude)/2 and math.abs(ocf.Position.X-cf.Position.X)<(size.X+os.X)/2 and math.abs(ocf.Position.Z-cf.Position.Z)<(size.Z+os.Z)/2 then print("CHECK NEIGHBOR",b.Name,old.Name) end
	end
end
