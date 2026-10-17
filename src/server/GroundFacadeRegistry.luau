--!nonstrict
-- Bounded UTF-8 string properties for edit-time facade manifests/checkpoints.
-- New generations are complete before one small pointer commits them. No geometry.
local Registry={VERSION=1,MAX_CHUNK_BYTES=60000}
local H=game:GetService("HttpService")
local STORE="_FacadeRegistryChunks"
local POINTER="FacadeRegistryActive_"
local OWNER="facade-registry-chunks-v1"
local KEYS={"Manifest","Report","Checkpoint"}
local function keyOkay(key)
 assert(type(key)=="string" and key:match("^[A-Za-z][A-Za-z0-9_]*$") and #key<=64,"Invalid registry key")
end
local function storeOf(reg,create)
 local store=reg:FindFirstChild(STORE)
 if store then assert(store:IsA("Folder") and store:GetAttribute("Owner")==OWNER,"Unowned registry chunk folder")
 elseif create then store=Instance.new("Folder");store.Name=STORE;store:SetAttribute("Owner",OWNER);store.Parent=reg end
 return store
end
function Registry.Read(reg,key,default)
 keyOkay(key)
 local active=reg:GetAttribute(POINTER..key)
 if active==nil then
  local old=reg:GetAttribute(key)
  if old~=nil then assert(type(old)=="string","Legacy registry property is not a string");return old end
  return default
 end
 assert(type(active)=="string","Invalid registry generation pointer")
 local store=storeOf(reg,false);local generation=store and store:FindFirstChild(active)
 assert(generation and generation:GetAttribute("Complete")==true and generation:GetAttribute("RegistryKey")==key,"Incomplete registry generation: "..key)
 local count,bytes=generation:GetAttribute("ChunkCount"),generation:GetAttribute("ByteLength")
 assert(type(count)=="number" and count>=0 and count%1==0 and type(bytes)=="number" and bytes>=0,"Invalid registry generation metadata")
 local chunks={};local length=0
 for i=1,count do
  local chunk=generation:FindFirstChild(string.format("C%06d",i))
  assert(chunk and chunk:IsA("StringValue") and #chunk.Value<=Registry.MAX_CHUNK_BYTES,"Missing/oversized registry chunk")
  chunks[i]=chunk.Value;length+=#chunks[i]
 end
 assert(length==bytes,"Registry byte length mismatch: "..key)
 return table.concat(chunks)
end
function Registry.Write(reg,key,value)
 keyOkay(key);assert(type(value)=="string","Registry values must be strings")
 assert(utf8.len(value)~=nil,"Registry strings must be valid UTF-8")
 local store=storeOf(reg,true)
 local generation=Instance.new("Folder");generation.Name=key.."_"..H:GenerateGUID(false)
 generation:SetAttribute("RegistryKey",key);generation:SetAttribute("ByteLength",#value)
 local committed=false
 local okay,err=pcall(function()
  local first,index=1,0
  while first<=#value do
   local last=math.min(first+Registry.MAX_CHUNK_BYTES-1,#value)
   -- Never end inside a multibyte code point. The next chunk starts on its lead byte.
   while last<#value do
    local nextByte=string.byte(value,last+1)
    if nextByte<128 or nextByte>=192 then break end
    last-=1
   end
   assert(last>=first,"UTF-8 chunk boundary failure")
   index+=1;local chunk=Instance.new("StringValue");chunk.Name=string.format("C%06d",index)
   chunk.Value=string.sub(value,first,last);chunk.Parent=generation;first=last+1
  end
  generation:SetAttribute("ChunkCount",index);generation:SetAttribute("Complete",true)
  generation.Parent=store
  -- All properties above are bounded; this tiny pointer is the sole commit point.
  reg:SetAttribute(POINTER..key,generation.Name);committed=true
  reg:SetAttribute(key,nil) -- Retire the historical oversized property after commit.
 end)
 if not okay then if not committed then generation:Destroy() end;error(err) end
 -- Only collect this key's retired/incomplete generations after its new commit.
 for _,old in store:GetChildren() do if old~=generation and old:GetAttribute("RegistryKey")==key then old:Destroy() end end
 return {bytes=#value,chunks=generation:GetAttribute("ChunkCount"),generation=generation.Name}
end
function Registry.Migrate(reg)
 local changed=0
 for _,key in KEYS do
  local legacy=reg:GetAttribute(key)
  if type(legacy)=="string" then
   if reg:GetAttribute(POINTER..key)==nil then Registry.Write(reg,key,legacy)
   else Registry.Read(reg,key);reg:SetAttribute(key,nil) end
   changed+=1
  end
 end
 return changed
end
-- Read the atomic checkpoint plus every committed per-building transaction.
-- Incremental synchronous batches intentionally leave aggregate blobs unchanged
-- until consolidation; consumers must not mistake those older blobs for live data.
function Registry.ReadLatest(reg,key,default)
 if key~="Manifest" and key~="Report" then return Registry.Read(reg,key,default) end
 local journal=reg:FindFirstChild("CommitJournal")
 if not journal or #journal:GetChildren()==0 then return Registry.Read(reg,key,default) end
 local checkpoint=Registry.Read(reg,"Checkpoint")
 local data=checkpoint and H:JSONDecode(checkpoint) or {
  manifest=H:JSONDecode(Registry.Read(reg,"Manifest","[]")),
  report=H:JSONDecode(Registry.Read(reg,"Report",'{"rows":[]}')),
 }
 local rows,reports={},{}
 for _,row in data.manifest do rows[row.id]=row end
 for _,row in data.report.rows or {} do reports[row.id]=row end
 for _,entry in journal:GetChildren() do if entry:GetAttribute("Committed")==true then
  local id=assert(entry:GetAttribute("SourceSliceId"),"Committed entry lacks ID")
  if entry:GetAttribute("Kind")=="remove" then rows[id]=nil;reports[id]=nil
  else
   rows[id]=H:JSONDecode(assert(Registry.Read(entry,"ManifestRow")))
   reports[id]=H:JSONDecode(assert(Registry.Read(entry,"ReportRow")))
  end
 end end
 local manifest,reportRows={},{}
 local report={revision=reg:GetAttribute("Revision") or 9,buildings=0,parts=0,panes=0,supportedPlanters=0,rows=reportRows}
 for id,row in rows do
  local r=assert(reports[id],"Committed manifest lacks report: "..id)
  table.insert(manifest,row);table.insert(reportRows,r)
  report.parts+=r.parts or 0;report.panes+=r.panes or 0;report.supportedPlanters+=r.supportedPlanters or 0
 end
 table.sort(manifest,function(a,b)return a.id<b.id end)
 table.sort(reportRows,function(a,b)return a.id<b.id end)
 report.buildings=#manifest
 return H:JSONEncode(key=="Manifest" and manifest or report)
end
-- Covers live/archived RegistryBefore folders, avoiding the station archive's
-- unrelated small capture Manifest and avoiding traversal through source Models.
function Registry.MigrateTree(root)
 local result={registries=0,properties=0,rowProperties=0};local queue={root};local index=1
 while index<=#queue do
  local object=queue[index];index+=1
  local registryLike=object.Name=="GroundFacadePilotManifest" or object.Name=="RegistryBefore"
   or object:GetAttribute("Report")~=nil or object:GetAttribute("Checkpoint")~=nil
   or object:GetAttribute(POINTER.."Report")~=nil or object:GetAttribute(POINTER.."Checkpoint")~=nil
  if registryLike then result.registries+=1;result.properties+=Registry.Migrate(object) end
  for _,key in {"ManifestRow","ReportRow"} do
   local value=object:GetAttribute(key)
   if type(value)=="string" and #value>Registry.MAX_CHUNK_BYTES then Registry.Write(object,key,value);result.rowProperties+=1 end
  end
  for _,child in object:GetChildren() do if child:IsA("Folder") and child.Name~=STORE then table.insert(queue,child) end end
  if index%100==0 then task.wait() end
 end
 return result
end
return Registry
