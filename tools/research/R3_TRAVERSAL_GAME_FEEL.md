# R3: Traversal, camera and impact feel for a 20-second Shibuya (2026-10-19)

Research only. No game code changed. This file answers: how fast should things move, how should the camera behave at that speed, how should hits feel, and how do players keep track of each other in the chaos. Section 6 is a concrete spec and a prototype test for the owner to approve.

**Tags:** [doc] Roblox documentation · [staff] Roblox staff post · [community] wikis, forums, player measurements · [ext] other studios, talks, papers · [est] my estimate or arithmetic, to be measured.

---

## 0. The numbers this is built on

- **Map scale.** The Shibuya import is **1 stud = 0.2391 m**, not the 0.28 m the repo used to assume (`tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md`, `tools/road_parts.py`). All m/s figures below use 0.2391. To convert: **m/s ÷ 0.2391 = studs/s**, so 10 m/s ≈ 42 studs/s.
- **Map size** (Edit census, `R2_CITY_INVENTORY.md`): buildings span about **6,400 × 6,000 studs** (about 1.53 × 1.43 km at 0.2391). The diagonal is about **8,800 studs** (2.1 km). The tallest roof is at Y ≈ 967. Building heights: p50 74, p90 154, max 910 studs.
- **Average trip.** The mean distance between two random points in a rectangle this size is about 0.52 × its side, so **about 3,200 studs** [est]. The worst case is the 8,800-stud diagonal.
- **Character.** An R15 character is about 5 studs tall, which is about 1.2 m at this map's scale [est]. So speed in *body lengths per second* is about speed ÷ 5. This matters, because perceived speed depends on body lengths and on nearby reference objects, not on metres.
- **Today's settings.** `default.project.json` sets `CharacterWalkSpeed = 256` (about 61 m/s, about 51 body lengths/s) and `CharacterJumpPower = 512`. The current hit leaves the dummy at 600 studs/s.
- **Gravity.** The default `workspace.Gravity` is 196.2 studs/s². At 0.2391 m/stud that is about 47 m/s², roughly 4.8 g [est]. That suits anime: arcs are snappy, not floaty.

### The 20-second budget

"Anywhere on the map, fighting, within about 20 s" splits roughly like this [est]:

| Phase | Time |
|---|---|
| Choose a target, turn, first input | 1–2 s |
| Travel | 13–15 s |
| Arrival: slow down, land, opening attack | 1–3 s |

- To cross the diagonal (8,800 studs) in about 14 s, travel must **average about 630 studs/s** (150 m/s).
- The average trip (3,200 studs) needs only about 230 studs/s.
- **So the top tier needs a sustained travel mode of about 600–900 studs/s, with short bursts above that.** Teleports cover the rest. This matches the inventory's estimate.

---

## 1. Traversal: what fast games actually do

### 1.1 Reference speeds

| Game / thing | Speed (m/s) | studs/s at 0.2391 | Source |
|---|---|---|---|
| Real sprinter (peak) | about 12 | about 50 | [ext] common knowledge |
| Warframe walk / Bullet Jump / slam | 6 / 14.5 / about 50 | 25 / 61 / 210 | [community] [Warframe wiki: Movement](https://wiki.warframe.com/w/Movement) |
| Warframe Archwing (in atmosphere) | 20 | 84 | [community] same page |
| ULTRAKILL walk / slide / dash / slam | 16.5 / 24 / 49.5 / 100 u/s | 69 / 100 / 207 / 418 | [community] ULTRAKILL wiki, Movement (Unity units ≈ metres) |
| Titanfall (2014) pilot run | about 4.6 (180.6 units/s); wall-run chains reach almost 2× sprint | about 19–40 | [community] [Gameranx datamine](https://gameranx.com/updates/id/20713/article/titanfall-raw-weapon-stats-decrypted-titan-health-and-speed-revealed/) |
| Marvel's Spider-Man swing | low tens of m/s (one unverified claim says 15–20 mph) | about 30–60 | [community, low reliability] [ExpertBeacon](https://expertbeacon.com/how-fast-is-spiderman-ps4/) |
| GTA V fastest cars | about 55–60 [est] | about 230–250 | [est] |
| Flashpoint (Roblox) "Speed Force" | about 10,000 studs/s (fan wikis) | 10,000 | [community, low reliability] `SPEED_SKYLINE_STREAMING.md` §2 |
| **This game today: walk / hit launch** | 61 / 143 | **256 / 600** | `default.project.json`, HitHandler |

**Takeaways:**

1. **We are already faster than every AAA reference except Flashpoint.** AAA player-steered movement near buildings stays at about 60 m/s or less. Insomniac adds speed through **nearby reference objects**, not raw velocity. Their camera "pulls back or catches up" with swing speed, and wind and music swell [ext] ([The Ringer on Spider-Man's swing](https://www.theringer.com/2018/9/24/17895602/marvels-spider-man-swing-success)).
2. **Above about 60 m/s, games change the mode, not just the number.** Planes in GTA fly high, at reduced real-world speed and lower LOD (`SPEED_SKYLINE_STREAMING.md`). Spider-Man 2 boosts web wings with wind tunnels and slingshots and keeps you above the streets ([PlayStation: what's new](https://www.playstation.com/en-gb/games/marvels-spider-man-2/whats-new-in-marvels-spider-man-2/)) [ext]. Fast travel is a cut. Flashpoint reserves its top speeds for a separate mode (`GAME_DESIGN_DECISIONS.md`).
3. **Our map rewards altitude.** 90% of buildings are under 154 studs. A travel lane at 200–300 studs clears almost everything. Only the towers (up to 910 studs) need avoiding.

**Recommendation:** split movement into three regimes that feel and render differently:

- **Combat** (≤ about 120 studs/s). Readable, aimable, on the stock Humanoid.
- **Rooftop travel** (300–900 studs/s). Leaps and boosts above the roofline, on a kinematic mover.
- **Streak** (≥ 1,500 studs/s or instant). Teleports and the Tier B "Mach" fake, presented as a cut with a streak effect, never as steerable flight through streets.

### 1.2 Collision at speed

- **Spider-Man's rule: "you don't slam into a wall and just stop"** [ext, Ryan Smith in The Ringer].
  - Head-on contact turns into a wall run with little speed loss.
  - A clipped corner pushes the hero off the facade at the same pace.
  - An outward force from buildings nudges him toward the middle of the street.
  - A tuck-and-dive keeps him at a workable height.
- **For us, the same idea becomes three outcomes**, chosen by speed and angle:
  - **Deflect / wall run** (shallow angle): keep about 85% of speed and slide along the facade normal.
  - **Smash through** (`speed > breakSpeed`): already planned in `COMBAT_MOTION_DESTRUCTION_SYNC.md` as `Breakthrough`.
  - **Plant** (steep angle, low speed): a stylish stop. This is the only case where speed drops to zero.
  - Never use a dead stop plus a ragdoll for the player's own movement. `PlayerMovement.luau` already blocks automatic ragdoll.
- **Tunnelling.**
  - At 60 Hz, 600 studs/s is 10 studs per frame, and 1,500 studs/s is 25 studs per frame.
  - Facade skins are about 1 stud thick, so frame-by-frame overlap tests miss walls.
  - Every travel mover must do a **swept `workspace:Spherecast` over `v·dt`** each step (radius about 2.5 studs). Filter it to the building collision folder, using the Include filters `R2_MASTER_SYNTHESIS.md` already recommends [est].
- **Auto-avoid for towers.**
  - In rooftop travel, cast about 0.5 s ahead (300–450 studs).
  - If a tower is hit, raise the arc or bend the path up to about 15° (Spider-Man's "nudge") rather than colliding.
  - Do this on the client for feel, and validate it on the server.
- **Don't use the Humanoid above about 150 studs/s.** The stock controller at high WalkSpeed trips on stairs and curbs and sticks to walls [community, widely reported]. Travel modes should drive the character kinematically, with the server checking speed caps (`R2_CHARACTER_NETCODE.md`). The current 256 WalkSpeed is a test value; see §6.

### 1.3 Readability of the map at speed

- **Lead the eye with landmarks.** At rooftop height, the Shibuya 109, Hikarie, Cerulean Tower and the Scramble are the navigation beacons. Give them lit crowns at night and keep them in the block stand-ins, so they survive the draw-distance cut.
- **Target pins.** A HUD diamond on the chosen fight or target, with distance shown in metres (about studs × 0.24) or seconds of travel. The time to a fight is a better number than distance.
- **Detail drops at speed, on purpose.** Above about 300 studs/s, hide small dressing (`SPEED_SKYLINE_STREAMING.md`, "the GTA flying rule"). The eye can't read it anyway.

---

## 2. Camera at high speed

### 2.1 Field of view

- **Roblox facts [doc].** `Camera.FieldOfView` is **vertical**, clamped to 1–120°, and defaults to 70 ([Camera](https://create.roblox.com/docs/reference/engine/classes/Camera.md)). On a 16:9 screen, 70° vertical is about 102° horizontal [est, from tan(h/2) = tan(v/2) × 16/9].
- **Why widen at speed.** A wider view puts more of the scene in the periphery, where optic flow (the visual sense of motion) is strongest. Racing players report a wider FOV raises perceived speed [community] ([GTPlanet FOV thread](https://www.gtplanet.net/forum/threads/field-of-view-fov-aka-why-does-that-track-look-so-wide.323267/latest)).
- **The costs of widening:**
  - Objects look smaller and farther away, which hurts judging distance ([Fanatec FOV guide](https://www.fanatec.com/explorer/games/gaming-tips/optimizing-fov-for-sim-racing-getting-the-view-right/)) [ext].
  - VR research finds that big FOV plus fast, close objects increases both vection (the illusion of self-motion) and the risk of sickness [ext] ([So et al., HKUST](https://www.ieda.ust.hk/dfaculty/so/pdf/So-et-al-2001a-HumanFactors.pdf); [Dizmen & So 2023](https://www.ieda.ust.hk/dfaculty/so/pdf/Dizmen+So-2023-vection.pdf)). This research is mostly HMD-based; I found no study of dynamic FOV on a monitor.
  - **New finding for this project [est]:** going from 70° to 90° vertical roughly **doubles** the frustum's cross-section ((tan 45° × tan 60.6°) / (tan 35° × tan 51.2°) ≈ 2.0). About twice as many buildings are on screen, so the FOV kick can itself trigger Roblox's automatic draw-distance cut. **The FOV cap must be measured with the skyline test**, not just tuned by feel.
- **Recommended curve [est]:** `FOV = 70 + 7 × log2(max(1, speed / 100))`, capped at 90.

| Speed (studs/s) | 100 | 200 | 400 | 800 | 1,500+ |
|---|---|---|---|---|---|
| Vertical FOV | 70 | 77 | 84 | 90 (cap) | 90 |
| Horizontal on 16:9 | 102° | 110° | 116° | 121° | 121° |

- **Smooth the curve.**
  - Widen fast: time constant about 0.15 s, at most 40°/s.
  - Narrow slowly: about 0.4 s, at most 15°/s.
  - Filter the speed before applying, so a jittery velocity never makes the FOV "breathe". Breathing FOV is a known nausea trigger.
  - Example: the DevForum's speed-FOV scripts use exponential easing for the same reason [community] ([Speed-based FOV](https://devforum.roblox.com/t/speed-based-fov/3038337)).
- **Impulse kicks** on top of the curve:
  - **Dash:** +6° over 80 ms, back over 250 ms.
  - **Heavy hit landed or taken:** a −4° *punch-in* for 60–100 ms during hitstop. Zooming in on impact reads as weight; zooming out reads as speed.
- **Settings slider:** "Speed FOV effect 0–100%", plus a separate base FOV of 60–80.

### 2.2 Motion blur alternatives (Roblox has no motion blur)

| Technique | Look | Laptop cost [est] | Use |
|---|---|---|---|
| **Radial speed-line overlay** (ScreenGui ImageLabel, 2–4 frame flipbook, alpha scaled by speed) | Anime-correct; stays fixed on screen | One full-screen quad, about 0.1 ms | Default above about 300 studs/s |
| **Camera-attached ParticleEmitter streaks** (thin stretched particles spawned in a cone ahead, about 20–40 alive) | Real parallax, best "wind" read | Small; avoid additive LightEmission at full screen | Rooftop travel and streaks; the DevForum suggestion for speed lines [community] ([UI wind effect](https://devforum.roblox.com/t/2427686)) |
| **Trails / Beams** on the character's hands, feet and root | Shows path and direction to *other* players | Very small | Always on above about 200 studs/s; doubles as readability (§4) |
| **Afterimages** (2–4 pooled, single-colour ghost rigs, moved with `BulkMoveTo`, fading over 150 ms) | The anime speedster trope | About 15 parts each, pooled; never clone at runtime | Dashes and teleport departures |
| **BlurEffect** | Uniform Gaussian blur of the whole 3D view [doc] ([BlurEffect](https://create.roblox.com/docs/reference/engine/classes/BlurEffect.md)); not directional, and it blurs the opponent too | Full-screen pass that grows with Size, about 0.3–1.5 ms on an integrated GPU | **Only** as a ≤150 ms transition (teleport cut, Tier B), never sustained |

### 2.3 Follow distance, lag and Focus

- **Follow distance.** The base zoom is about 12–14 studs. Ramp it out to about 20 studs and raise it about 3 studs at rooftop speed, as Spider-Man's camera pulls back with speed [ext, The Ringer].
- **Bound the lag by distance, not time.**
  - At 600 studs/s, a 0.1 s positional lag is 60 studs, so the character would leave the frame.
  - Spring the **offset**, not the world position: `offset = clamp(speed × 0.01, 0, 6)` studs behind, critically damped.
  - Rotation lag of about 0.08 s on yaw is fine.
- **No roll.** Keep a level horizon. Allow at most 3° of banking on hard turns in flight, and none on foot.
- **Teleports and Tier B cut; they never pan.**
  - A camera that lerps across 3,000 studs is a whip pan, the worst case for sickness.
  - Instead: hard-cut, hold the camera's yaw relative to the travel direction, and mask the cut with a 60–120 ms speed-line burst or flash (§3.3).
- **`Camera.Focus` [doc].** The engine uses Focus to decide which area gets more detail and more frequent updates. Dynamic lights far from Focus may not render.
  - The default camera script keeps Focus on the character. **A custom camera must set it every frame.**
  - Recommended [est]: `Focus = root + velocity × 0.25 s`, with the lead capped at 150 studs. This prioritises what you are flying into, without starving the character's own lights.
  - Whether Roblox's *draw-distance* cut centres on Focus or on the camera is **undocumented**. Add it to the owner-approved measurement pass.

### 2.4 Avoiding motion sickness

The common accessibility pattern is separate controls for shake, blur, FOV and sway, often under an Accessibility tab [ext] ([Xbox Accessibility Guideline 117](https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/117); [Indiana Jones accessibility guide](https://bethesda.net/en/article/7DI9BqNzgCUJOEXL9JqGLi/indiana-jones-and-the-great-circle-accessibility-guide)). Ship with:

- **Shake intensity** (0–100%).
- **Speed FOV** (0–100%).
- **Speed lines** (on/off).
- **Reduce flashes** (impact frames become a 30% tint instead of a full-screen invert).
- **Camera rules:** no camera bob, a level horizon, rotational shake only, and rate-limited FOV.

**Photosensitivity is a hard rule, not a setting.**
- WCAG 2.3.1 forbids more than **three general flashes per second** [ext] ([WCAG 2.3.1](https://www.w3.org/WAI/WCAG21/Understanding/three-flashes-or-below-threshold.html)).
- A 10-player brawl can easily produce more impact frames than that.
- So the client keeps a **global flash budget: at most 3 full-screen flashes per rolling second**. Extra impacts fall back to world-space effects (§3.3).

---

## 3. Impact feel

### 3.1 Hitstop

| Reference | Hitstop | Source |
|---|---|---|
| Smash Melee | ⌊d/3 + 3⌋ frames, capped at 20 (333 ms); a 15% hit gives 8 frames (133 ms) | [community] [SmashWiki: Hitlag](https://www.ssbwiki.com/Hitlag) |
| Smash Ultimate | ⌊0.65d + 6⌋ frames, capped at 30; a 15% hit gives about 15 frames (250 ms); electric hits ×1.5 | [community] same |
| Guilty Gear Xrd | 11 (Lv0) to 15 (Lv4) frames, 183–250 ms; counter hits up to 27 frames, on the receiver only | [community] [Dustloop: Attack Attributes](https://dustloop.com/w/GGXRD/Attack_Attributes) |
| Sakurai's design writing | Hitstop sells impact, and he tunes it per move | [ext] [Source Gaming translation of Famitsu vol. 490](https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/); [Nintendo Wire, Dec 2022](https://nintendowire.com/news/2022/12/12/this-week-in-sakurai-12-5-12-11-fine-tuning-hit-stop-and-cheating-the-system/) |

**What carries over:**

1. Hitstop **scales with damage**, from a floor of about 3 frames.
2. **Both fighters freeze**, but **the world does not**.
3. **The victim shakes in place** during the freeze, so it never reads as lag.
4. Fighting-game values (130–250 ms) are **longer than our 60–120 ms server budget**. That is fine: our game is faster, and our hitstop is also a latency mask (`COMBAT_MOTION_DESTRUCTION_SYNC.md`). It must be short enough that fights keep flowing.

**Multiplayer rules [est]:**

- Freeze only the two participants' animations and positions. Never freeze the server clock, other players or debris.
- With several attackers on one victim, the victim's **stacked hitstop is capped at 150 ms per 0.5 s window**, so a gang can't freeze-lock them.
- **Slow motion is baked into the path, never the clock.** For a dramatic launch, the first 150–250 ms of the server path segment runs at 20–30% speed, then accelerates. Every viewer sees the same "slow-mo" because it is in the timeline.
- True time dilation is local and cosmetic only. For example, the KO'd player's own death camera can run slow for 0.5 s, like Smash's final-hit zoom.

### 3.2 Screen shake

- **Standard recipe, Squirrel Eiserloh, GDC "Math for Game Programmers" (2016)** [ext] ([Game Developer video page](https://www.gamedeveloper.com/programming/video-sprucing-up-cameras-with-math); [recap](https://blogs.jccc.edu/dpatter/tag/mathematics)):
  - Keep a **trauma** value from 0 to 1. Hits add trauma, and it decays linearly.
  - The shake amount is **trauma² (or ³)**, so small hits barely shake and big ones shake hard.
  - Drive the offsets with smooth **Perlin noise**, not random jitter.
  - **In 3D, use rotational shake only.** Translation pushes the camera into walls.
- **Vlambeer, "The Art of Screenshake"** [ext] ([infovore recap](https://infovore.org/?p=5275)):
  - Add a **directional kick**: push the camera back along the hit direction by a fixed amount, then let it settle.
  - Directional reads better than random.

**Roblox implementation [est]:**

- Bind at `RenderPriority.Camera + 1`, after the camera script.
- Multiply `camera.CFrame` by `CFrame.Angles(pitch, yaw, roll)`, using `math.noise` at 18–25 Hz for hits and 4–8 Hz for collapse rumble.
- Limits: yaw and pitch at most 2.5°, roll at most 1° at trauma 1.
- Trauma decays at 1.5 per second.
- Don't move `Camera.Focus`.
- Cost is effectively zero.

### 3.3 Impact frames (the anime flash)

- **What they are.** In the JJK anime, the big hits (most famously Black Flash) cut to 1–4 frames of high-contrast, often inverted or red-and-black drawings, then snap back [ext].
- **Roblox recipes in use [community]:**
  - An open-source impact-frame module drives a `ColorCorrectionEffect` with tint, saturation and contrast, and recolours a hit list of instances ([Impactframe Module](https://devforum.roblox.com/t/open-source-impactframe-module/2963136)).
  - A silhouette recipe ([In-game silhouette effect](https://devforum.roblox.com/t/in-game-silhouette-effect/2997599)):
    - extreme brightness with saturation 0 on the world;
    - a Highlight of the opposite colour on the fighters;
    - hold about 0.1 s, then invert.
  - Known gotcha: particles can vanish behind the Highlight while the correction is active.
  - A Jujutsu Shenanigans skill-builder update reportedly added a "Screen Color" overlay for impact frames [community, low reliability] ([RosenBerry Rooms](https://rosenberryrooms.com/?p=134510)).
- **Highlight cap [doc].** At most **255** simultaneous Highlights per client. Disabled ones still count ([Highlight](https://create.roblox.com/docs/reference/engine/classes/Highlight.md)).

**Recipe, all inside the hitstop so it never lengthens the timeline [est]:**

| Time (ms) | World | Fighters |
|---|---|---|
| 0–33 (2 frames) | Camera-parented ColorCorrection: Saturation −1, Contrast +1, Brightness +0.6 (white world) | Pooled Highlight, black fill, FillTransparency 0, AlwaysOnTop |
| 33–66 | Brightness −0.6, TintColor black (or deep red for Black Flash) | Highlight white |
| 66–hitstop end | Fade correction to neutral over 40 ms | Highlight off; impact-star billboard scales 0 → 1 → 0 |
| After | Colour pulse: TintColor per character (Gojo blue, Sukuna red) fading over 200 ms | — |

- **Pool everything.** Use one ColorCorrection and two Highlights per client, re-pointed via `Adornee`. Never create them per hit.
- **Who sees the full-screen version:**
  - the attacker and the victim;
  - anyone within about 150 studs who has the hit on screen;
  - everyone, for tier-3+ hits.
  - All of this goes through the flash budget (§2.4).
- **What everyone else sees:** a world-space flash only. That is a PointLight burst plus a billboard star at the hit point.
- **Cost [est]:**
  - ColorCorrection is one cheap full-screen pass, under about 0.3 ms.
  - The Highlight outline pass scales with on-screen pixels, so keep it to 2–4.
  - Both are toggles, with nothing created at hit time.
- **Chromatic aberration:** Roblox has none, and faking it on the 3D view isn't practical. Use the colour pulse instead.

### 3.4 Sound layering

Build each hit from four layers:

1. **Transient:** a crack or snap, 0–30 ms.
2. **Body:** a low thump, 60–120 Hz.
3. **Tail:** debris, glass and reverb, 0.5–2 s.
4. **Signature:** the character's cursed-energy sweetener.

Then:

- Precede strong attacks with a short whoosh.
- **Duck everything else by 3–6 dB for about 150 ms** on heavy hits, with a SoundGroup plus a CompressorSoundEffect sidechain [doc, verify in Studio].
- **For map scale, delay distant booms by distance ÷ 1,435 studs/s** (the speed of sound at this map's scale). A hit 1,000 studs away rumbles 0.7 s later. It is cheap and makes the city feel huge [est].
- Remember that Roblox's SoundService `DopplerScale` exists, for streaking passers-by [doc, verify].

---

## 4. Readability under chaos (with no long telegraphs)

The owner rejected wind-up telegraphs. So readability comes from **persistent state** and **after-signals**: tell the player *what happened, and from where*, instantly.

1. **Opponent markers.**
   - The locked target and anyone targeting you get an AlwaysOnTop Highlight outline or a marker. `DummyTracker.luau` already does this for the dummy.
   - Cap outlines at about 8 for cost.
   - Off-screen threats get edge-of-screen arrows.
2. **Soft lock-on**, as in Roblox battlegrounds games (TSB, Jujutsu Shenanigans) [community]. At these speeds, free aim is not viable.
   - The netcode makes it necessary: at 600 studs/s, 100 ms of latency is 60 studs of position error.
   - Hits on fast movers must be lock-on or area-based. **Arrival should decelerate into an attack**: a dive-kick from the leap is the opener.
3. **Hit-direction arcs** on the HUD when you are hit from off-screen, like FPS damage indicators.
4. **Arrival pops for teleports.** Teleports arrive "with no warning" by design, but the *arrival* still gets a 1–2 frame burst plus a sound at the destination. Then the victim learns where the hit came from after the fact. This is not a telegraph.
5. **Speed trails in character colours.** Anyone above about 200 studs/s leaves a Trail. You can see where a player came from and where they are heading across the skyline.
6. **Audio:** 3D whooshes for passing movers, character-signature hit sounds (you can tell Sukuna hit someone without looking), and distance-delayed booms (§3.4).
7. **Domains and ultimates.**
   - In the anime, a domain is a hand sign, then a closed barrier.
   - JJK games commonly show outsiders a large dark dome, and give insiders a changed sky, lighting and colour [community / est].
   - Recipe:
     - A **single large sphere MeshPart**, 150–300-stud radius, visible map-wide. Large, few objects survive the culling (`SPEED_SKYLINE_STREAMING.md`).
     - Clients inside swap Sky, Atmosphere, ColorCorrection and ambience locally.
     - Map-wide ultimates such as Hollow Purple get one long glowing part or Beam, already planned for cross-map visibility (`GAME_DESIGN_DECISIONS.md`).
     - Their invincible wind-up is spectacle, not a fairness telegraph.

---

## 5. Render cost summary for laptops [est, to measure]

| Effect | Per-frame cost | Notes |
|---|---|---|
| FOV change | about 0 directly | **But** 90° shows about 2× the objects of 70°, which may trigger the draw-distance cut. Measure. |
| Camera shake / kick (CFrame) | about 0 | — |
| ColorCorrection pulse | < 0.3 ms | Pooled, toggled |
| Highlight (2–4) | 0.1–0.5 ms | 255 cap [doc]; pool them |
| ScreenGui speed lines | about 0.1 ms | Fill-rate only |
| Particle streaks (≤ 40) | about 0.1–0.3 ms | Avoid full-screen additive overdraw |
| BlurEffect | 0.3–1.5 ms | Transitions only |
| Afterimages (pooled, `BulkMoveTo`) | < 0.1 ms | About 1.6 µs per part (`R2_ENGINE_TESTS.md`) |

**Target:** the whole feel stack costs **≤ 1 ms p95 on the laptop** at graphics level 1–5.

---

## 6. Recommended spec (proposed, not agreed)

### 6.1 Speed tiers

Metres per second are at 0.2391 m/stud.

| Tier | Speed (studs/s) | m/s | Mover | Notes |
|---|---|---|---|---|
| Combat run | 50–70 | 12–17 | Stock Humanoid | Replace today's test value of 256. Readable at 10–40 stud fighting range. |
| Sprint (out of combat for 1 s) | 140–180 | 33–43 | Humanoid, server speed check | The ceiling for ground movement |
| Dash | 200–250 burst, 0.15–0.2 s | 48–60 | Kinematic | About 35–45 studs, roughly 8 body lengths (ULTRAKILL's dash is about 10 m) |
| Rooftop leap | Vertical 250–620, horizontal 300–500 | — | Kinematic arc, g = 196.2 | Vertical 246 clears a 154-stud roof (p90) in 1.25 s; 616 reaches the 967 tower top in 3.1 s. About 800–1,200 studs per leap. |
| Travel boost / flight (top tier) | 600–900 sustained | 143–215 | Kinematic, swept spherecast, tower avoid | Diagonal in 10–15 s |
| Burst / streak | 1,500–2,500 for ≤ 0.6 s | 360–600 | Kinematic or cut | Speed lines and BlurEffect transition |
| Launch (victim, Tier A) | 200–1,200 initial, with drag | 48–290 | Server path | Wall rule: deflect, break through or plant |
| Mach launch (Tier B) | Effectively more than 3,000 | — | Teleport fake | Cut, streak, dust. 600 residual after the cut (today). |
| Teleport ability | Instant | — | Cut | Arrival pop is mandatory |

### 6.2 FOV and camera

- **FOV:** `70 + 7·log2(v/100)`, clamped to 70–90, with asymmetric smoothing (§2.1).
- **Kicks:** dash +6°; heavy impact −4° for 60–100 ms.
- **Follow distance:** 13 → 20 studs from 0 to 600 studs/s.
- **Offset lag:** at most 6 studs.
- **Horizon:** no roll.
- **Focus:** `root + v·0.25 s`, capped at 150 studs.
- **Teleports:** a hard cut with a mask.

### 6.3 Hitstop table

Hitstop is applied to attacker and victim only. Frames are at 60 fps.

| Attack tier | Example | Hitstop | Shake trauma added | Impact frame | FOV |
|---|---|---|---|---|---|
| 0: chip / combo jab | M1 hits 1–3 | 50 ms (3 f) | 0.10 | None | — |
| 1: combo ender / light launch | M1 4, short launch | 70 ms (4 f) | 0.25 | None; victim shake only | — |
| 2: heavy launch / wall slam | Divergent Fist, Tier A launch through one building | 90 ms (5–6 f) | 0.45 | Tint pulse only | −3° |
| 3: critical | Black Flash, ultimate hit | 120 ms (7 f) | 0.70 | Full two-frame invert, red or black | −4° |
| 4: Mach / map-crossing | Tier B | 120 ms, plus a 200 ms path-baked slow-mo | 0.90 local; ≤ 0.3 for bystanders | Full invert, then cut | −4°, then cut |

- **Bystander shake:** `trauma × max(0, 1 − d / 300)`.
- **Building collapses:** 0.2 trauma out to 1,000 studs, at low frequency.

### 6.4 Prototype test for owner approval

Build a **"FeelLab" client module plus a small server mover** in a test place, or behind a toggle in this place. It must not touch HitHandler's behaviour.

1. **Movement course.**
   - On the real map: rooftop leap, travel boost and streak, from the far south-west corner to the far north-east corner (about 8,800 studs).
   - **Pass:** completed in ≤ 15 s; no tunnelling through any facade over 50 runs; tower auto-avoid fires without visible snapping.
2. **FOV A/B/C.**
   - Fixed 70°, the log curve capped at 90°, and the curve capped at 80°.
   - Run each on the laptop at graphics levels 1, 5 and 10, and record whether the skyline survives (ties into the measurement pass).
   - **Pass:** the chosen cap doesn't shorten draw distance more than a fixed 70°.
3. **Impact stack.**
   - Script 30 hits per tier against the dummy, and 10 simultaneous tier-3 hits from bots.
   - **Pass:**
     - the feel stack costs ≤ 1 ms p95 on the laptop (MicroProfiler);
     - at most 3 full-screen flashes per second, enforced;
     - no Instances created per hit (pooling verified by instance count).
4. **Readability.**
   - Two players plus 6 bots fight in a 300-stud area while a third player arrives by travel boost.
   - **Pass:**
     - the arriving player finds the fight from the pin within 2 s of landing;
     - testers can name who hit them from off-screen (direction arc plus signature sound) in 4 of 5 cases.
5. **Comfort check.**
   - Three testers each do 10 minutes of travel and fighting at the default settings, then rate nausea from 0 to 10.
   - **Pass:** median ≤ 2. If it fails, reduce the FOV cap and shake defaults first.

**Gate:** if 1–5 pass, promote the speed tiers and camera into `GAME_DESIGN_DECISIONS.md` and start the real movement kit.

---

## Sources

**Roblox documentation [doc]**
- Camera (FieldOfView vertical, 1–120, default 70; Focus prioritises detail and lighting): https://create.roblox.com/docs/reference/engine/classes/Camera.md
- Highlight (255 simultaneous limit; disabled ones count): https://create.roblox.com/docs/reference/engine/classes/Highlight.md
- BlurEffect (Gaussian blur of the 3D world; Size in pixels; varies with quality level): https://create.roblox.com/docs/reference/engine/classes/BlurEffect.md
- Post-processing effects: https://create.roblox.com/docs/environment/post-processing-effects.md

**Roblox community [community]**
- Speed-based FOV: https://devforum.roblox.com/t/speed-based-fov/3038337
- UI wind / speed-line effect: https://devforum.roblox.com/t/2427686
- Open-source Impactframe module: https://devforum.roblox.com/t/open-source-impactframe-module/2963136
- In-game silhouette (impact frame) effect: https://devforum.roblox.com/t/in-game-silhouette-effect/2997599
- Jujutsu Shenanigans "Screen Color" overlay (low reliability): https://rosenberryrooms.com/?p=134510
- Flashpoint speed claims: see `SPEED_SKYLINE_STREAMING.md` §2

**Game data wikis [community]**
- SmashWiki, Hitlag: https://www.ssbwiki.com/Hitlag
- Dustloop, GGXrd attack attributes: https://dustloop.com/w/GGXRD/Attack_Attributes
- Warframe wiki, Movement: https://wiki.warframe.com/w/Movement
- ULTRAKILL wiki (movement speeds): https://ultrakill.wiki.gg/
- Titanfall datamine: https://gameranx.com/updates/id/20713/article/titanfall-raw-weapon-stats-decrypted-titan-health-and-speed-revealed/
- Spider-Man swing speed (unverified): https://expertbeacon.com/how-fast-is-spiderman-ps4/

**Studios, talks and press [ext]**
- The Ringer, how Spider-Man's swing works (Insomniac quotes): https://www.theringer.com/2018/9/24/17895602/marvels-spider-man-swing-success
- GDC 2024, "Higher, Faster, Farther: Evolving Traversal in Marvel's Spider-Man 2": https://schedule.gdconf.com/session/higher-faster-farther-evolving-traversal-in-marvels-spider-man-2/900249
- PlayStation, what's new in Spider-Man 2 (web wings, wind tunnels): https://www.playstation.com/en-gb/games/marvels-spider-man-2/whats-new-in-marvels-spider-man-2/
- Sakurai on hitstop (fan translation): https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/
- Nintendo Wire, Sakurai fine-tuning hitstop: https://nintendowire.com/news/2022/12/12/this-week-in-sakurai-12-5-12-11-fine-tuning-hit-stop-and-cheating-the-system/
- Eiserloh, camera math (GDC 2016): https://www.gamedeveloper.com/programming/video-sprucing-up-cameras-with-math · recap: https://blogs.jccc.edu/dpatter/tag/mathematics
- Nijman, "The Art of Screenshake" recap: https://infovore.org/?p=5275
- Xbox Accessibility Guideline 117: https://devdocs.xbox.com/gaming/accessibility/xbox-accessibility-guidelines/117
- Indiana Jones and the Great Circle accessibility guide: https://bethesda.net/en/article/7DI9BqNzgCUJOEXL9JqGLi/indiana-jones-and-the-great-circle-accessibility-guide
- WCAG 2.3.1, three flashes: https://www.w3.org/WAI/WCAG21/Understanding/three-flashes-or-below-threshold.html
- So et al., navigation speed and cybersickness: https://www.ieda.ust.hk/dfaculty/so/pdf/So-et-al-2001a-HumanFactors.pdf
- Dizmen & So 2023, vection: https://www.ieda.ust.hk/dfaculty/so/pdf/Dizmen+So-2023-vection.pdf
- Fanatec, FOV trade-offs: https://www.fanatec.com/explorer/games/gaming-tips/optimizing-fov-for-sim-racing-getting-the-view-right/
- GTPlanet FOV discussion: https://www.gtplanet.net/forum/threads/field-of-view-fov-aka-why-does-that-track-look-so-wide.323267/latest

**Repo**
- `default.project.json`
- `src/client/PlayerMovement.luau`, `DummyTracker.luau`
- `tools/research/R2_CITY_INVENTORY.md`, `SPEED_SKYLINE_STREAMING.md`, `COMBAT_MOTION_DESTRUCTION_SYNC.md`, `R2_CHARACTER_NETCODE.md`, `R2_ENGINE_TESTS.md`, `GAME_DESIGN_DECISIONS.md`
- `tools/SHIBUYA_SOURCE_SLICE_HANDOFF.md` (0.2391 m/stud)
