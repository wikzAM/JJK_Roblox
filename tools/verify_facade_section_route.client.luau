-- Append to the temporary native section probe, with its sample duration set to
-- 30 seconds. Not a normal game startup module. Camera motion is visual only.
task.spawn(function()
 while root:GetAttribute("Phase")~="ready-for-damage" do
  if root:GetAttribute("Phase")=="failed" then return end
  task.wait(.1)
 end
 local route={
  {Vector3.new(-343.56,94.43,-660.66),Vector3.new(-333.43,91.43,-705.23)},
  {Vector3.new(-136.24,93.21,-665.07),Vector3.new(-180.59,90.21,-676.12)},
  {Vector3.new(-173.27,93.21,-758.72),Vector3.new(-184.29,90.21,-714.36)},
  {Vector3.new(-82.16,101.23,-803.22),Vector3.new(-126.66,98.23,-813.65)},
  {Vector3.new(-320.53,94.43,-838.79),Vector3.new(-331.22,91.43,-794.35)},
  {Vector3.new(-343.56,94.43,-660.66),Vector3.new(-333.43,91.43,-705.23)},
 }
 root:SetAttribute("Measure","final-6328-part-moving-route")
 root:SetAttribute("Phase","moving-route")
 for _,point in route do
  local startP,startT=position,target
  for i=1,20 do
   root:SetAttribute("CameraPosition",startP:Lerp(point[1],i/20))
   root:SetAttribute("CameraTarget",startT:Lerp(point[2],i/20))
   task.wait(.1)
  end
  task.wait(3)
 end
 task.wait(1)
 local v=info();assert(v.panes==175 and v.near==0 and v.far==0)
 root:SetAttribute("FinalRouteMetrics",H:JSONEncode(v))
 root:SetAttribute("Phase","route-complete")
end)
