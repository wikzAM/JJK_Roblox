-- Stable logical panes and exact segment-to-oriented-box distance. No Instances.
local Layout=require(script.Parent.FacadeLayout)
local Config=require(script.Parent.GlassConfig)
local G={}
function G.SegmentBoxDistance(a,b,cf,size)
	local p=cf:PointToObjectSpace(a);local d=cf:VectorToObjectSpace(b-a);local half=size*.5
	local ps,ds,hs={p.X,p.Y,p.Z},{d.X,d.Y,d.Z},{half.X,half.Y,half.Z}
	local cuts={0,1}
	for i=1,3 do if math.abs(ds[i])>1e-10 then
		for _,edge in {-hs[i],hs[i]} do local t=(edge-ps[i])/ds[i];if t>0 and t<1 then table.insert(cuts,t) end end
	end end
	table.sort(cuts)
	local function sq(t)
		local sum=0;for i=1,3 do local v=ps[i]+ds[i]*t;local q=math.max(0,math.abs(v)-hs[i]);sum+=q*q end;return sum
	end
	local best=math.min(sq(0),sq(1))
	for j=1,#cuts-1 do
		local lo,hi=cuts[j],cuts[j+1];local mid=(lo+hi)/2;local A,B=0,0
		for i=1,3 do local v=ps[i]+ds[i]*mid;local bound
			if v < -hs[i] then bound=-hs[i] elseif v>hs[i] then bound=hs[i] end
			if bound then A+=ds[i]*ds[i];B+=(ps[i]-bound)*ds[i] end
		end
		local t=A>1e-12 and math.clamp(-B/A,lo,hi) or lo
		best=math.min(best,sq(lo),sq(hi),sq(t))
	end
	return math.sqrt(best)
end
function G.Split(strip)
	local nx=math.max(1,math.ceil(strip.size.X/Config.PaneStuds))
	local ny=math.max(1,math.ceil(strip.size.Y/Config.PaneStuds))
	local w,h=strip.size.X/nx,strip.size.Y/ny;local cells={}
	for y=1,ny do for x=1,nx do
		table.insert(cells,{key=string.format("%d/%d/%d:%d:%d",strip.storey,strip.piece,strip.run,x,y),
			cframe=strip.cframe*CFrame.new(-strip.size.X/2+(x-.5)*w,-strip.size.Y/2+(y-.5)*h,0),
			size=Vector3.new(w,h,strip.size.Z),kind="glass",storey=strip.storey,piece=strip.piece,run=strip.run})
	end end
	return cells
end
function G.Id(model) return model:GetAttribute("SourceSliceId") or model.Name end
function G.GeneratedEnabled(model)
	if Config.GeneratedFacadeScope=="city" then return true end
	if Config.GeneratedFacadeScope~="groundPilot" then return false end
	local pilot=model:FindFirstChild("GroundFacadePilot")
	return pilot~=nil and pilot:GetAttribute("Owner")=="2026-10-08-ground-pilot"
		and type(model:GetAttribute("GroundFacadeOwnedRuns"))=="string"
end
function G.OwnedRuns(model)
	local raw=model:GetAttribute("GroundFacadeOwnedRuns")
	if type(raw)~="string" then return {} end
	local ok,t=pcall(function()return game:GetService("HttpService"):JSONDecode(raw)end)
	return ok and t or {}
end
function G.UpperEnabled(model)
	return Config.GeneratedUpperEnabled~=false and G.GeneratedEnabled(model)
end
function G.Strips(model)
	if not G.UpperEnabled(model) then return nil,{} end
	local frame,strips=Layout.ForModel(model);if not frame then return nil end
	local owned=G.OwnedRuns(model);local rows={}
	for _,s in strips do
		if not (s.storey==1 and owned[tostring(s.piece).."/"..tostring(s.run)]) then table.insert(rows,s) end
	end
	return frame,rows
end
return G
