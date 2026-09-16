--!nonstrict
-- Temporary, recoverable before/after inspection. Restore() before Apply/save.
local Review={}
local SS=game:GetService("ServerStorage")
local LIVE="SmoothReviewPreview"
local HIDDEN="SmoothReviewOriginal"

function Review.Restore()
	assert(not game:GetService("RunService"):IsRunning(),"Stop playtest first")
	local hidden=SS:FindFirstChild(HIDDEN)
	if hidden then
		for _,b in hidden:GetChildren() do b.Parent=workspace.Buildings end
		hidden:Destroy()
	end
	local preview=workspace:FindFirstChild(LIVE)
	if preview then preview:Destroy() end -- only disposable review clones
end

function Review.Show(stage,index,mode,angle)
	Review.Restore()
	local list=stage:GetChildren()
	table.sort(list,function(a,b)
		local sa,sb=a:GetAttribute("InteriorBBoxSize"),b:GetAttribute("InteriorBBoxSize")
		if sa.Y==sb.Y then return a.Name<b.Name end
		return sa.Y>sb.Y
	end)
	local b=assert(list[index],"No review building at index")
	local old=assert(b.ReplacementSource.Value,"Missing review source")
	assert(old.Parent==workspace.Buildings,"Original moved")
	local cf,size=b:GetAttribute("InteriorBBoxCFrame"),b:GetAttribute("InteriorBBoxSize")
	if mode~="before" then
		local hidden=Instance.new("Folder"); hidden.Name=HIDDEN; hidden.Parent=SS
		old.Parent=hidden
		local preview=Instance.new("Folder"); preview.Name=LIVE; preview.Parent=workspace
		local copy=b:Clone(); copy.Parent=preview
	end
	local radius=math.max(size.X,size.Z,size.Y)*1.25
	local a=angle or 0.7
	local target=cf.Position
	workspace.CurrentCamera.CFrame=CFrame.lookAt(target+Vector3.new(math.cos(a)*radius,radius*0.6,math.sin(a)*radius),target)
	workspace.CurrentCamera.Focus=CFrame.new(target)
	game:GetService("Selection"):Set({})
	print("SMOOTH_REVIEW",index,mode or "after",b.Name,"floors",b:GetAttribute("GeneratedFloors"),"tiers",b:GetAttribute("SmoothTierCount"),"wedges",b:GetAttribute("SmoothWedgeParts"))
	return b
end

return Review
