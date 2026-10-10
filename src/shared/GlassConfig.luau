-- Shared asset IDs and performance/art tuning. No runtime actions.
local C={}
C.VERSION=1
C.State={Intact=1,Cracked=2,Shattered=3,Removed=4}
C.CrackImage="rbxassetid://91345378258372"
C.ShatteredImage="rbxassetid://118715470275244"
C.BackupCrackDecal="rbxassetid://111911787795227" -- owner-supplied store asset; not needed by current uploads
C.CrackTileStuds=12
C.EdgeThicknessStuds=1.0
C.PaneStuds=12
-- Temporary opt-in trial. This is not the final per-floor facade art policy.
C.GeneratedFacadeScope="groundPilot" -- "city" must be an explicit later rollout
C.GeneratedUpperEnabled=false -- Larger trial is ground-only; future upper families opt in.
C.FarProxyEnabled=false -- opaque coloured stand-ins are unsuitable for this trial
C.NearRadius=700
C.DropRadius=850
C.DetailRadius=220
C.FarRadius=1700
C.FarDropRadius=1900
C.FrameBudget=0.002
C.MaxBuildSpeed=400
C.MaxPooledParts=1800
C.MaxShardsPerEvent=48
C.MaxVFXRowsPerEvent=16 -- Transient shard geometry; full damage still lives in state pages.
C.MaxLiveShardParticles=192
C.ShardImage="rbxassetid://95153642216404"
C.ShardsPerPane=3
C.ShardLifetime=3
C.DefaultCrackBand=6
C.DestructionClearance=12 -- remove a full pane-width beyond the structural cutter
C.DestructionCrackBand=12 -- cracked glass starts outside that cleared margin
C.ShatterSpeed=65 -- illustrative impact speed threshold, studs/s; attacks may supply explicit states
return C
