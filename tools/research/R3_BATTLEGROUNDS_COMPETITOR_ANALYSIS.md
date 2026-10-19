# R3: Battlegrounds competitor analysis (2026-10-19)

Research only. No code, Studio or place changes. This compares our design (`GAME_DESIGN_DECISIONS.md`,
`R2_CHARACTER_NETCODE.md`) with the leading Roblox battlegrounds and anime combat games. For each game
it asks how they handle the problems we face: destruction, knockback, hit netcode, VFX cost and
feel.

**Tags.** [doc] official game page, Roblox API data or patch notes written by the developer.
[staff] a statement by the game's own developers. [community] wiki, DevForum, NamuWiki or player
claims. [est] my inference.

**How good is the evidence?** None of these studios has published a technical post-mortem, a
DevForum write-up or a devlog about their netcode or destruction. I searched for Yielding Arts, Tze's
Shenanigans, "more awesome games yo" and Varis Studios and found none [est]. The best primary evidence
is therefore **patch notes**. The fandom wikis copy them from the games' Discords, and they reveal a
lot: what broke, what was throttled, which settings exist. Player counts and server sizes come from
the Roblox games API on 2026-10-19 [doc]. Reddit could not be read from this environment, so player
sentiment comes from NamuWiki "problems" pages, wiki notes and DevForum threads. Treat any claim about
*how* a game works internally as [community] or [est].

---

## Executive summary

1. **Nobody in the genre does what we plan.** Every successful battlegrounds game is a small arena with
   10-20 players. None uses CSG carving. None crosses a city in 20 s with real destruction. The
   closest is **Jujutsu Shenanigans (JJS)**: a 20-player city-block map built almost entirely from
   destructible parts, with voxel-style breakage and automatic map regeneration. Its patch history is
   the most useful document we have.
2. **The genre's top technical complaint is ping-dependent knockback and hits.** Two of TSB's own patch
   notes [doc] stand out: landing distance "should no longer be ping based", and laggy players were
   "not getting slammed down". From these I infer that victims fly by physics on their own client
   [est]. Our Tier A server-planned kinematic path removes this class of bug by construction. That is
   a real advantage. Protect it.
3. **Destruction cost is managed with blunt levers, not clever maths.** JJS and Heroes Battlegrounds
   (HB) use:
   - caps on parts per destruction and in total;
   - a debris "step size", meaning voxel size;
   - fewer debris pieces when **server** performance drops;
   - no debris beyond a distance;
   - client toggles for smoke, interpolation and physics VFX;
   - auto-respawn of the map;
   - no destruction in ranked.

   We should adopt every one of these.
4. **VFX are client-side, scalable and culled offscreen.**
   - TSB has a VFX Scale slider and "No Offscreen Craters", and skips barrage effects that are off screen.
   - HB's "Low Effects" setting cuts particle counts.
   - JJS lets each visual node be marked "Client Sided".
5. **Servers rot with age.** TSB has shipped at least four "old servers get laggy / memory leak" fixes.
   Jujutsu Infinite now shows server age in its server list. With CSG and debris, our server will rot
   faster. Soak tests are mandatory.
6. **Debris that collides with characters causes flings and stuck players.** TSB and Jujutsu Infinite
   made debris non-collidable for this reason. JJS added a push-out when a player gets up from
   ragdoll. Make our debris non-colliding with characters by default.
7. **Fairness complaints are social as much as technical.** In 15-20 player free-for-alls, the top
   complaint after lag is **teaming**. JJS built a dedicated anti-teaming "burst" mechanic. With
   bots and 20 players, we need an answer too.

---

## At a glance (Roblox games API, 2026-10-19) [doc]

| Game | Developer | Max per server | Playing now | Visits | Map | Destruction |
|---|---|---|---|---|---|---|
| The Strongest Battlegrounds (TSB) | Yielding Arts | 15 | ~49.5k | 19.4B | Park arena ringed by mountains, void edges | Props only (trees, benches, bins, floor tiles); craters as VFX |
| Jujutsu Shenanigans (JJS) | Tze's Shenanigans | **20** | ~109k | 7.7B | "Shinjuku" city block, 11-floor towers; Shibuya maps in Roulette | **Almost everything**, voxel-like, auto-respawn |
| Heroes Battlegrounds (HB) | more awesome games yo | 15 | ~4k | 1.75B | Arena with pillars, bar interior | Tiles, pillars, trees by specific moves; capped |
| Sorcerer Battlegrounds | alrage fan club | 15 | ~170 | 466M | Arena | Not documented |
| Jujutsu Infinite (JJI) | Awesome Ninja Games | 12 | ~1.1k | 725M | Open-world PvE RPG, zoned by level | Move-based debris; little structural |
| Jujutsu: Zero | Studio Resonance | 14 | ~4.2k | 130M | Not researched in depth | Not researched |
| A Universal Time (AUT) | Universe Time Studio | menu place, then servers | ~3.4k | 995M | Large hub plus instanced locations (one is "Shibuya") | Minimal |
| FLASHPOINT | Varis Studios | 15 | ~1.1k | 227M | City plus desert plus race instances | None documented |

Our target is about 20 players plus bots, which equals JJS's ceiling and exceeds everyone else's.

---

## 1. The Strongest Battlegrounds (Yielding Arts)

**Map and destruction.**
- The main map is a paved, park-like arena [community]:
  - 60-70 trees, 30-35 benches and 25-30 trash cans;
  - metal railings;
  - a central leaderboard;
  - tunnels that lead nowhere;
  - a mountain ring with void beyond.
- Seasonal reskins add snow, and a summer beach map came and went. Duel maps have invisible walls, which
  disables wall combos ([TSB wiki: Map](https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Map),
  [NamuWiki](https://en.namu.wiki/w/The%20Strongest%20Battlegrounds)).
- Destructibles are props: trees, trash cans, benches, floor and arena floor. A brick wall exists only in
  build mode ([Destructible Objects](https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Destructible_Objects)).
- When broken, benches turn to dust and trees fly off and vanish [community]. Build mode makes
  destroyed objects respawn after **30 s** ([Build Mode](https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Build_Mode)) [community].
- TSB's "destruction" is mostly **ground craters**: rings of rocks, smoke and debris. Patch notes keep
  trimming them [doc, via [Updates](https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Updates)]:
  - "reduce smoke and debris from ground craters", and less debris from dashing;
  - broken trees no longer collide with hitboxes;
  - "fixed debris being collidable".

  DevForum creators widely clone these craters as **client-side** rock modules with part caching. One,
  "Bezier Debris", copies the arcing rocks of TSB's God Slayer move
  ([Rock Module](https://devforum.roblox.com/t/rock-module-v10-craters-explosions-and-more-effects/3041562),
  [Battlegrounds crater module](https://devforum.roblox.com/t/battlegrounds-crater-module/3370194),
  [Bezier Debris](https://devforum.roblox.com/t/bezier-debris-10/4755754)). Those modules' authors stress
  calling them on the client, because server calls cause lag and high ping [community].

**Knockback and ragdoll.**
- There is no developer statement. The patch notes are telling, though [doc]:
  - "landing distance should no longer be ping based";
  - "Fixed laggy players not getting slammed down";
  - a move was fixed for "not working against laggy players".
- Distance that depends on ping, and slams that fail against a laggy victim, both mean the victim's
  motion is simulated on the **victim's own client** under normal character network ownership [est].
- Wiki "tech" pages also show combos that exploit physics. In the "uppercut dash", the knockback
  "roll" is cancelled because there is nothing to roll on, and "certain techs are ping-based"
  ([Techniques](https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Techniques)) [community].
- One DevForum poster asserted, unverified, that TSB applies combo knockback with server BodyVelocity
  and abilities with AlignPosition
  ([thread](https://devforum.roblox.com/t/how-can-i-achieve-knockback-like-in-battleground-games/2545817)) [community].
- Developers repeatedly cite TSB as the "smooth ragdoll" benchmark they cannot match
  ([Ragdoll knockback lag](https://devforum.roblox.com/t/ragdoll-knockback-lag-replication-issue/2845470)) [community].
- Wall slams are a designed **wall combo**: the 4th M1 near a wall, then a dash, gives a unique
  animation plus ragdoll. TSB treats a wall as a *combo state*, not a physics event [community].

**Hit detection.**
- A DevForum poster claims TSB, Sorcerers and Heroes use **server-side hitboxes**. Another notes that TSB
  "at least doesn't" use rollback
  ([thread](https://devforum.roblox.com/t/what-system-do-big-battlegrounds-games-use-for-hitboxes/3972418)) [community].
- The practice dummy has "no ping", so combos behave differently on it than on players
  ([NamuWiki](https://en.namu.wiki/w/The%20Strongest%20Battlegrounds)) [community].

**VFX and settings.** The settings page lists [community, [Settings](https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Settings)]:
- VFX Scale, down to 0.10;
- a low-effects toggle;
- **No Offscreen Craters**;
- Reduced or Remove Camera Shake.

Patch notes add "barrage effects won't show if they're not visible on your screen" and a "rendering
system" for one tornado ultimate [doc]. Camera shake is a key part of TSB's feel; DevForum threads
credit it, plus head-focused camera framing, for the punch
([camera shake thread](https://devforum.roblox.com/t/camera-shake-for-combat/2317381)) [community].

**Praise and complaints.**
- **Praise:** natural hit feel and motion; awards from the platform and voters
  ([Bloxy News](https://x.com/Bloxy_News/status/1810357961807769996)) [community].
- **Complaints** (NamuWiki "Problems" page) [community]:
  - Servers lag even with good ping and FPS, with interrupted motion and bad hit judgment. One
    ultimate made it worse because each part of its robot model is a separate object with heavy
    effects.
  - Duels cross regions at about 300 ms. Teleport-heavy characters dominate at high ping.
  - Teaming is rampant. Hackers persist because anti-cheat updates are slow.
  - Bug backlogs grow during long gaps between updates.
- Patch notes repeat "fixed memory leak that caused lags in old servers" and "servers start to lag as
  they get older" at least four times [doc].

**Copy:**
- client-scaled VFX;
- offscreen culling;
- shake toggles;
- wall interactions as designed states.

**Avoid:**
- ping-dependent victim motion;
- part-heavy ultimate models;
- long-lived servers without leak testing.

## 2. Jujutsu Shenanigans (Tze's Shenanigans): the closest analogue

**Map.**
- Since V1.03, public servers use a city-block map with a "Shinjuku Station" [community, [JJS wiki: Map](https://jujutsu-shenanigans.fandom.com/wiki/Map)]:
  - towers, cafes, a jail, a bowling alley and sewers;
  - two 11-floor towers joined by a bridge, with climbable ladders.
- "Almost all of the map is made of destructible parts", inspired by an older game, *Combat Mayhem*.
- Roulette minigames use "large maps", several of them JJK set pieces: **Shibuya Station, Shibuya
  Crossing**, Shinjuku's Fallout and a detention center.
- The map is still small. Its towers are 11 floors, and it is a battle arena, not a traversal city [est].

**How destruction works** [community unless noted]:
- Terrain crumbles into physical rubble. Debris size varies by skill, and some skills erase debris
  entirely. Rubble can block skills and trap players.
- Destroyed features "are automatically restored to their original state over time"
  ([NamuWiki](https://en.namu.wiki/w/Jujutsu%20Shenanigans)).
- Private-server toggles confirm the design ([Private Servers](https://jujutsu-shenanigans.fandom.com/wiki/Private_Servers)):
  - **Destruction Respawns** ("automatic world reload");
  - **Destruction** on/off;
  - **Debree Fidelity**, the debris size in studs, **2 by default**.

  This is voxel-style subdivision, not CSG.
- DevForum posters claim, unverified, that it uses the open "Vex 2.0" voxel module, citing a Discord
  message from the owner. Others reverse-engineer it as octree subdivision of the hit region
  ([optimized voxel thread](https://devforum.roblox.com/t/how-to-do-optimized-voxel-destruction/2918590),
  [JJS-like thread](https://devforum.roblox.com/t/how-could-i-make-destruction-like-jujutsu-shenanigans-or-realm-rampage/3127398)).
  One poster argues the voxels must be created on the server, or clients disagree about which floating
  piece someone is standing on.

**The patch history shows how hard this is** [doc, via [Update Log](https://jujutsu-shenanigans.fandom.com/wiki/Update_Log) and sub-pages]:

| Version | Change |
|---|---|
| V1.03 | "Massively improved performance on the server during destruction" (new map shipped "may be reverted if performance is worse") |
| V1.08 | Fixed lag spikes when parts despawn |
| V1.25, 1.35, 1.37 | Reduced destruction network usage (1.37: "at the risk of causing performance issues") |
| V1.28 | Optimized destruction of large parts; fixed large-part pieces "teleporting around" |
| V1.30 / 1.37 | Client settings: Destruction Smoke; **Destruction Interpolation** ("smoothens debris while using more performance") |
| V1.41 | Fixed performance when destroying "a ton of parts"; cheaper ragdoll collisions |
| V1.49 | Less debris created by ragdolls |
| V1.52 | Faster destruction maths, better player replication, cheaper "idle destruction" |
| V1.58 | Debris no longer moves the camera; Screen Shake toggle |
| V1.59 | Getting up from ragdoll pushes loose debris off you |
| V1.62 | Larger debris step size; **fewer debris when server performance drops**; debris cleanup on drops |
| V1.67.1 | Debris physics throttling fixed |
| V1.74 | **Destruction disabled in Ranked duels** |
| V1.76 | One domain's debris is smaller, and **none is created "if far enough"**; smoke caching fixed |
| V1.79 | Memory leaks in ragdoll and **anchored debris** |
| V1.80 | Visual and Sound nodes gain a "Client Sided" option |
| V1.83 → V1.83.1 | "Destruction has been completely rewritten from the ground up", then next patch "Added back old destruction" |

Read together [est]:
- the server owns the destruction and replicates debris;
- clients interpolate debris, at a cost they can switch off;
- the studio has fought network use, instance churn and leaks for two years;
- a full rewrite was rolled back within one patch.

**Knockback and netcode.**
- Ragdoll is physical, and "true ragdoll" is a distinct state.
- Patches mention "hitlag" and "hitstop" tuned per move. For example, one move gets "a longer hitstop on
  stun" and hitlag is removed from spikes [doc].
- "Improved the interpolation of players, fixing jittery movement" (V1.53) and "improved player
  replication" (V1.52) suggest custom smoothing on top of Roblox replication [est].
- High-ping bugs still surface, for example a throw failing on high ping (V1.81.2) [doc].
- Server-region filtering was added (V1.68), which treats ping as a matchmaking problem [doc].

**Domains** are physical barriers with health that can be broken, contested ("domain clash") and
locked out [doc].

**Fairness.** The **burst** system is an anti-teaming mechanic. The server records who hit whom. If a
second attacker hits a stunned victim, the victim may burst out of the combo and heal
([NamuWiki](https://en.namu.wiki/w/Jujutsu%20Shenanigans)) [community].

**Settings for low-end devices:** shadows, Destruction Smoke, Destruction Interpolation, Physics VFX
and Ragdoll SFX, each labelled "turning off may reduce lag"
([Settings](https://jujutsu-shenanigans.fandom.com/wiki/Settings)) [community].

**Copy:**
- auto-respawning destruction;
- voxel or step size as a single quality lever;
- debris that degrades with server load;
- no debris at distance;
- no destruction in ranked;
- debris push-out on get-up;
- an anti-teaming mechanic;
- a per-effect "client sided" flag.

**Avoid:**
- big-bang rewrites of destruction without a load harness;
- debris that physically traps players or moves cameras.

## 3. Heroes Battlegrounds (more awesome games yo)

**Map.** An arena with four fire-topped pillars, trash cans, benches, rocks and an enterable "Villain Bar"
whose TV and jukebox react to hits
([Structures and Objects](https://heroes-battlegrounds.fandom.com/wiki/Structures_and_Objects)) [community].

**Destruction.**
- Destruction is move-specific [doc, via [Update Log](https://heroes-battlegrounds.fandom.com/wiki/Update_Log)]:
  - "World Smash now destroys pillars";
  - "Ember Assault now destroys tiles";
  - one move's neutral variant "doesn't destroy tiles on throw".
- Private-server options expose the budget directly: **Max Parts Per Destruction** and **Max Destruction
  Parts** ([PS commands](https://heroes-battlegrounds.fandom.com/wiki/Private_Server_Commands)) [community].

**Hits and feel** [doc]:
- Hitboxes are retuned often: "Reduced all hitbox sizes and new hitbox method acquired", and "Experimental
  changes to improve hitboxes (please provide feedback if there are any issues or lag)".
- Players get 0.6 s of invulnerability on ragdoll get-up.
- Settings disable screen flashes and custom camera movement.
- **"Low Effects" decreases particle count** for low-end hardware.

**NPCs.** A world boss, The Prototype, spawns every 3-5 h on public servers. Its HP scales with player
count, and private-server cheats are disabled during the fight
([The Prototype](https://heroes-battlegrounds.fandom.com/wiki/The_Prototype)) [community].

**Copy:** explicit part caps per event and in total; HP scaling with player count for bot bosses.

## 4. Sorcerer Battlegrounds and other JJK battlegrounds

**Sorcerer Battlegrounds**:
- 15 players; JJK-themed; TSB-style controls (Q dash and ragdoll cancel, G awakening).
- 466M visits but only ~170 concurrent today [doc].
- No technical documentation was found; its wiki is gone. A DevForum poster lumps it with TSB as using
  server hitboxes [community].
- The lesson is market, not technical: a JJK skin on TSB mechanics did not hold players [est].

**Jujutsu: Zero** (Studio Resonance, 14 players, ~4.2k playing) is a newer JJK entry [doc]. It was not
researched in depth, and is worth a follow-up because it is growing.

## 5. Jujutsu Infinite (Awesome Ninja Games)

**Map.**
- An open-world PvE RPG with 12 players per server [doc].
- Zones are gated by level: Shijo Town (1+), Umi Village (60+), Numa Temple (120+), Kura Camp (180+),
  Yuki Fortress (240+) ([Map](https://jujutsuinfinite.fandom.com/wiki/Map)) [community].
- Ranked PvP happens on **separate small maps**, not the open world.

**Lessons from its patch notes** [doc, via [Update Log](https://jujutsuinfinite.fandom.com/wiki/Update_Log)]:
- "Cursed Shock debris is no longer collideable (was causing flinging and jank)."
- "Fixed high ping sometimes breaking you when you use moves", fixed with a 5 s move-lock timeout.
- "Added Ranked Match leashing" for flung players, plus thicker floors and added roofs so players cannot
  be flung out.
- "Added current server age to server list."
- Event bosses spawn "at XX:00 at the same time across all servers"; domains are blocked by proximity in
  boss arenas.

**Takeaway.** JJI keeps its big world and its PvP on separate maps. It patches fling, ping and server
aging with blunt guards: leashes, timeouts and server-age display.

## 6. A Universal Time (Universe Time Studio)

AUT is a multi-anime ability RPG on a large hub map with **fast-travel waypoints**. Many areas are
separate locations reached by portal or NPC, including a "Shibuya"
([Map Locations](https://a-universal-time-roblox.fandom.com/wiki/Map_Locations)) [community]. Its
root place is a 1-player menu that teleports players into servers [doc]. Its description carries a
photosensitive-epilepsy warning [doc], which signals how far its flashing VFX go.

There is no notable destruction. The lesson: a large world plus many flashy abilities was made
manageable by **instancing**, not by one seamless map [est]. We reject instancing for the Shibuya
fight, but a menu or lobby place and a separate ranked place are cheap wins.

## 7. FLASHPOINT (Varis Studios)

FLASHPOINT is a Flash-inspired game: 15 players, a city plus a desert biome, and racing instances
[doc]. Fan-wiki claims follow; they are low reliability and sourced from TikTok-level community
testing ([flashpoint.wiki map size](https://flashpoint.wiki/exploration/roblox-map-size/),
[Speed Force](https://flashpoint.wiki/progression/speed-force/)) [community]:
- **Speed Force.** Holding about 10,000 studs/s unlocks it as a **separate dimension**, and stopping
  forces an exit.
- **Traversal times.** Advanced players cross the map in 10-20 s; extreme speeds in under a second.
- **Collision at extreme speed.** Collision fails at extreme speeds, so players clip through walls and
  fall into unrendered zones.
- **Jitter.** Jitter at speed means the player has hit hardware or optimization limits.
- **Hand-to-hand combat** exists, but there is no destruction.

This confirms our existing reference point. A Roblox city can be crossed in 10-20 s, but only with
**no destruction**. The very top speeds are a different mode, because physical collision breaks down.
Our teleport fake (Tier B) for Mach-level travel is the same move.

## 8. City-destruction games

- **Destroy a City** (70M+ visits; "may run poorly on some tablets and lower end devices") and
  **CITY DESTRUCTION** ("lag because many parts are being simulated at once") use unanchored part
  physics on hand-built cities [doc,
  [Destroy a City](https://www.roblox.com/games/6700307184/Destroy-a-City),
  [CITY DESTRUCTION](https://www.roblox.com/games/375720828/CITY-DESTRUCTION)].
- **Destroy The City** has a manual "regen building" button [doc].
- **Kaiju Universe** makes destroying skyscrapers a currency source on open-world city maps
  ([guide](https://progameguides.com/roblox/how-to-get-g-cells-fast-in-kaiju-universe-roblox/)) [community].

None of these pairs city destruction with fast PvP. All of them accept lag as the price. Their model is
"physics everything, regenerate whole buildings". This is the opposite of our physics-off pillar,
and it confirms why we chose it [est].

---

## Cross-cutting: how the genre solves our problems

**Knockback.**
- DevForum consensus is that server-applied physics knockback looks choppy to everyone except the
  victim. Client-applied knockback looks smooth but is delayed by ping and open to exploits.
- Fixes on offer:
  - attacker-owned ownership tricks;
  - hidden client-side decoy ragdolls;
  - moving attachments to the root part.

  None is satisfying
  ([laggy knockback](https://devforum.roblox.com/t/laggy-knockback-linear-velocity/2950780),
  [ragdoll knockback lag](https://devforum.roblox.com/t/ragdoll-knockback-lag-replication-issue/2845470),
  [zero-delay ragdoll like TSB/JJS](https://devforum.roblox.com/t/how-to-achieve-instant-zero-delay-ragdoll-like-tsbjjs/4815245)) [community].
- The community's newer answer is custom character replication: BetterReplication and **Chrono**. Chrono
  states that default physics replicates at 20 Hz with a large, non-configurable interpolation delay
  ([Chrono](https://devforum.roblox.com/t/chrono-drop-in-custom-physics-replication-library/3873294)) [community].
- Our anchored-root, analytic `path(t)` design sidesteps the whole debate. Every client evaluates the
  same server-timed curve [est].

**Hit detection.** Opinions split between client hitboxes with server distance checks and server hitboxes
with velocity prediction. Neither side has evidence of lag compensation in the big games
([thread](https://devforum.roblox.com/t/what-system-do-big-battlegrounds-games-use-for-hitboxes/3972418),
[client vs server](https://devforum.roblox.com/t/melee-combat-client-vs-server-hitboxes/4244279)) [community].
Our server rewind plan (R2) is ahead of the genre.

**Destruction.**
- Battlegrounds games use voxel subdivision (JJS, "Realm Rampage" imitators), prop breakage (TSB, HB),
  or client-only crater VFX.
- DevForum CSG experiments for live destruction report it as slow and laggy when repeated
  ([CSG destruction](https://devforum.roblox.com/t/csg-destruction/3633276),
  [soft wall](https://devforum.roblox.com/t/soft-wall-destruction-with-weapons/4047722)) [community].
- I found **no shipped battlegrounds game using runtime CSG** [est]. That is a differentiator and a risk.

**VFX.** Everyone triggers effects on the server and renders them on clients. Everyone exposes
per-player effect-scale and toggle settings.

---

## What players praise, what they complain about

| Praised | Complained about |
|---|---|
| Natural hit feel, camera shake, readable impact (TSB) | Lag "even with good ping": server-side frame drops from heavy ultimates (TSB) |
| Wrecking the environment, parkour over and through it (JJS) | Ping-dependent knockback, slams and techs (TSB patch notes, JJI) |
| Interactive props: throwable bins, chairs, extinguishers (TSB, JJS, HB) | Debris trapping or flinging players (JJS, JJI, TSB) |
| Wall combos and slams | Old servers degrading (TSB, JJI) |
| Domains as physical, contestable spaces (JJS) | Teaming in free-for-all; hackers; slow patch cadence (TSB) |

---

## Lessons for our game

### Motion tiers

- **Tier A (kinematic path) is our biggest competitive advantage.** The market leader has shipped
  patches to stop landing distance depending on ping and to make slams work on laggy victims. A
  server-timed analytic path makes both impossible. Keep victims anchored on the path for the whole
  flight. Don't hand them to physics "for smoothness" mid-flight.
- **Make the wall slam a designed state, not a collision accident.** TSB's wall combo shows players love
  it. Our spherecast wall hit should trigger a scripted slam pose, camera beat and crater on the
  timeline. Don't trigger a physics bounce.
- **Tier C ragdoll must be robust against debris.**
  - Default debris to a collision group that ignores characters (as TSB and JJI did).
  - Push characters free on get-up (as JJS does).
  - Add a leash: a flung or stuck victim returns to the last valid path point (as JJI does in ranked).
  - Add a hard move-lock timeout (JJI uses 5 s) so high ping can never soft-lock a player.
- **Per-move hitstop.** JJS tunes hitlag per move. Make our 60-120 ms hitstop a per-move field in the
  timeline, not a global constant.

### The three destruction types

- **Physical attack (CSG plus debris).**
  - **Budgets.** Adopt HB's two caps: max parts per event and max live destruction parts per server.
  - **Throttling.** Adopt JJS's server-load throttling: fewer debris pieces when server heartbeat drops.
  - **Distance cull.** Spawn no debris beyond a distance.
  - **Fidelity.** Expose a "debris fidelity" (minimum chunk size) as our single quality lever.
- **Beam.** It costs the least. It needs no debris, so it is the best type for long-range ultimates seen
  across the map.
- **Slice and collapse.** Nobody in the genre has this. It is our showcase. It runs entirely on the
  timeline, so it should be cheaper per viewer than JJS-style physical rubble.
- **Regeneration is required.** Every competitor with destruction has it:
  - JJS restores the world automatically;
  - TSB build mode respawns objects after 30 s;
  - city games use regen buttons.

  For Shibuya, regenerate damaged blocks **when no player has line of sight**, so the skyline is
  always present. Swap in the undamaged block stand-in at the same moment. Pick a timer per block, for
  example 60-180 s after the last hit [est].
- **Ranked or competitive modes should turn destruction off or down** (as JJS did). That also gives us a
  clean control group for netcode testing.
- **Do not big-bang rewrite destruction.** JJS's V1.83 rewrite was reverted within one patch. Keep
  destruction behind a versioned interface, and A/B it in private servers first.

### Server timelines and VFX

- Keep every VFX node flagged client-side (as JJS does). The server sends only seeds and times.
- **Settings** to match genre norms:
  - VFX Scale;
  - offscreen crater and debris skip (as TSB does);
  - destruction smoke on/off;
  - debris interpolation on/off;
  - physics VFX on/off;
  - camera shake reduce or off;
  - screen-flash off (HB, plus AUT's epilepsy warning).
- Cull timeline effects that are off screen or far away on the client (as TSB does with barrages). Keep
  gameplay-relevant collision changes identical for everyone.
- **Ultimates must not be part-heavy.** TSB's worst lag came from an ultimate whose robot model was many
  separate parts. Build large summons and ultimates as single meshes or Beams.

### Skyline and lean map

- No competitor combines a large city, 20-second traversal and destruction:
  - FLASHPOINT has the city and the speed, but no destruction, and a separate dimension for top speed;
  - JJS has the destruction, but on a city *block*;
  - AUT and JJI use instancing.
- Our lean part budget (10-25 parts per near building, about 60k map-wide) is therefore the make-or-break
  constraint. Budget it now with a soak test: 20 clients, 1-2 hours, continuous destruction, and
  watch memory.
- TSB and JJI both learned that **servers rot**. Add server-age telemetry from day one. Consider
  scheduled soft restarts that migrate players, for example after 6-8 h [est].
- Shibuya itself already appears in JJS Roulette and in AUT. Players will compare against them.
  Night-time Shibuya at city scale is our distinct pitch.

### Bots

- Bots must go through the **same server path** as players. TSB's ping-less dummy makes combos behave
  differently on it than on real opponents, which misleads practice.
- **Boss bots:** HP scales with player count, and cheats are disabled during the fight (HB). Optional:
  world events at fixed clock times across servers (JJI).
- With 20 players plus bots in a free-for-all, **teaming** will be the top social complaint. Consider a
  JJS-style burst. When a second attacker joins a combo on a stunned victim, give the victim a
  one-time escape. Bots should also avoid ganging up on one human.

### Copy, adapt, avoid (summary)

| Copy | Adapt | Avoid |
|---|---|---|
| Part caps per event and per server (HB) | Auto-regen → regenerate out of sight with stand-in swap | Victim motion on the victim's client (TSB) |
| Debris throttling under server load (JJS) | Wall combo → timeline wall-slam state | Debris colliding with characters (TSB, JJI) |
| Client effect settings and offscreen culling (TSB, JJS, HB) | Domains as physical barriers with HP (JJS) → our CSG-proof domain shells | Part-heavy ultimate models (TSB) |
| Destruction off in ranked (JJS) | Anti-teaming burst (JJS) | Destruction rewrites without load tests (JJS) |
| Leash plus move-lock timeout (JJI) | Separate menu and ranked places (AUT, JJI) | Unmeasured long-lived servers (TSB, JJI) |

---

## Sources

**Roblox data and official pages [doc]**
- Roblox games API, universes 3808081382, 3508322461, 3808223175, 4568630521, 4724071612, 1782832995, 6760085372, 4785982047: https://games.roblox.com/v1/games?universeIds=…
- Roblox omni-search API (place and universe IDs): https://apis.roblox.com/search-api/omni-search
- Destroy a City: https://www.roblox.com/games/6700307184/Destroy-a-City
- CITY DESTRUCTION: https://www.roblox.com/games/375720828/CITY-DESTRUCTION
- FLASHPOINT: https://www.roblox.com/games/13796645198/FLASHPOINT

**TSB**
- Map: https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Map
- Destructible Objects: https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Destructible_Objects
- Build Mode: https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Build_Mode
- Settings: https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Settings
- Updates (patch notes): https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Updates
- Techniques: https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Techniques
- Bugs: https://the-strongest-battlegrounds-rblx.fandom.com/wiki/Bugs
- NamuWiki: https://en.namu.wiki/w/The%20Strongest%20Battlegrounds
- NamuWiki, Problems page: https://en.namu.wiki/w/The%20Strongest%20Battlegrounds/%EB%AC%B8%EC%A0%9C%EC%A0%90
- Bloxy News award post: https://x.com/Bloxy_News/status/1810357961807769996

**JJS**
- Map: https://jujutsu-shenanigans.fandom.com/wiki/Map
- Update Log index and sub-pages: https://jujutsu-shenanigans.fandom.com/wiki/Update_Log
- Settings: https://jujutsu-shenanigans.fandom.com/wiki/Settings
- Private Servers: https://jujutsu-shenanigans.fandom.com/wiki/Private_Servers
- NamuWiki: https://en.namu.wiki/w/Jujutsu%20Shenanigans

**HB**
- Structures and Objects: https://heroes-battlegrounds.fandom.com/wiki/Structures_and_Objects
- Update Log: https://heroes-battlegrounds.fandom.com/wiki/Update_Log
- Private Server Commands: https://heroes-battlegrounds.fandom.com/wiki/Private_Server_Commands
- The Prototype: https://heroes-battlegrounds.fandom.com/wiki/The_Prototype

**JJI**
- Map: https://jujutsuinfinite.fandom.com/wiki/Map
- Update Log: https://jujutsuinfinite.fandom.com/wiki/Update_Log
- Domains: https://jujutsuinfinite.fandom.com/wiki/Domains

**AUT and FLASHPOINT**
- AUT Map Locations: https://a-universal-time-roblox.fandom.com/wiki/Map_Locations
- FLASHPOINT wiki: https://flashpoint.wiki/
- FLASHPOINT map size: https://flashpoint.wiki/exploration/roblox-map-size/
- FLASHPOINT Speed Force: https://flashpoint.wiki/progression/speed-force/

**DevForum [community]**
- Hitboxes in big battlegrounds games: https://devforum.roblox.com/t/what-system-do-big-battlegrounds-games-use-for-hitboxes/3972418
- Knockback like battlegrounds games: https://devforum.roblox.com/t/how-can-i-achieve-knockback-like-in-battleground-games/2545817
- Ragdoll knockback lag: https://devforum.roblox.com/t/ragdoll-knockback-lag-replication-issue/2845470
- Zero-delay ragdoll like TSB/JJS: https://devforum.roblox.com/t/how-to-achieve-instant-zero-delay-ragdoll-like-tsbjjs/4815245
- TSB-like ragdoll module: https://devforum.roblox.com/t/ragdoll-system-like-strongest-battleground/3183722
- Laggy LinearVelocity knockback: https://devforum.roblox.com/t/laggy-knockback-linear-velocity/2950780
- Chrono replication library: https://devforum.roblox.com/t/chrono-drop-in-custom-physics-replication-library/3873294
- Optimized voxel destruction: https://devforum.roblox.com/t/how-to-do-optimized-voxel-destruction/2918590
- Destruction like JJS or Realm Rampage: https://devforum.roblox.com/t/how-could-i-make-destruction-like-jujutsu-shenanigans-or-realm-rampage/3127398
- VoxelDestruct 2.1: https://devforum.roblox.com/t/voxeldestruct-21-voxelated-destruction-physics-with-greedy-meshing-hitboxes-and-more/3044264
- Rock Module: https://devforum.roblox.com/t/rock-module-v10-craters-explosions-and-more-effects/3041562
- Battlegrounds crater module: https://devforum.roblox.com/t/battlegrounds-crater-module/3370194
- Bezier Debris: https://devforum.roblox.com/t/bezier-debris-10/4755754
- CSG destruction: https://devforum.roblox.com/t/csg-destruction/3633276
- Soft wall destruction: https://devforum.roblox.com/t/soft-wall-destruction-with-weapons/4047722
- Camera shake for combat: https://devforum.roblox.com/t/camera-shake-for-combat/2317381
- Melee client vs server hitboxes: https://devforum.roblox.com/t/melee-combat-client-vs-server-hitboxes/4244279

**Secondary [community]**
- Kaiju Universe G-Cells guide: https://progameguides.com/roblox/how-to-get-g-cells-fast-in-kaiju-universe-roblox/
