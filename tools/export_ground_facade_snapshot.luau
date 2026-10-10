-- Exports only the reusable library, never city geometry. Requires local sink.
local Http=game:GetService("HttpService")
local function dump(o)
	local row={class=o.ClassName,name=o.Name,attributes=o:GetAttributes(),children={}}
	if o:IsA("Model") then row.pivot={o:GetPivot():GetComponents()}
	elseif o:IsA("BasePart") then
		assert(o:IsA("Part"),"Unexpected facade primitive")
		row.cframe={o.CFrame:GetComponents()};row.size={o.Size.X,o.Size.Y,o.Size.Z}
		row.color={math.round(o.Color.R*255),math.round(o.Color.G*255),math.round(o.Color.B*255)}
		row.material=o.Material.Value;row.shape=o.Shape.Value;row.tags=o:GetTags();table.sort(row.tags)
		for _,k in {"Anchored","CanCollide","CanQuery","CanTouch","CastShadow","Transparency","Reflectance"} do row[k]=o[k] end
	elseif o:IsA("SurfaceGui") then
		row.Face=o.Face.Value;row.SizingMode=o.SizingMode.Value
		for _,k in {"PixelsPerStud","LightInfluence","MaxDistance"} do row[k]=o[k] end
	elseif o:IsA("TextLabel") then
		row.Text=o.Text;row.Font=o.Font.Value;row.TextScaled=o.TextScaled;row.TextWrapped=o.TextWrapped
		row.TextColor3={o.TextColor3.R,o.TextColor3.G,o.TextColor3.B}
	elseif o:IsA("UIPadding") then
		for _,k in {"PaddingLeft","PaddingRight","PaddingTop","PaddingBottom"} do row[k]={o[k].Scale,o[k].Offset} end
	else assert(o:IsA("Folder"),"Unsupported facade class: "..o.ClassName) end
	for _,c in o:GetChildren() do table.insert(row.children,dump(c)) end
	return row
end
local library=game.ServerStorage.GroundFacadeDraftLibrary
local row=dump(library)
local encoded=Http:JSONEncode(row)
for first=1,#encoded,500000 do
	Http:RequestAsync({Url="http://127.0.0.1:58999/ground_facade_library.json",Method="POST",Body=encoded:sub(first,first+499999),Headers={["X-Append"]=first==1 and "0" or "1"}})
end
return {templates=#row.children,revision=library:GetAttribute("Revision")}
