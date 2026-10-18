--!nonstrict
-- Replicated, bounded log of hit capsules for CLIENT-built upper facades.
-- Clients delete their local upper-facade parts inside each capsule and skip
-- those parts when (re)building, so late joiners and rebuilt floors agree.
local Hits={MAX=256}
local folder
local serial=0
local function root()
	if folder and folder.Parent then return folder end
	local RS=game:GetService("ReplicatedStorage")
	folder=RS:FindFirstChild("UpperFacadeHits")
	if not folder then folder=Instance.new("Folder");folder.Name="UpperFacadeHits";folder.Parent=RS end
	return folder
end
function Hits.Record(a,b,radius)
	local f=root();serial+=1
	local hit=Instance.new("Configuration");hit.Name=string.format("H%06d",serial)
	hit:SetAttribute("A",a);hit:SetAttribute("B",b);hit:SetAttribute("R",radius)
	hit.Parent=f
	local list=f:GetChildren()
	if #list>Hits.MAX then
		table.sort(list,function(x,y)return x.Name<y.Name end)
		for i=1,#list-Hits.MAX do list[i]:Destroy() end
	end
end
return Hits
