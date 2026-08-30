# Roadmap

Where the game actually stands, and what has to happen to make it a game rather
than a sandbox. Ordered so that each phase produces something playable.

Status legend: **[done]** shipped · **[gap]** built but unreachable in-game ·
**[todo]** not written yet.

**Companion documents**

| Document | Answers |
|---|---|
| [CAMPAIGN.md](CAMPAIGN.md) | When it is set, what the story is, who you play as, who you meet |
| [PLANETS.md](PLANETS.md) | What is on each world, and how a map gets hand-authored |
| [LIVING-NPCS.md](LIVING-NPCS.md) | Free-form conversation, and the backend it shares with analytics |

This file stays the build order. Those three are the content.

---

## The one-line summary

The systems were largely built; the *seams between them* were missing. Phase 1
was almost entirely about connecting things that already existed, and it is now
**closed** — a player can walk, shoot, talk, trade, take a mission, finish it,
and spend the points. Phase 2a then opened the other eight worlds, and turned
out to be the same story one more time: the jump was already written and had no
caller.

What is missing now is not wiring. It is that the nine planets are the same
generator in nine colours (Phase 3). Phase 3b.1 closed on 2026-08-16: the
character you are is chosen, once, on a screen that will not let you past it,
and the choice reaches missions and conversations as well as the star map.

---

## Playtest findings — 2026-08-15

First run with all nine worlds reachable. Split into **bugs** (something is
wrong with what exists) and **new scope** (something that was never built).
The bugs are cheap and should land before any of Phase 3's content work,
because several of them make the content that already exists impossible to
*see*.

### Bugs and tuning

**All five were fixed on 2026-08-15.** What changed is recorded inline below.

**B1. Three worlds are too dark to play.** — **[fixed]** Reported for Korriban, Coruscant
and — as fog rather than darkness — Ord Mantell. Two independent causes:

- `AtmosphereController` runs a **day/night cycle** (`:297`, Heartbeat advances
  `Lighting.ClockTime` and lerps ambient toward `afterDark(...)` by
  `nightFactor()`). It is entirely possible to arrive on a planet at 02:00 and
  find it unplayable through no fault of the palette. **Suspect this first.**
  Options: clamp `nightFactor` so night never goes below a floor; hold new
  arrivals at midday for a minute; or give `PlanetDef` a `fixedClockTime` for
  worlds that should never be dark.
- The per-planet palettes are genuinely dark on top of that. Korriban's
  `ambientLight` is `RGB(90, 52, 42)` — the second darkest in the file, under a
  red fog at `fogEnd = 2400`. Ord Mantell is `fogStart = 200 / fogEnd = 2200` in
  purple-grey. Hoth's `fogEnd = 900` is deliberate (the comment says "whiteout:
  you cannot see trouble coming") and should stay.

The rule to write down: **atmosphere is allowed to set a mood, but never to hide
a landmark you are being sent to.** A fog end shorter than the distance between
two points of interest is a bug.

*Fixed:* `ARRIVAL_CLOCK = 9` — you now always land in the morning, instead of
inheriting whatever hour the *previous* planet's clock had drifted to. Night is
floored at `MAX_NIGHT = 0.7` so it never reaches full dark, and atmosphere
density is capped at `MAX_DENSITY = 0.45` (Ord Mantell was landing at 0.58).
Swamp air came down from 0.5/3.2 to 0.38/2.2. Korriban's ambient went from
`RGB(90,52,42)` to `RGB(126,82,68)` with `fogEnd` 2400 → 3000; Ord Mantell from
80/1200 to 220/2400; Coruscant's ambient lifted for the shade between towers.
Hoth's deliberate whiteout is untouched.

**B2. Every planet's buildings are identical.** — **[fixed]** Correct, and worse than it
looks. `PlanetBuilder.styleFor` (`:139`) switched on `planet.terrain` only, and
there are five branches for nine worlds:

| Style | Worlds |
|---|---|
| Desert | **Tatooine, Korriban** |
| Urban (default) | **Coruscant, Taris, Nar Shaddaa** |
| Forest/Swamp | **Tython, Ord Mantell, Dromund Kaas** |
| Ice | Hoth |
| Ocean | *(unused since Kamino was cut)* |

And a "style" is only `buildingColors`, floor counts, a `domed` flag, a window
colour and a scatter kind. The *geometry* — `buildBuilding` (`:307`), a stack of
tiered boxes with window strips — is the same on all nine. So Korriban is
literally Tatooine with different sand, and the boys can see it.

This is Phase 3.1's prefab work, and this finding **promotes it above 3b**. The
fix is not more terrain branches; it is that a planet declares an *architecture*
independent of its ground, and prefabs carry real shapes. Sith pylons and
ziggurats are not adobe domes with a red tint.

*Fixed:* `PlanetDef` gained an `architecture` field, and `Style` gained a
`shape` function — so a style is now geometry, not a palette. Nine architectures
for nine worlds, one each, none shared:

| Architecture | World | Reads as |
|---|---|---|
| `Adobe` | Tatooine | cylinder drums, hemisphere domes, slit windows |
| `SithZiggurat` | Korriban | stepped tiers, a lit mouth, flanking obelisks |
| `Ruin` | Taris | sheared shells, exposed girders, rubble at angles |
| `NeonStack` | Nar Shaddaa | shoved slabs, signs, a full-height neon strip |
| `Spire` | Coruscant | slow taper, dense window bands, mast and beacon |
| `Frontier` | Ord Mantell | stilts, corrugated hut, pitched roof, stovepipe |
| `JediStone` | Tython | colonnade, overhanging lid, stepped roof |
| `IceBunker` | Hoth | mostly buried dome, snow berm, tunnel mouth |
| `ImperialGothic` | Dromund Kaas | tower, corner buttresses, narrow red slits |

Terrain still picks the *scatter* (dunes, drifts, trees, rocks) — that one it
was always right about. `styleFor` no longer branches on terrain at all, and
PlanetBuilder warns at load about any architecture name it does not know, rather
than at the moment someone flies there. Coruscant's `Spire` was declared but
never drawn for two weeks — `hasWalkableGround = false` sent it down the
vertical-city path, which calls no room builder at all. `PlanetDef.decks` fixed
that on 2026-08-29; see **Coruscant's five decks** below.

**B3. Everything charges you on sight from a very long way off.** — **[fixed]**
Half of this was already solved and half was real:

- **Line of sight already exists.** `NPCBrain.hasLineOfSight` (`:278`) raycasts
  from the NPC to the target and excludes both models. Do not build it again.
- What is wrong is **range**. `findTarget` defaults to `sightRange or 120`
  studs, and the authored values run 120–300: SithLord **300**, Jedi 260, Sith
  220, ImperialCommando 240. At 300 studs an NPC starts running before it is a
  recognisable shape on screen. A prior fix already pulled one archetype down
  from 260 to 150 with a comment about "opening fire from the next district
  over" — that fix was right and was not applied broadly enough.
- And `isEnemy` (`:294`) **short-circuits on `Behavior.Aggressive`** before
  reading faction reputation, so those archetypes are hostile to everyone
  always. Already recorded as a hazard; this is the second time it has produced
  a visible bug.

*Fixed:* `NPCBrain` gained a **facing cone** — 120 degrees, so an NPC no longer
notices what is behind it. Inside `PERIPHERAL_RANGE` (22 studs) facing stops
mattering, because at that distance it hears you. Every archetype's
`sightRange` came down to 100–150 (SithLord 300 → 140, Jedi 260 → 130,
ImperialCommando 240 → 130, line infantry 160 → 110), and `MAX_SIGHT_RANGE`
clamps at 150 whatever the config claims. Being shot from behind still provokes
normally — that path never went through `findTarget`.

**Left alone deliberately:** the `Behavior.Aggressive` short-circuit. Changing
it decides whether Korriban has any threat at all for a fresh player, which is
a design call, not a bug fix. It belongs with N1 (disguises) and the faction-rep
reader in Phase 4, where reputation finally means something.

Still wanted, in rough order of value: a **detection ramp** rather than a boolean —
awareness builds with proximity, facing and whether you are moving, so there is
a moment to back away; **rear/flank arcs** so LOS means a cone rather than a
sphere; and **stealth as an actual input** (crouch, cover, sprinting is loud).
That last one is what makes B4 mean something.

**B5. Seven of the nineteen skills do nothing at all.** — **[fixed]** Found while reviewing the
trees. `Config/Progression.luau` defines 19 skills; grepping each `effect.stat`
for a reader outside `Progression.luau` and `SkillTreeController.luau` finds
**none** for:

| Stat | Skill | Why |
|---|---|---|
| `ShipSpeedMult` | Throttle Control | no ships |
| `ShipTurnMult` | Manoeuvring | no ships |
| `ShipShield` | Shield Harmonics | no ships |
| `FuelCostMult` | Navigator | travel is priced by fare, not fuel |
| `PushPower` | Force Push | the power itself is unimplemented |
| `SliceTier` | Slicer | nothing in the world is sliceable |
| `RepairMult` | Field Repair | no ship hull to repair |

**The entire Piloting tree is inert** — a player can sink 20 points into it and
gain nothing, and the UI happily sells them. Two of Engineering's four are dead
too. This is failure mode #1 again (a system with no reader), and it is the
worst instance so far because the player *pays* for it.

*Fixed:* `SkillNode` gained an **`unimplemented: string?`** field. `canPurchase`
refuses those nodes first, before it even looks at your points, so the reason is
the honest one; the panel already surfaces `canPurchase`'s refusal, and the row
now reads `COMING SOON` so nobody has to click to find out. Server-side
enforcement came free, because `ProgressionService` re-checks `canPurchase`.

**Points already spent on those nodes are not refunded** — the ranks are
harmless, since nothing reads the stats. Worth a migration only if it happens to
a real save.

**The rule this establishes: a skill does not enter `Progression.luau` without
either a reader for its stat or an `unimplemented` string.** Proper fix — making
them real — is §4.3 below.

*Follow-up 2026-08-16:* the rule was applied by hand, so it **missed two**, and
`Progression.validate()` now checks it at boot instead of trusting it. See §4.3.

*Follow-up 2026-08-17:* `SliceTier` came off this table — `TerminalService` and
`Dialogue`'s `minStat` both read it (§4.3 target 5). **Engineering has one dead
node left**, `Field Repair`, and it is waiting on ships like the whole Piloting
tree above it.

**B4. Ord Mantell has no missions.** — **[fixed]** The board read "No work going on this
planet right now." It is the Conscript prologue world and had zero entries in
`Missions`. Same failure family as §1.2's dead POIs: nothing errors, the world
is just empty when you arrive.

*Fixed:* a four-entry garrison chain covering the planet's whole 1–6 band —
**Pay and Rations** (1), **The Hill With No Name** (3), **Filed as Fatigue** (5)
and a repeatable **Bounty: Separatist Irregulars** (2). It follows the beats in
[PLANETS.md](PLANETS.md) "Ord Mantell" and uses only what the planet actually
has: Sgt. Marr is a `RepublicVeteran` because named NPCs do not exist yet, and
the separatists are the `Smuggler` stand-in that `Planets.luau` already spawns
in the Fields and the Wilds. The beat the data cannot carry — the Jedi liaison
going hollow mid-firefight — stays in the briefing text rather than becoming a
fake objective, until origins can gate content (CAMPAIGN §6.1).

Authoring this exposed a missing check, so `Missions.validate` now also
verifies that a **giver exists, is interactable, and spawns on its own
planet**. `giver` is matched against the archetype id of whoever you are
talking to, so a giver who does not stand there makes the board the only way to
take the mission and the conversation it was written for never happens — with
nothing erroring. All seventeen pre-existing missions pass.

### New scope

**N1. Disguise outfits.** Outfits already carry stat mods and level gates
(`Config/Outfits.luau`), so the data model has room. Design: an outfit declares
a `disguiseFaction`; `NPCBrain.isEnemy` consults it before deciding; it fails
under scrutiny — proximity to officers, drawing a weapon, being seen in a
restricted zone, or a species mismatch the costume can't hide (a Wookiee in
Imperial armour). Pairs with B3's detection ramp: a disguise should raise the
threshold, not zero it.

**N2. Non-lethal outcomes — jail.** Correct, and it is the missing half of the
morality system. Right now every encounter resolves in a corpse, which
contradicts the "decently dark, but you always have agency" tone in CAMPAIGN §6.
Design sketch: security-faction NPCs **subdue** rather than kill at 0 HP; you
wake in a cell with your gear confiscated, a fine to pay, a sentence to wait
out, or a way to break out — three exits, each rewarding a different tree
(credits / patience / Scoundrel or Scrapper skills). A bounty/heat value per
faction drives it, which is another *reader* for faction reputation.

*Correction, 2026-08-16.* Reputation was never the dead system this said it
was — `NPCBrain.isEnemy`, `Missions.canAccept` and `DialogueService` all read
it. What was dead was the player's view of it, and `Rank.creditStipend`, which
was declared on all 34 ranks and paid by nothing. Standing now shows on the
galaxy map beside the fare (attitude in words and colour, plus where you are on
the ladder), a promotion pays the stipends for every rank it crossed, and
`profile.factionRankPaid` stops the same rank paying twice. `Factions.validate`
gained the ladder checks the payout depends on — non-empty, starting at 0,
strictly ascending — since a ladder out of order pays the wrong rank silently.
Testable via `strengthandhonor`, which goes through `awardRep` so one code
exercises spillover, promotion and payout together.

**N3. Terrain variability.** Ground is a flat slab today. Wanted: mountains,
canyons, rivers where the world justifies them — Korriban's valley of tombs is
a *valley*, Taris is a ruined city under a shattered skyline, Ord Mantell has
swamp and water, Tython has hills and rivers, Nar Shaddaa has no ground at all.
This is a `PlanetDef` heightfield or Roblox Terrain pass and it should land with
3.1 so prefabs are placed onto real ground rather than a plane.

*Partly done — the skyline half.* `buildRelief` puts mesas, ridges or hills in
a ring outside the play area, keyed off `terrain` (nothing on Urban worlds,
where the horizon should be city). Nine worlds no longer share one straight
horizon, which is most of what "they all look the same at a distance" was.

**The walkable floor is still one flat slab, deliberately.** Every placement in
`PlanetBuilder` assumes ground at y = 0 — buildings, spawn markers, landmarks,
scatter — so real elevation is not a change to the ground, it is a change to
how five other things find their footing, and it wants the layout system (3.1)
underneath it. Rivers want the same. Do not call N3 done.

**N4. Paths, and how you cross a world.** A 3000x3000 slab with a 520-radius
town means most of the map is a walk across nothing. Two answers and we probably
want both: **authored paths** — roads, catwalks, ridge lines — that make the
wilderness legible and give a reason to leave them; and **vehicles** —
speeders/swoops for ground worlds, which is the natural home for the Scrapper
and Scoundrel signature chains. Nar Shaddaa and Coruscant are the forcing case:
a vertical city genuinely has no walkable ground, so it needs platforms, lifts
and air traffic or it needs a flier.

*Partly done — the paths half.* The settlement always left gaps between blocks
but never paved them, so a "street" was the same dirt as everywhere else and a
town read as buildings dropped on a plain. `buildStreets` paves the grid
(cut to the chord of the town circle, since the town is round and a square grid
over it runs streets out past the last house), and `buildMarkers` runs one road
from the town edge to every landmark standing outside it. Roads start at the
edge rather than the plaza on purpose: drawn from the centre they would cut
through whichever houses stood on the bearing, and inside the walls the street
grid already is the road.

That makes **following a road a navigation method that needs no UI**, and the
things roads lead to are the Reach objectives.

*And the vehicles half, 2026-08-17* — see §2b. Five speeders, bought from the
vendors that already exist, **V** to call one in. **Still open: the
vertical-city case**, which is the harder half of this item and the one thing a
speeder does not answer: Nar Shaddaa and Coruscant have no walkable ground to
hover over, so they need platforms, lifts and air traffic, or they need a flier.

**N5. Cities built out properly.** The standing request from day one, restated:
better designs, **indoor spaces you can enter**, more detail. Interiors are the
biggest single jump in perceived quality and are currently zero — every landmark
is a solid exterior. Suggest: a prefab may declare an interior, entered by a
door trigger, built as its own local space. Cantina, shop, barracks, tomb,
apartment. That also gives dialogue and vendors somewhere to happen that isn't
a street corner.

*Started.* Two landmarks now have insides — the **cantina** (bar, back shelf,
tables and stools, hanging lights, a dome that no longer collides because the
ceiling under it is the real surface) and the **base keep**, which is a barracks
with bunks, footlockers and a briefing table, its door lined up with the
compound gate.

Two decisions worth keeping. **Interiors are built in place**, not as a separate
space you teleport into: same ground, same coordinates, so pathfinding,
waypoints, line of sight, and the proximity prompts vendors and dialogue run on
all keep working without knowing interiors exist. And **a building with an
interior is built as a shell from the start** — nothing is hollowed out
afterwards, so there is never a solid version and a hollow version of the same
wall to keep in step. `roundWall` and `roomShell` in `PlanetBuilder` are the two
shells; a third landmark should need no new machinery.

**And there are people in them.** A `LandmarkDef` may declare an `interior`
offset, which becomes a part in that landmark's district zone — and NPCService's
map contract already reads a zone's parts as both spawn points and a patrol
route, so a cantina gets drinkers and the guards outside walk in and back out
again without a line of new AI. A room nobody is in is a room, not a place;
furniture was the cheap half of the job.

**Second playtest, and the lesson worth keeping: furniture is not slabs.** The
first pass built a bunk as one flat box and a briefing table as another, and
from inside the room they read as black rectangles floating against the wall —
the user's words were *"whats with the random blocks?"*. Anything the eye is
meant to *name* needs the part that holds it up: legs under a table, posts under
a bunk, a stem and a shade above a lamp, banding and skids on a crate, coping
and buttresses on a compound wall. Three or four parts each. The same rule
retired the base's bare 164-stud wall slabs, which had the same problem outdoors.

**Ordinary buildings, 2026-08-17.** The prediction held: no new machinery, and
the `roomShell` that was written for the base keep builds an authored shop
unchanged. A `PrefabDef` may now declare a `room` — the fittings that go inside
it — and `buildFromLayout` builds that cell as a shell instead of handing it to
`style.shape`. Anchorhead has **five shops and two halls** you can walk into.

Four decisions in it:

- **The door faces the street, and the building turns to suit.** `roomShell`'s
  doorway is always local +X, so `doorFacing` scores the four sides of the
  rectangle by how much open ground is against each and the whole shell is
  turned that way. Without it a door is a three-in-four chance of opening into
  the neighbour's back wall — and a door that does not open is worse than no
  door, because a player spends a minute finding that out. All seven of
  Anchorhead's rooms come out on a side that is 100% open.
- **Fittings are written in the room's own frame** (`at: CFrame`, `inner` swapped
  when the building is turned), which is why `roomShell` now takes a CFrame base.
- **A room is one storey, always** — so the prefabs with a `room` carry no
  `floorScale`. Stairs are a system this does not have, and a second floor would
  be a ceiling with nothing above it.
- **`Style` gained a `wallMaterial`.** The nine shape functions each pick their
  own materials part by part; shared machinery had nothing to ask, so an authored
  shop would have been concrete on all nine worlds. It is sandstone on Tatooine.

It also caught a live bug in 3.1: `ontoStreet` snaps an NPC patrol point onto the
**radial** generator's block lines, which an authored town does not have — the
whole Anchorhead crowd would have stood inside the houses. `ontoPaving` reads the
grid instead and takes the nearest paved cell; worst case a point moves 93 studs,
and every one of them lands on a street.

**And then somebody is behind the counter.** The rooms were finished and empty,
which is worse than solid: a lit shop with stock on the shelves and nobody in it
reads as a broken shop system rather than as scenery. The fix reuses the
cantina's mechanism rather than inventing a second one — each room now emits an
`Inside` marker into whichever district its cells fall in, and NPCService already
treats every part of a zone folder as somewhere one of that district's people may
stand. No new AI, no new spawn rule. `Behavior.Vendor` is `Idle`, so a merchant
put in a shop holds his post there.

Three things had to change with it, and only one of them was the marker:

- **`PrefabDef.room` returns where the floor is left clear**, in the room's own
  frame, because the code that placed the counter is the only code that knows
  what is still free — in front of the counter for a shop, past the end of the
  table for a hall. The marker is then kept well *inside* that: NPCService
  scatters within a part and drops to what is underneath, so a box reaching the
  counter puts a trader standing on it. Square, too, because `marker` builds
  axis-aligned parts and most of these buildings are turned a quarter circle.
- **Placement is emptiest-first, not a uniform roll.** With nine people over nine
  parts, the odds of every part being used were about one in a thousand. That was
  invisible while a part was a slice of a patrol ring — three traders on one
  spoke is a crowd either way — and stopped being invisible the moment a part
  meant *this shop*. `leastUsed` also makes a respawn fall back into the gap the
  death left, so a merchant killed in his shop comes back to it.
- **A room drawn outside every `ZoneDef.cells` rectangle is a boot warning.**
  Offline simulation found six of eleven rooms had no district that could staff
  them. Two were fixed by widening Town west to the hall block; the four
  back-street shops became houses, because inventing a district to hold one
  person would have moved that district's whole crowd. Hence five shops, not
  nine — the count is now a claim the map can keep.

Merchant count went 5 → 9 to match the Market's nine places. Adding a tenth `s`
now costs a trader, not a bug.

**Korriban is the second map, and the one that made it a system.** One authored
grid is an anecdote. Anchorhead is a town — a wall, a plaza, streets on a rough
square — and the question was whether the same twelve glyphs could draw something
that is not a town at all. Korriban is a corridor: the Academy behind its own
wall at the head, eleven rows of road and cliff with four tomb facades cut into
them, Dreshdae at the mouth. 21×28 cells, corner 560 studs, inside the 610 where
`buildScatter` starts.

Writing it broke two things, and both were the map telling the code it was wrong:

- **A landmark bigger than half a city block cannot stand in a district.** It is
  pushed out past the last street instead, which is right for a landing field and
  absurd for a Sith academy — the Academy would have ended up six hundred studs
  north of the Academy, with the students still in the Academy.
  `PointOfInterest.drawn` says *this place is already on the page*: build
  nothing, keep the name, the sign and the waypoint, and let the district's own
  `cells` say where it is. Validated at boot, because a `drawn` place with no
  layout or no `cells` is a named location with no building anywhere.
- **`rectBounds` answers with one radius, and a valley is not a circle.** The
  Valley is seventeen cells long and eleven across; the circle that reaches its
  ends also reaches eight cells into the Academy at one end and Dreshdae at the
  other. That is not a cosmetic overlap — the Academy is where a level 1 Acolyte
  opens their eyes and the valley bands nineteen levels above him. `rectExtents`
  gives the two half-sides and the patrol ring becomes an ellipse inscribed in
  the rectangle the author actually drew. The angle is untouched, because the
  ring is also the patrol route and a walker who doubles back has stopped
  patrolling.

Two decisions in the map itself are worth carrying into the next seven:

- **`Plaza`, `Yard` and `Lamp` are where players spawn**, since spawn markers are
  unclaimed anchors. So there is not one of them in the valley — the avenue is
  `.`, which paves without anchoring. Every anchor on Korriban is inside the
  Academy or inside Dreshdae, which makes this a level-band decision expressed in
  punctuation.
- **A district is also a casting call.** Dreshdae mixes civilians, researchers
  and traders, and emptiest-first placement does not care who it puts where — so
  the shopfronts got their own zone, `Bazaar`, at the same `distance` and
  therefore the same band. Two counters in a district containing nothing but
  merchants cannot be staffed by a farmer.

**Taris and Ord Mantell are the third and fourth, and they finish the openings.**
Four origins start on four worlds; two of them were already drawn, so drawing
these two means **nobody's first five minutes are procedurally generated any
more**. Neither map needed a new feature — which is the point of writing them
now, while the rules from Korriban are still one commit old.

- **Taris** is a fence with a colony above it and a dig below. North is a grid
  of identical prefab shacks, because that is what a resettlement colony is:
  the same building stamped out by the same contract. South of the gate is the
  Dig, a scatter of Czerka survey towers around two field halls — the only
  district in the game that is authored and still meant to look unplanned. Its
  legend uses `#` for `Wall` rather than `W`, which is not decoration: legends
  are per-planet, and this is the map that proves it.
- **Ord Mantell** is the argument between a diagram and a war. Fort Garnik is
  perfectly symmetrical — four barracks around a muster square, a watchtower on
  each front corner, one gate. Everything the army is actually doing is south of
  that gate, in the **Savrip Fields**: four trench lines drawn as rows of the
  same glyph as the fort's own rampart, with the gaps staggered, and *nothing
  else at all*. A trench is a row of one character, which is the thing the tile
  map was for.

Both applied Korriban's two rules without being told: Taris's two shopfronts got
a `Depot` district and Ord Mantell's got a `Market`, each split off at the *same*
`distance` so no band moved; and the Savrip Fields carry **zero anchor cells**,
so no level 1 Conscript wakes up in a trench with fourteen militia. Ord Mantell
goes further and **does not declare `Yard` in its legend at all** — a glyph
meaning "open ground you can also spawn on" is precisely the one that gets
sprinkled somewhere dangerous without anyone noticing.

**The checker is now the thing that catches this, not care.** Ord Mantell's grid
was assembled by concatenating a village column and a fields column and came out
ragged on eleven of twenty-four rows. `Planets.validate` would have reported it
at boot, but boot is a Studio session away. `/tmp/gridcheck.py` **parses
`Planets.luau` itself** — grid, legend, zones and spawn counts — and re-runs
`layoutRects`, `walkable`, `doorFacing`, `cellOffset` and `rectExtents` offline,
reporting ragged rows, undeclared and unused glyphs, rooms whose middle cell
lands outside their own district, rooms with no walkable side, anchors per
district, out-of-bounds `cells`, districts with fewer NPCs than parts, and the
610-stud scatter corner. Copying a grid into the checker is the mistake the
checker exists to catch, so it does not accept a copy.

**Nar Shaddaa is the fifth, and it is the first city.** The four before it are
settlements — a town, a corridor, a colony, a fort — and all four are drawn as
figures on open ground. A moon-wide city is the opposite: **no open ground
anywhere**, every road one cell wide with a building pressed against both sides,
nothing symmetrical, no two stalls the same width. One bulkhead across the
middle with two gates in it, and that line carries the whole social geography —
people shop north of it; south of it are the docks and the sector where the moon
puts the people it has finished with. Six shopfronts, because PLANETS.md
promised "every vendor in the game" here and the moon had no interior at all.

Two things fell out of drawing it, both of the "nothing reads X" kind:

- **`PlanetDef.verticalCity` was dead.** PLANETS.md said Nar Shaddaa had no
  walkable ground and would reuse the Coruscant tower code; the config said
  `hasWalkableGround = true` and had said so all along. The field that agreed
  with the document was `verticalCity`, and **no code in `src/` ever read it** —
  `hasWalkableGround` is the only switch. Deleted. Verticality on this moon is a
  later feature, not a reason to have no streets.
- **`gridcheck.py` was under-counting every dangerous district.** Its spawn
  regex matched a one-line entry, and StyLua wraps any entry carrying a
  `behavior` across four lines — which is *every aggressive spawn in the game*.
  Korriban's valley was being reported at 14 NPCs when it holds 22. Replaced
  with a brace scanner. The bug could only ever have produced a false alarm, but
  a checker that quietly skips the interesting rows is worth less than no
  checker.

**Tython, Hoth and Dromund Kaas finish the set — every walkable world in the
galaxy is now drawn.** Eight grids; Coruscant was ruled out here as *the one
planet that should not get one*, since `hasWalkableGround = false` genuinely
sends it down `buildVerticalCity`. **That was wrong, and it took a play test to
show it** — see **Coruscant's five decks** below. The last three were each drawn around a single sentence the
planet already said about itself:

- **Tython built nothing it could defend**, so it is the only grid in the game
  with **no `Wall` and no `Gate` anywhere on it**. The one thing on the map that
  lines up is the Temple precinct; Kalikori Village below it is deliberately
  crooked, because the Twi'leks were there first and were not asked.
- **Hoth is one line — inside the wire or not.** Two halves of a page with a
  single gate between them. The Graveyard's hulls are drawn as **`Wall`**, which
  is the trick that map turns: a rampart is a long run you cannot walk through
  and can walk *on*, which is what "you do not cross it, you climb it" has
  always claimed. Staggered so the gaps never line up, so crossing it is a route.
  No shops anywhere, because Hoth's spawn list contains no Merchant at all.
- **Dromund Kaas is a diagram of a state.** The only settlement in the galaxy on
  a true lattice — sixteen identical blocks, four to a rank. Anchorhead is
  crooked because it grew; this is straight because it was issued. The Nexus
  Road is four cells wide with a rampart down each side and **no anchor cell
  between them**: ten aggressive Honour Guard live in that corridor, and anchors
  are where players spawn.

A third "nothing reads X" fell out, and it was in the checker again:
**`gridcheck.py`'s zone parser had the same one-line-regex bug its spawn parser
had.** StyLua wraps a zone entry the moment `id` is long enough to push `cells`
over the column limit, so `Spaceport`, `NexusRoad` and `DarkTemple` were parsed
as *not existing* — and a room in a district the parser cannot see reports as
`zone=None`, which is a **false** alarm rather than a missed one. It was caught
because `-v Tython` on its own passed and `./check.sh` did not: the difference
was that `check.sh` runs StyLua first. Same fix, the brace scanner.

Still open: tombs and apartments as interior types.

**Finding the place at all.** Also from the second playtest: *"I have no idea
where the cantina is."* Roads answer "where does this go" once you are standing
on one, and a landmark's own sign is deliberately short-ranged so signs do not
outrun the fog — so nothing answered the question a player actually asks. There
is now a **finger-post in the plaza**: one arm per landmark, turned to its
bearing, labelled. It sits at the one spot everybody passes through. Not enough
on its own — a "points of interest" layer on the galaxy map is the other half.

The first version of it got two things wrong, both in one screenshot: *"it'd be
great if the actual writing was there rather than floating words. Also, I don't
see cantina here."* The labels were BillboardGuis, and a BillboardGui always
turns to face the camera — so six of them on one post are six lines of text
stacked in mid-air, attached to none of the planks. They are SurfaceGuis now,
painted on both faces of the arm. And the cantina *was* there, labelled "The Dry
Well", which is no help to somebody hunting for a cantina: signs now lead with
the kind, and only the building's own nameplate leads with the name, since
standing in front of it you can already see what it is.

**N6. An economy, not just a wallet.** The largest new ask, and it is really
five features:

1. **More ways to earn** than mission rewards and loot: salvage, courier runs,
   bounties, gambling, crafting.
2. **Property.** Buy and sell homes. A home is also the natural place to hang
   the "ship interior customization" wish from `note.txt` — same system, one
   is parked.
3. **A market with moving prices.** A "stock market of sorts": commodity prices
   per planet that drift and react, so buying spice cheap on Nar Shaddaa and
   selling it on Coruscant is a *trade route*. This is a better fit than equities
   and it makes travel (Phase 2) economically meaningful instead of a toll.
4. **Player-to-player trading**, Diablo-style. **No longer blocked** — the
   inventory is a map of stacks (`73dc1db`), and `Inventory.take(inv, uid)`
   already lifts one specific item out. A trade is that stack re-keyed through
   `Inventory.add` on arrival.
5. **Loans**, with the debtor who does not pay and the mission that follows.
   This is genuinely good: it is a *generator* for radiant missions (Phase 4.0)
   with a built-in reason to care about the target, and it converts the economy
   into content instead of a number that goes up.

Sequencing note: 1 and 3 are cheap and can ride along with Phase 3. 2 and 5 want
persistence and are Phase 4. 4 is unblocked and can be picked up whenever.

---

## Playtest findings — 2026-08-17

Reported in one sentence, and it contained two unrelated failures of the same
kind: **a system that is finished but that the player has no way to reach is not
a system.** Both are fixed; both left a check behind, because both were the sort
of thing that is invisible from inside the file that caused it.

> *"I'm unsure how to use powers, where we see the skills tree, etc. I tried to
> start as the acolyte and completed the first mission but I had to go to an area
> that said level should be above 18."*

**C1. Six panels reachable only by a letter nobody was told.** — **[fixed]**
Abilities on 1-6, and B/M/J/K/G. All six worked. Nothing in the game had ever
named one. The key moved out of each controller's private `TOGGLE_KEY` and into
`Panels.PanelDef.toggle`, and `HudController` draws a permanent top-left legend
by walking `Panels.ALL` — so a panel is advertised by being registered, which is
the bargain that file already makes for input focus and mutual close. Buying an
ability now toasts its name and its key once. See TESTING §9.0.

**C2. The Acolyte's first mission walked a level 1 character down a level 19-30
corridor.** — **[fixed]** *The Empty Bunk* sent you to Dreshdae, and the only
road there is the Valley of the Dark Lords: 22 aggressive things, and the client
correctly met it with **TURN BACK**. Three separate causes, each harmless alone:

- The Academy had **no interactable NPC at all** — `SithAcolyte` and
  `ImperialTrooper` are both `interactable = false` — so "ask around" had
  nowhere in the district to happen. Czerka `Researcher`s now spawn there, which
  is also the right piece of fiction: the form that collects an acolyte was
  printed by a contractor.
- `SithAcolyte` was declared **22-38 against a district banded 1-12**. It spawns
  in exactly one place in the galaxy, so `rollLevel`'s clamp pinned every one of
  them to an end and the Acolyte's own home world contained nothing fightable.
  2-14 now, and `repOnKill` -25 rather than -150: six sparring matches used to
  turn the Academy hostile to its own student.
- **Act 2 was six missions, all on Tatooine and Ord Mantell** — the Scoundrel's
  and the Conscript's worlds. The Acolyte and the Scrapper had *nothing* between
  their prologue at level 2 and their signature chain at 12, which reads exactly
  like a game that has run out. Four new missions, two per origin, both chains
  staying in the district the origin already stands in, both ending by naming the
  star map. That debrief is the first time the game has said travel is possible.

`Missions.validate` now refuses an origin's first mission that has no `next`, or
one whose objectives sit more than twice `UNDERLEVELLED_BY` above it. **The band
half is deliberately scoped to prologues**: sending a player somewhere dangerous
is a normal move and twenty existing missions do it on purpose — a general
version of this check produced 20 false hits, including the whole Tatooine
opening chain. It is only ever wrong for the mission nobody chose.

### The second report, same day

Played again after C1 and C2. Five findings, and **every one of them is a system
that already worked** — the fix each time was the part the player could see.

> *"What do you mean by force tree? I'm not seeing a tree anywhere."*
> *"I should have an inventory screen where I can see and equip my items."*
> *"I have this ridiculously long lightsaber but I have no way to actually swing
> it. I'm also not a huge fan of the blaster physics and options. I'd think we'd
> have the ability to have a reticle or other / better way to fire."*
> *"I still don't know what's going on, who I am."*
> *"I don't have any other missions I can complete or a means to level up."*

**C3. The skill tree was drawn as a ladder.** — **[fixed, `1108c1d`]**
`requires` has always been real; `nodesInTree` sorted by level then name, so the
structure was visible to everything except the player. `Progression.treeRows`
walks it depth-first and returns a depth; the panel indents and draws an elbow.

**C4. Nowhere to fight on day one.** — **[fixed, `1108c1d`]** Not a shortage of
enemies — a shortage of enemies a level 1 character could reach. One hostile
district a gate away from each origin's camp, banded at the planet's floor, and
`Origins.validate` now refuses a home world whose weakest enemy is more than
`UNDERLEVELLED_BY` above that floor.

**C5. The blaster had no aim and the saber had no swing.** — **[fixed]**
`AimController` (priority 22): hold **Mouse 2** for an over-the-shoulder camera,
a centre-locked mouse, a character that faces where you look, and a **reticle
sized from `WeaponDef.spread`** — the same number `CombatService` applies, so the
reticle cannot lie. The permanent HUD dot is gone; it claimed something the game
was not doing. The saber's blade drops 8.5 studs to **4.2** with `range` moved to
match (`swingMelee` reaches about `range * 1.1`, so a shorter blade with the old
range would have moved the lie rather than fixed it). The swing itself was always
dealing damage and always broadcast — `EffectsController` discarded every melee
`WeaponEffect` — so it now draws a **Motor6D arm arc** (no marketplace animation
asset), alternating direction, with a `Trail` built into the replicated weapon
model and a spark hung off `DamageDealt`, which is the only honest source for
where a server-side sweep actually landed. See TESTING §9.0a and §9.0b.

**C6. The inventory was unreadable at a vendor.** — **[fixed]** Equipping always
worked; the panel drew four things you owned mixed into a whole catalogue.
`ItemEntry.carried` was already on the wire, so the split is client-only:
**CARRIED** above **&lt;VENDOR&gt; SELLS**, headers suppressed away from a shop
where every row is yours, and the default selection prefers something you own.

**C7. Nothing told you who you were.** — **[fixed]** `OriginDef.blurb` and
`.mentor` were shown once, on a modal dismissed to start playing, and the choice
was acknowledged by a four-second toast. Two changes, both pure views of the
profile that already replicates: a **card** on `originChosen` going true (stays
up, takes input focus, names the mentor and the two keys) and a pinned **Who you
are** page at the top of the Journal (**J**) — origin, level, alignment band,
mentor, standing, home world, and what The Quiet is once the character has met
it. No new remote and no new field. See TESTING §6.1 step 4 and §7.2 step 0.

---

## Playtest findings — 2026-08-18

Three findings, one of them a screenshot rather than a sentence.

> *"not sure what's happening here."* (a photograph of seven NPCs heaped
> against the side of a building, interpenetrating)
> *"Id think purchasing vehicles / spaceships should be colocated with
> spaceports or other areas where it makes sense vs having one guy who sells
> everything."*
> *"how do i ride in the vehicles?"*

**C8. The whole district was walking into the same wall.** — **[fixed]** Two
defects, either of which is survivable alone.

- **The patrol route ran through the inside of every building in town.** A
  zone folder's parts have always meant two things to `NPCService` — one is
  handed out as somewhere to stand, and all of them together are the
  district's circuit. That was true and harmless while a marker was a patch
  of street. Then 3.2 gave rooms interiors and `PlanetBuilder` started
  writing an `Inside` marker into the zone folder for every authored room and
  every landmark, so the circuit acquired a stop inside each of them and the
  district's entire foot traffic was under standing orders to walk through a
  wall. Markers that are places to stand rather than places to walk through
  now carry **`PlanetBuilder.OFF_ROUTE`**, and `placementFor` builds the
  route from the rest — an attribute rather than a name match, because
  `Inside07` is a convention and a convention breaks silently. Somebody
  spawned *on* one gets no route at all, which drops `Patrol` through to
  `Guard`: a shop gets a shopkeeper, which is what the room was for. Fewer
  than two outdoor points left means no route either — a one-point circuit is
  an instruction for the district to converge on a single spot, which is this
  bug again with fewer steps.
- **Nothing in the brain ever gave up.** `requestPath`'s failure branch walks
  at the goal in a straight line and lets the Humanoid bump into things,
  which is right for a rock and wrong for a building, because the bump never
  ends. Nothing above it asked whether the walking was getting anywhere, so
  an NPC whose goal sat behind a wall pressed into that wall for the rest of
  the session — and several of them heading for the same unreachable room
  pressed into it together, which is the photograph. `moveTo` now samples
  progress (four studs in six seconds, measured on the root, sampled only
  when the NPC is actually being *asked* to move, so standing still on
  purpose is never mistaken for stuck). Patrol skips the waypoint; Guard
  stands down where it is and keeps the post's facing.

**C9. One trader sold everything, including starships.** — **[fixed]** The
counter that hands you a hyperdrive between the ration packs and the blaster
charges. Split by the user's call — **starships only**: a new `ShipYard` shop
and a `ShipBroker` archetype that spawns at all five spaceports and nowhere
else, carrying the three hulls and the twelve cabin furnishings; `GeneralGoods`
keeps the four speeders, because the point of a speeder is that the walk you
are sick of is the one you are in the middle of right now, and selling them out
of a garage district is the joke that writes itself. It costs the player
nothing they had: `Ships.PAD_TAG` already meant a hull could only be *called
down* at a spaceport, so the change is that you can no longer buy something you
could not use without first walking to where it works.

Placing him needed **`SpawnRule.poi`**. Three of the five spaceports are drawn
into their grid and their district *is* the landing field, so the zone was
enough. Anchorhead's and Coruscant's are single buildings — and a spaceport is
too wide for a city block, so it stands out past the last street while the
district it belongs to holds thirty-two other people. `poi` names the landmark
and takes the marker tagged `PlanetBuilder.AT_POI`. `Planets.validate` refuses
one that names an unknown POI, a drawn one, or one in a different zone: all
three would fail identically at runtime by falling back to the district, which
is the config-that-silently-does-nothing failure mode. `LANDMARKS.Spaceport`
gained an `interior` for this — thirty studs out the front of the tower, clear
of its footprint and well inside the pad ring. Not everything called an
interior is indoors.

**C10. Nothing said how to board a vehicle.** — **[fixed]** Seats are entered
by touch, which is a Roblox convention and not a fact about this game; there is
no prompt over the saddle, and `VehicleSeat` turns WASD into `Throttle` and
`Steer` for free, which is exactly why no screen ever mentioned it. The summon
toast now says it. The pitch keys are named only on a starship — a speeder has
no use for them, and a line listing two controls that do nothing teaches the
player the rest of the line might be wrong too. Same shape of fix as the three
Phase 6 omissions: extend a message that already exists.

---

## Design direction — Diablo-style (decided 2026-08-14)

The target is an action-RPG loop: kill things, level, spend points, find better
gear, walk somewhere harder. Three consequences, in the order they should be
built:

1. **Skill tree screen** — **[done]**, see 1.5.
2. **Loot with rolled affixes** — **[done]**, `73dc1db` / `accb151` / `3ab7e9a`.
   The data model went first: `profile.inventory` was `{ [itemId]: count }`, a
   bag of counts that cannot hold two different rolls of the same blaster.
   `Shared/Core/Inventory.luau` now owns the shape — a map of stacks keyed by
   uid, each optionally carrying `rolls`. A map rather than an array because a
   profile is both DataStore-serialised and replicated, and neither survives a
   sparse one. `Inventory.load` still reads the old shape, so old saves come
   back intact.

   `Config/Affixes.luau` holds ten affixes, one per stat something actually
   reads, five rarities named by affix count (0–4), and the roller.
   `Affixes.validate(Progression.baseStats)` runs at boot and reports any affix
   whose stat nothing consumes — the same "no dead stat" rule the skill tree
   broke once already.

   `profile.equipped` now names an inventory **stack**, not a catalogue entry.
   That is the piece that makes rolls do anything: `ProgressionService` folds
   the equipped outfit's *and weapon's* rolls into `computeStats`. Everything
   that reads `equipped` resolves uid → id through `Inventory.idOf`; plain
   items keep their id as their uid, so nothing in an existing save changed
   meaning. The B panel is one row per stack accordingly, coloured by rarity,
   with roll lines under the base stats.

   `Config/Loot.luau` derives its pool from the Weapons and Outfits catalogues
   by level instead of authoring a drop table, so it cannot name an item that
   does not exist. A Common roll is treated as **no drop at all** — a plain
   blaster identical to the vendor's is clutter, and plain stacks merge by id
   so it would not even be a second item. About one drop per seven kills, tuned
   by `Loot.DROP_CHANCE`.

   **Bag size and a way out of it — done.** `Inventory.MAX_ROLLED` (30) caps
   *rolled* items only: plain stacks merge by catalogue id, so the catalogue
   itself is their ceiling and only drops are unbounded. Being over the cap is
   legal, so an old save comes back whole and simply takes nothing more. The way
   out is the B panel's second button — **SELL** at a vendor (`RarityDef.value`
   × `Shops.SELL_FRACTION` ÷ the vendor's own `priceMult`, so the dearest trader
   also pays the least), **DISCARD** away from one, with a two-press confirm.
   Neither will touch what is equipped: `profile.equipped` naming a uid that no
   longer exists would hand the player nothing on their next respawn.

   **The affix slot was too coarse, and is now `WeaponDef.class`** (2026-08-18,
   from a playtest: *"when I'm wielding a lightsaber, seems weird to modify
   blaster power since that's not a thing"*). `slot` had only been Weapon or
   Outfit, so `Affixes.validate` could prove a stat had *a* reader but not a
   reader on the item it rolled on — and `BlasterDamageMult`'s reader returns
   early on anything that is not a blaster. Four combinations printed a number,
   priced it into the rarity and did nothing. The Legendary-pool check now walks
   `Weapons.classes()` rather than a list written here, so a class nobody has
   written affixes for arrives as a boot warning. `MeleeDamageMult` followed on
   2026-08-19: with the dead affixes gone, Melee's pool was exactly
   `MAX_AFFIXES`, which made every Legendary vibroblade identical.

   **`Loot.repair` is the one migration in the game.** Fixing the roller did
   nothing for saves that already held a *Vicious Lightsaber*, so every load
   re-rolls dead affixes onto the item's real pool. It **replaces rather than
   strips**: rarity is derived from affix count, so deleting them would demote a
   Legendary won fairly on the strength of a bug that was ours. Rolled at the
   item's `requiredLevel`, the only level the item itself carries — it errs low,
   which is the right direction for a rewrite nobody can audit.
3. ~~**A large world banded by level.**~~ **Done 2026-08-16.** `ZoneDef.distance`
   was already the difficulty dial in intent; it is one in fact now.
   `Planets.bandFor(planetId, zoneId)` spreads the planet's own
   `minLevel..maxLevel` across its districts by distance — a sliding window
   `Planets.BAND_WIDTH` (a quarter of the range) wide, so consecutive bands
   overlap and the step out of a district is a slope rather than a cliff. Bands
   are derived, not authored: 45 hand-written pairs would only repeat what the
   dial already says and then drift from it. `ZoneDef.band` overrides the
   handful of places where difficulty and remoteness genuinely disagree, and
   `validate` rejects one that is inverted or outside the planet's own range.

   `NPCArchetypes.rollLevel` takes that band and **narrows the archetype's own
   range with it** rather than replacing it — a Jawa in the deep desert sits at
   the top of what a Jawa can be, not at level 40.

   The warning is `ZoneController`. `PlanetBuilder` publishes each district's
   `Centre` as an attribute on its zone folder — districts are placed
   procedurally from the planet's seed, so that is the only record of where one
   landed — and the client picks the nearest with hysteresis, because districts
   have no borders and standing on the line between two would otherwise flicker.
   Crossing into a new one names it and states its level range, in red with
   "TURN BACK" when `Planets.underlevelled` says its floor is more than
   `UNDERLEVELLED_BY` (3) above you. Client-only; no new remote, and the band
   comes from the same shared config the server levelled the NPCs from, so the
   warning cannot disagree with the fight.

Also wanted, not required: **complementary co-op classes** — a Jedi and a
soldier who play differently and cover each other. The four skill trees
(Combat / Piloting / Force / Engineering) are already shaped for this; what is
missing is a reason to specialize, which means abilities that only deep
investment unlocks, not just bigger numbers.

---

## Campaign direction — decided 2026-08-14

Four decisions, taken together, that everything after Phase 2 depends on. Full
reasoning in [CAMPAIGN.md](CAMPAIGN.md).

1. **Era: the Old Republic, ~3,640 BBY.** The Sith Empire and the Republic in
   open war after the Sacking of Coruscant. Chosen because it is the only era
   where a Sith orphan is *normal* — the Korriban Academy is a school full of
   them — and because both sides are governments, so a Sith player and a
   Republic player can co-op without either being a traitor.
2. **Four origins that converge.** Acolyte (Force), Conscript (Combat),
   Scoundrel (Piloting), Scrapper (Engineering) — one per existing skill tree, so
   it adds no new axis. A ~20 minute prologue each, then a shared main story.
   Each origin's mentor becomes another origin's stranger.
3. **Cameos only; the player stays a nobody.** Malgus, Satele Shan, HK-47,
   Mandalore. Set pieces and quest-givers, never party members, never a fight
   you win.
4. **Authored layouts, generated buildings.** An ASCII tile map per planet in
   config; the geometry stays procedural code. See PLANETS.md §2.

Since settled, same day: **a lightsaber is built over five quests, not bought**,
which gave every origin its own signature chain (3b.5); the tone is **decently
dark**, written up as a usable in/out list in CAMPAIGN.md §6; **Ord Mantell is
worth a ninth world** for the Conscript's prologue; and the game is called **The
Hollowing**.

**Cost of the era decision:** Naboo, Kamino, Mustafar and Endor are replaced by
Korriban, Tython, Taris and Dromund Kaas, plus Ord Mantell as a ninth — **still
owed.** The factions and 13 archetypes were re-dated 2026-08-15 and are **done**;
six more archetypes are still to add. All 15 missions are rewritten — they were 5
unconnected chains with no theme, so that was owed anyway. Every service, weapon,
outfit and skill is untouched: the engine does not care what era it is.

---

## Where data lives — decided 2026-08-15

Prompted by a good question: should planets, characters, weapons and missions
live in Supabase rather than being hardcoded, so content can be composed
dynamically?

**Static content stays in Luau `Config/` files. Runtime state that outlives a
server instance goes in a database.** The line is not "files vs. database" but
*authored vs. accumulated*.

The `Config/` tables already are a database — `Factions.defs` is keyed by id,
`Missions.boardFor` is a query, `Missions.validate` is referential integrity.
Four things would be lost by moving them out of the repo, and all four have
already been paid for:

1. **The client could not read them.** `HttpService` is server-only; there is no
   raw TCP, so no database driver. `InventoryController` and `SkillTreeController`
   require `Shared.Config.*` and get it through replication for free. Remote
   config means relaying every weapon stat over remotes.
2. **`--!strict` would stop applying.** JSON is `any`. The 2026-08-15 faction
   migration was safe *because* ids are type-checked at author time and
   cross-checked by `validate()` at boot — a database would surface the same
   mistakes in a Play test instead.
3. **`git revert` would stop working.** A bad balance change is currently one
   command. As a row update it is a mystery.
4. **Boot would become a network call**, per server instance.

What studios actually do is this: Unity ships `ScriptableObject` assets, Unreal
ships `DataTable`s, both in version control. Remote config exists but is scoped
to what must change *without shipping a build* — and on Roblox, publishing takes
seconds, so that pressure barely exists.

**Dynamic mission composition is a generator, not a storage problem.** Picking
an archetype × a POI × an objective template × a level band reads the tables we
already have and writes nothing. That is how Diablo's bounties and Skyrim's
radiant quests work, and it is the right shape for the ARPG direction above.

Where a backend does earn its place: analytics (4.1), cross-server state (5.2)
and free-form conversation (5.1) — all three accumulate, none are authored, and
all three share one backend. See [LIVING-NPCS.md](LIVING-NPCS.md) §5.

---

## Phase 1 — Close the loop (highest value, lowest cost)

Nothing here is a new system. Each item is a missing connection between two
things that are already written and tested.

### 1.1 Mission board UI — **[done]**
`MissionBoardController.luau`, opens with **M**. Available / Active tabs, briefing
and objective detail, accept and abandon, backed by the existing
`GetMissionBoard`. Opening it closes the inventory and vice versa, and
`InputController.uiHasFocus` now covers both so reading a briefing does not fire
your blaster.

There is no `TrackMission`, on purpose: the HUD already renders *every* active
mission (`HudController.luau:260`), so a single tracked mission is not a concept
the game has. It sat in `Net.Event` unimplemented until 2026-08-18 and was then
deleted, because `Net.ensureRemotes` builds a RemoteEvent for every declared
name — an unused one is not a dead identifier, it is a live remote with nothing
listening on either side.

### 1.2 Collect and Deliver objectives — **[done]**
`PickupService.luau` puts the items in the world: one shared, respawning pile per
planet, placed at the objective's new `at` point of interest, taken with a
`ProximityPrompt`. Its spawn table is derived from the missions rather than
hand-written, so it cannot drift out of step with them.

Delivery is handled in `MissionService.sweepPlayer` — standing at the destination
carrying the goods. Items are deducted under a fresh inventory read, so two
missions wanting the same crate cannot both be paid for it.

`Items.luau` holds the six quest items (deliberately separate from `Weapons` and
`Outfits`: these are carried and spent, not owned and equipped). `Missions.validate`
now checks `at` and item ids, and `WaypointController` points at `Collect`.

### 1.3 Dialogue system — **[done]**
`Config/Dialogue.luau` holds 17 authored trees; `DialogueService.luau` runs the
conversation entirely on the server; `DialogueController.luau` draws it. The
panel is 250 tall and sits at the bottom of the screen rather than covering it,
so you keep looking at the person you are talking to. Replies are numbered and
the number keys work.

The client is sent a node and a list of replies and answers with an *index into
that list*, so it can only ever pick something it was actually offered. There is
no client-callable "start talking" remote either — `NPCService`'s proximity
prompt is the only way in, so there is no range check to spoof.

Mission offers are derived, not authored: the "anything that needs doing?" reply
builds itself from `Missions.boardFor` filtered by `giver`, so a new mission
with `giver = "Merchant"` is offered by every merchant in the galaxy with no
dialogue edit.

`TalkTo` finally has a caller, deduped per NPC so pressing E four times at one
Jawa is not four conversations. Four `TalkTo` objectives were also broken:
"convince the Jawas" was authored as a **Kill** against unarmed traders, one
pointed at a point of interest, and two named characters (`TheedInformant`,
`DelinquentDealer`) that were never written. `Missions.validate` now rejects a
`TalkTo` whose target is not an interactable archetype. Four mission givers
(BountyHunter, CartelEnforcer, RebelTrooper, NabooGuard) had no prompt at all
and were unreachable except through the M board.

### 1.4 Vendor discovery — **[done]**
`VendorController.luau` puts a billboard over shop NPCs: the shop's name plus
either the distance or, once you are inside trading range, `[B] Trade` in
accent. Nothing on it is interactive — trading already worked through the
`ProximityPrompt` every NPC carries. The missing piece was *discovery*: that
prompt only appears at 12 studs, so you had to already be standing next to the
right person to find out they were the right person, in a market square holding
five merchants and seventeen identical-looking civilians.

Two deliberate constraints. Only the **nearest four** vendors are labelled, from
a fixed pool of billboards that get re-pointed rather than rebuilt — Tatooine
spawns 14 Jawas and 5 merchants, and signing all nineteen would be worse than
signing none. And these are **not** `AlwaysOnTop`, unlike the objective beacon:
a shop sign glowing through a building is how you walk into the building.

The trading radius moved to `Shops.VENDOR_RANGE` so the client's cue and the
server's enforcement read one number. Two copies would drift, and the visible
symptom would be a prompt that lies.

### 1.5 Skill tree UI — **[done]**
`SkillTreeController.luau`, opens with **K**. A tab per tree, rank pips per node,
an XP bar, and a preview of what the next rank buys. The Spend button carries the
refusal reason straight from `Progression.canPurchase`, so it explains a locked
node instead of doing nothing.

Points had been accumulating unspendable since the first kill: `SpendSkillPoint`,
`ProgressionService.purchaseSkill` and the 18 nodes all existed, and nothing on
the client ever fired the remote.

> Every objective kind now has a way to be completed, every mission has a person
> to take it from, and every shop has a sign.

**Phase 1 exit criterion:** a new player can spawn, be pointed at a quest-giver,
accept a mission, complete every objective kind, and turn it in for credits.
**Met on paper — needs a playtest to confirm it in practice.** There is no way
to execute Luau offline, so nothing in Phase 1 has been run; `validate()` at
boot and `check.sh` cover the static half only.

---

## Phase 2 — Space and the galaxy

The single biggest content multiplier: nine planets are authored
(`Config/Planets.luau`) and until 2a only one was reachable.

**There is no ship code today** — not a config, not a model, not a service. The
word "ship" appears in `Planets.luau` only as flavour text and one comment about
fuel range. This is a from-scratch phase.

### 2a. Travel without flight — **[done]**

`Config/Origins.luau` + `TravelService` (priority 38) +
`GalaxyMapController` (**G** key, priority 44).

`PlayerService.travelTo` already swapped planet folders, respawned the character
and ran the gravity/atmosphere transition — and, in this codebase's oldest
failure mode, **had no caller anywhere**. So 2a is not the jump; it is the policy
in front of it and the door into it.

**Travel differs by origin, not by a flat number.** Each of the four origins gets
somewhere by a different *mechanism*, expressed as three fields
(`patron`, `fareMultiplier`, `cooldown`):

| Origin | Tree | Home | Travels by | Free when | Fare | Cooldown |
|---|---|---|---|---|---|---|
| Acolyte | Force | Korriban | Imperial shuttle | either end is Empire-held | ×2.0 | 30 s |
| Conscript | Combat | Ord Mantell | Republic troop transport | either end is Republic-held | ×1.4 | 75 s |
| Scoundrel | Piloting | Tatooine | bought passage | never | ×0.6 | 20 s |
| Scrapper | Engineering | Taris | working a freight berth | never | ×0.2 | 180 s |

Two things fall out of that rather than being authored:

- **The patron is also a liability.** If the destination's controlling faction is
  an *enemy* of your patron (`Factions.areEnemies`), the fare takes a ×1.5
  surcharge — nobody wants an Acolyte aboard on a Republic world. No hostility
  list is written down; it is read off the faction graph.
- **The asymmetry is the balance.** The Acolyte has the smallest free network
  (2 of 9 worlds) and the steepest charter, because the Force tree is the
  strongest. The Scrapper travels for almost nothing and waits three minutes.

**Every origin keeps a paid route to every world.** A weakness that can strand
you is not a weakness, it is a dead end — no story beat may become unreachable
because of a background choice.

Implementation notes worth remembering:
- `Origins.passageFor` is **pure and shared**, so the price the map quotes and
  the price the server charges cannot drift. Same reasoning as `Shops.VENDOR_RANGE`.
- The cooldown is `profile.lastTravelAt` (an `os.time`), not server memory, so
  rejoining is not a free reset. It is stamped *before* the jump, because
  `travelTo` respawns the character and anything after that races the
  character-added handler.
- The map lists **locked** worlds too, with the reason (`Requires level 26`,
  `Needs 4200 cr`, `No berth for 2 min`). A destination you cannot afford yet is
  content; a destination you cannot see is not.
- If the charge succeeds and the jump then fails, the credits are refunded.

**Choosable since 2026-08-16** (3b.1). `DataService.defaultProfile` still assigns
`Origins.DEFAULT` and `migrate` still repairs an origin that was renamed away,
but that is now a fallback rather than the only path: `originChosen` is false on
a new profile and `CreationController` asks. Until then every character
travelled on Scoundrel terms — the differences were built, tested and invisible.

Shipped **before** flyable ships. Travel alone unlocks eight planets of existing
content; flight is a separate, much larger problem.

### 2b. Ship classes — **speeders done 2026-08-17**
`Config/Ships.luau`, same shape as `Weapons.luau` — stats as data, geometry
procedural via `Shared/Rig/ShipModel.luau` mirroring `WeaponModel`.

| Class | Example | Role | Crew |
|---|---|---|---|
| Speeder | Landspeeder, speeder bike | Ground traversal, no space | 1-2 |
| Starfighter | X-wing, TIE, N-1 | Fast, armed, no cargo | 1 |
| Light freighter | YT-1300 type | Cargo, walkable interior | 1-4 |
| Shuttle | Lambda type | Passenger, faction flavour | 1-6 |
| Capital | Corvette+ | Set dressing / boss encounters | — |

Stats worth modelling: speed, handling, hull, shields, cargo, fuel, hardpoints,
price, level gate — so ships slot into the existing shop and progression systems
rather than needing new ones.

Speeders are the cheapest real win: ground-only, no space scene required, and
they fix the "3 minutes to walk across the map" problem immediately.

**Done — the speeder half.** Five of them (`HoverSled` 900cr/L1 through
`AssaultSpeeder` 26,000cr/L28), stocked by the two existing vendors, gated by
the existing level checks, listed on a third **VEHICLES** tab in the inventory
panel. **V** calls one in; **V** again puts it away.

Decisions worth not relitigating:
- **A speeder is not an `ItemStack`.** It lives in `profile.unlockedShips` with
  `profile.equipped.ship` naming the selected one. Putting it in the bag would
  have meant teaching every drop, sell, discard, affix and bag-cap path about an
  item all of them must refuse. (This also found `defaultProfile` shipping
  `unlockedShips = { "Skiff" }` — an id no config ever defined, invisible for as
  long as nothing read the field.)
- **The driver's client drives the constraints.** With network ownership on the
  client, a server Heartbeat loop learns `Throttle` late *and* replicates its
  writes late — roughly double the input lag. The concession is that a modified
  client can exceed the config's top speed; it buys nothing, since there is no
  vehicle combat, no race and no reward for arriving early, and ownership, price,
  level gate and seat are all still decided server-side.
- **Velocity, not force.** `PlanetDef.gravity` differs across the nine worlds, so
  a force-driven hover would need retuning nine times. `LinearVelocity` makes
  handling exactly what the config says everywhere.
- **An idle speeder is anchored.** A hover needs someone simulating it; anchoring
  when the seat empties is also what a repulsorlift does when you get off it, and
  costs the server nothing.
- **Sold from the same counter, not a speeder yard.** A yard would exist on
  whichever planets got one, and the point of a speeder is that the walk you are
  sick of is the one you are standing in right now.

### 2c. Flight and interiors — **DONE 2026-08-18**
- ~~Flight controller, hangar spawn/despawn, landing pads at existing Hangar POIs~~
- ~~Ship interior customization (your note)~~
- ~~NPC ships flying over Coruscant (your note)~~

**Done — the flight half.** Three starships (`SkipjackCourier` 30,000cr/L16,
`LonghaulFreighter` 85,000cr/L26, `DaggerInterceptor` 175,000cr/L36) sold by the
same General Goods counter, tiers 6-8 continuing the speeders' 1-5. They fly on
the *same* loop: `ShipDef.class` is the only thing anything branches on, and
`VehicleController.onStep` gained one angle and one substitution.

**The real payload was not the flying.** Grepping `FuelCostMult` found the whole
**Piloting tree marked `unimplemented`** — four nodes, none of whose stats
appeared in `LIVE_STATS`. The Scoundrel is built on Piloting and Piloting is the
*default* origin, so a character could be created, played to level 50, and every
skill on their own sheet would still have been an advertisement. Three of the
four now read (`ShipSpeedMult`, `ShipTurnMult`, `FuelCostMult`); the two that
still don't (`ShieldHarmonics`, `FieldRepair`) say why in one honest sentence
each — *nothing shoots at a ship yet, nothing damages one*. §3b.1's "revisit with
Phase 2b" note is now discharged.

Decisions worth not relitigating:
- **The roadmap's "Hangar POIs" do not exist.** There is no `kind = "Hangar"`
  anywhere; there are five `kind = "Spaceport"` POIs on five of the nine worlds,
  and `buildSpaceport` has been drawing landing discs at them all along. A
  starship launches from one of those and nowhere else — `CollectionService`
  tagged with `Ships.PAD_TAG` at build time, so the tag survives
  `buildLandmark`'s later `PivotTo` in a way a stored coordinate would not.
  **The pad is claimed, not just found**: two brothers in one room calling a hull
  down onto the same disc is not a corner case, it is Saturday.
- **Speed and turn apply to speeders too.** A rank bought at level 1 does
  something at level 1, rather than waiting fifteen levels for a hull.
- **Two keys for pitch, not the camera.** Roblox's default camera only elevates
  while the right mouse button is held, so a player who does not know that flies
  dead level forever and never finds the ceiling. This project has shipped that
  exact bug twice under the name *"finished but unreachable is not finished"*.
  Space climbs, C dives, and pitch **decays to level** when neither is held — a
  held angle in a place with no visible horizon is a trap. Dive was LeftControl
  until 2026-08-30; see §5.6.
- **Above `Ships.CEILING` the star map opens itself**, once, on the way up. One
  raycast does both jobs: a hit closer than the hull's ride height is a floor to
  push off, and no hit at all *is* what leaving a planet looks like from the
  cockpit.
- **Fuel is a price, not a tank.** Flying yourself swaps
  `Planets.fastTravelCost` for `Planets.fuelCost` (dead code since long before
  anything could fly), Haggler for Navigator, the origin's broker cut for the
  hull's `fuelMult`, and the berth cooldown for nothing at all. A gauge that can
  run dry between worlds is a stranding, and `Origins.luau` already settled that
  argument: *"a weakness that can strand you is not a weakness, it is a dead
  end."* The cheap hull is thirsty (1.6×) and the expensive one is not (0.55×),
  which is the one difference between them that lasts a whole campaign.
- **The vehicles tab is not the speeders tab.** `kind` on a shop row went
  `"Speeder"` → `"Vehicle"` and `ShopDef.speeders` → `ShopDef.ships`, because a
  Czerka Dagger filed under SPEEDERS is a small lie and small lies in a UI are
  how this project's last two playtest reports started.

**Done — the interiors half (2026-08-18).** A hull was the most expensive thing
in the game and the only one you never got to be *inside* of.
`Config/Furnishings.luau` (3 cabins, 4 slots, 12 pieces), `World/CabinBuilder.luau`
and `InteriorService` (priority 37); **H** boards and leaves, and the CABIN tab of
the inventory panel (**B**) fits what you own.

- **Cosmetic, and said so in the header.** No furnishing grants a stat, a heal or
  a flag. The project's rule that a stat in `LIVE_STATS` needs a reader runs the
  other way too: a bunk that quietly restores health is a bunk you have to sleep
  in before every mission, which turns a room you *chose* into a chore you
  *perform*. Wanting the Dejarik table is the whole mechanic.
- **One item per slot, replaced not accumulated.** Thirty ornaments all placed at
  once is a warehouse, and a warehouse is not a decision about who you are.
- **Slots are fractions of the room, not coordinates.** `SlotDef.at` is in
  room-halves and `Furnishings.anchorFor` scales it, so three cabin sizes share
  one catalogue and a bigger hull spreads the same furniture wider. Absolute
  coordinates would have meant a position per cabin per piece, and a Dejarik
  table standing in the wall of the one hull nobody tested.
- **`anchorFor` lives in config because the builder and the validator must not
  disagree** — the same argument that put `TOWER_GRID` in `Planets.luau`.
  `Furnishings.validate` transforms each piece's rotated AABB through that anchor
  and checks it against the *smallest* cabin. Written the naive way first
  (compare a bare footprint to the room) it was wrong in both directions: it
  failed pieces that fit and passed **two slot facings that pointed furniture
  through the hull** — `KraytSkull` reached X = 8.34 in a room whose wall is at
  7.50. There is no way to run Luau offline, so that was found by hand-computing
  all twelve.
- **Boarding is a teleport, gated on the hull.** You must have a starship
  summoned and be standing within 30 studs of it. There is no door — a hull is a
  solid shell — and the gate is what makes the room read as *this ship's* room
  rather than a menu. It also gives the five spaceports a second reason to exist.
- **The cabin is built at +6,000 studs, not underground.**
  `Workspace.FallenPartsDestroyHeight` deletes anything that falls past it; a room
  below the map is a room that is sometimes not there. 6,000 clears every flight
  ceiling (Coruscant's is 1,400).
- **A sealed room has no sun and nothing outside**, so `CabinBuilder` carries two
  ceiling lamps and a 26-speck seeded starfield behind a split forward bulkhead.
  A black pane reads as a bug, not as space.
- **A fitted furnishing's button says REMOVE.** The server could always clear a
  slot; without that state nothing in the UI could ask it to, which is this
  project's twice-shipped *"finished but unreachable"* failure.

**Done — the sky over Coruscant (2026-08-18).** `PlanetDef.airTraffic` and
`SkyTrafficController`; eight of nine worlds declare nothing, because the Korriban
wastes do not have rush hour.

- **Entirely client-side, and still the same sky for both brothers.** No traffic
  hull can be shot, boarded, landed on or collided with, so replicating 26 moving
  models to every player is a network bill for a decoration. Lanes are seeded off
  the planet id and flown off `Workspace:GetServerTimeNow()` — same seed, same
  clock, same sky, without a single remote. Two different skies in one room is
  precisely the class of thing they notice and then argue about.
- **A hull's position is a function, not a simulation.** Given the time alone,
  `place` says where hull *n* is: no spawning, no despawning, no per-ship state.
  Lane wrap is a teleport, and it happens 1,800 studs out — past the outermost
  tower at 1,320, in air the atmosphere has already turned to haze.
- **Lanes are pinned to the planet, not the camera.** Following the player costs a
  visible sideways jump of a whole grid square every time they cross a tower row,
  and buys nothing: the vertical city is only 2,640 studs across. The lanes sit
  half a `TOWER_GRID` square between tower rows at half a `SKYLANE_STEP` between
  platform decks — dead centre of a canyon, passing *under* the pad you are
  standing on. Both numbers are read from config; a private copy here is a
  hundred airbuses flying through the Senate.

---

### 2d. Flying between worlds — **part 1 DONE 2026-08-29**

*"ok I have a ship, how do I fly it into space? and to other planets? Logan
wants the game to be more open world."*

**Grepped first — the ninth time — and again most of it was already built.** The
ships already fly in full 3D with pitch (2c). Space already exists as a place
(`5b20b8b`: cloud deck, black starred sky, altimeter, re-entry hysteresis). And
the load-bearing one: **all nine worlds have been in one `Workspace` at real
addresses on a 12,000-stud grid since the first planet was generated**
(`Planets.originFor`). Tatooine and its neighbour were never two scenes to be
swapped. They were two places you could have driven between, if anything had let
you.

So the gap was small, specific, and not flight:

1. **`profile.currentPlanet` could only change by respawning.** `travelTo` called
   `LoadCharacterAsync`, and that respawn *was* the teleport. It also fires
   `CharacterRemoving`, which dismisses your ship — so the reward for flying
   twelve thousand studs would have been arriving on foot, over a world the game
   still thought you had left.
2. **Being between worlds was an error.** `VehicleController` called it *strayed*,
   toasted *"Beyond the world's edge"* and threw the star map over the view.
3. **Nothing closed the gap at a playable speed** — 50 seconds of holding W. That
   is Part 2's job (the hyperdrive), not this one's.

**`Orbit.luau` gained the geography of the void.** `SYSTEM_RADIUS = 3600` is how
far a world's authority reaches: comfortably outside `Planets.worldRadius`
(~1,700), so a wide circuit of your own world cannot flip you in and out, and
comfortably inside half the grid spacing (6,000), so **no two systems ever touch
and there is ~4,800 studs of real void between neighbours**. `systemAt` returns
which world you are in the system of, or nil; `nearestSystem` never returns nil,
because something on screen always has to be able to name a place. Both compose
at require time off `Planets.ids()`, and `validate` now warns at boot if a tenth
planet or a changed `WORLD_SPACING` would make two systems overlap.

**`PlayerService.setPlanet` — arriving without a respawn.** The smaller half of
`travelTo`, which now delegates to it: write `currentPlanet`, `ensure` the world,
re-apply that planet's gravity, **move nothing**. Not repositioning is the entire
point — you are already there. All fourteen readers of `currentPlanet` follow on
their own, because every one of them listens on `ClientState.changed` or polls.

**The server decides which system you are in**, on a 1 Hz sweep in
`VehicleService` over piloted starships. Server-side because the client owns the
hull's physics and must not be trusted to say which world it has reached — and it
costs no new remote either way, since position replicates back regardless of
network ownership. Nine distance checks per ship per second. **Deep space keeps
your last world rather than clearing it**: there is nothing sensible for a sky, a
mission board or a spawn point to be when the answer is "nowhere".

**Deep space stopped being an error.** The old toast was honest while there was
nowhere to go; now it would be the game arguing with a player about the middle of
the journey they set out on. The HUD gains a `setBearing` line that names the
nearest world and its distance where the altimeter has nothing to measure. **G
still opens the star map anywhere**, which is the escape hatch that means nobody
out there is stranded. The genuinely wrong case survives untouched: off the rim
of the plate, low, still inside a system — no ground under you and not high
enough to be in orbit, which is a player who rode off a cliff.

**You cannot step out into vacuum.** Leaving the driver's seat above the ceiling
or outside any system, and not within `PAD_RANGE` of a pad, re-seats you with a
reason. Deferred by a quarter second, because leaving a `VehicleSeat` is a jump
and a character re-seated in the same frame leaps straight back out on the input
still being held.

### 2e. The hyperdrive — part 2 DONE 2026-08-29

Part 1 made a crossing possible and left it at fifty seconds of holding W.
`CAMPAIGN.md:45` already committed to the shape — *"Hyperspace is slow and mapped
— travel between planets is a journey with a cost"* — and the whole front end for
it was already built.

**Setting a course reuses the entire galaxy panel.** `GalaxyMapController` (**G**)
has always listed every world with its fare, its level gate and its lock reason,
and `TravelService.galaxyFor` has always priced a pilot's trip as *fuel* rather
than passage. The only thing that changed is the button: the payload gained
`canFly`, and with a hull under you it reads **SET COURSE** and fires
`Net.Event.SetCourse` instead of `TravelTo`.

**`TravelService.setCourse` takes the fare and builds the world.** Same gates as
`travelTo` — exists, not current, level with `LEVEL_GRACE` — plus being at the
controls of a starship, whose refusal is `starshipHint`'s existing ladder rather
than a fifth way of saying no. Then it calls **`WorldService.ensure` immediately**.
`PlanetBuilder.build` is fully synchronous — not one `task.wait` in 6,000 lines —
so a world costs one visible hitch, and this puts that hitch under the button
press instead of on arrival at fifteen hundred studs a second.

**No server-side course state.** The server takes the fuel, builds the world and
fires `CourseSet`; the client holds the course. That concedes nothing, because
arrival is still settled by Part 1's server-side position sweep, which has never
taken the client's word for anything.

**One number reconciles two distance systems.** `Planets.fuelCost` prices off the
**authored** `PlanetDef.coords` — the geometry the player is looking at on the
map. The ship flies the **physical** grid. They disagree, so each does the job it
is good at: the *path* is real and physical (`Orbit.gridDistance`), and the *fare*
and the *duration* both come from the same map (`Orbit.jumpDurationFor`, clamped
8–20s). A world the map says is far costs more **and** takes longer, which is the
only consistency a player can actually perceive. `MAX_JUMP_SPEED = 3000` caps the
worst case, and `validate` asserts a jump cannot outrun its own `ARRIVAL_RADIUS`
in a single frame.

**The jump is a real crossing, not a teleport.** Client-side in
`VehicleController`, which already owns the hull's physics. Hold **F** in orbit
with a course set; the heading **locks** onto `Orbit.arrivalPointFor` — you cannot
steer, which is what makes a lane a lane and what makes arrival deterministic —
and the speed ramps through the same `LinearVelocity` drive. It drops out inside
`ARRIVAL_RADIUS` (2,400), still flying, nose down. Because `SYSTEM_RADIUS` is
3,600, **the world has already become yours a beat before the streaks stop**: its
sky, its weather, its crowd and its mission board are in place by the time there
is anything to look at. A fresh press aborts at any moment, which is only safe
because Part 1 made deep space legal.

**Held, not tapped**, because engaging costs fuel and takes the controls away for
twenty seconds — the two things a mis-keyed press must never do. Aborting is a
press, because a panic button you have to hold is not one.

**`StarlineController` is the reference frame.** The jump is honest — the hull
really covers twelve thousand studs of the same Workspace — and honest looks like
*nothing*, because there is nothing out there to move past. Speed you cannot see
is a twenty-second pause with the controls taken away. 220 neon lines in a
90-stud box stapled to `Workspace.CurrentCamera`, wrapping rather than spawning,
so a long crossing cannot cost more than a short one. Client-only geometry, which
this project trusts **for shapes and not for people** (the 2026-08-29 ghost
crowd) — a streak at distance genuinely is a lit line.

**And it is reachable**, which is the failure this project has shipped four times.
The HUD's bearing line is one priority ladder — HYPERSPACE, then COURSE, then
DEEP SPACE — so the destination and the distance left are on screen from the
moment the fare is paid. **F** is in the legend. Pressing it with no course names
**G** rather than reporting "no course set", which is a fact the player already
had.

**It was **H** for about an hour**, chosen by reading the legend for a free
letter — and the legend is built from `Panels.ALL` plus five hand-written rows,
so the one binding not yet in it was invisible to exactly the check that would
have caught it. **H** had been the cabin door since the ship got an inside. That
is `Shared/Core/Bindings.luau`: every declared key in one list, counted at boot
by `WorldService`, naming both *files* rather than both letters. It does not own
the keys and is not a binding system — `Ships`, `Furnishings` and `Panels` still
declare their own next to the behaviour they belong to.

**Still to come:** the player's own species and proportions (Part 3), and an
interior that is not a box (Part 4).

### 2f. What the first flight actually found — 2026-08-29

Five things, from one session with Logan in a cockpit. None of them was the
hyperdrive.

**Space bar ejected the pilot.** The climb key and the eject key were the same
key, and had been since the ship could fly: a seated `Humanoid` that receives a
jump input sets `Humanoid.Jump`, which a `VehicleSeat` reads as *leave the seat*.
So the one control that gets a starship to orbit instead threw you out of it, at
altitude. Fixed by sinking `Enum.PlayerActions.CharacterJump` through
`ContextActionService:BindActionAtPriority` while at a starship's controls —
deliberately keeping Space rather than rebinding, because it is the key every
player already reaches for. It is released unconditionally and *before* the early
return in `release()`: a jump left sunk is a player who can walk and never jump
again, which is a far worse bug than the one it fixes.

**Bodies fell through the map on death.** Reported as *"you broke the ragdoll"*,
and there is no ragdoll code in the repo — so, asked rather than guessed. The
real fault was `PlayerService.applyGravity`'s `VectorForce`, which holds a
character up against a heavier world and **survived death**. Roblox breaks
character joints on death, so `HumanoidRootPart.AssemblyMass` collapses from
whole-body to fragment while the force stays sized for the whole body; on the
worlds where gravity is *above* Earth normal (Korriban 210, Coruscant 202, Hoth
198) that force points **down**, and for up to a second it was shoving a loose
torso through the floor. The force is now dropped on `Humanoid.Died` and scaled
off live mass.

**Space was too dark.** Ambient `(7,8,12)` → `(26,29,40)`, planetshine 0.14 →
0.3, exposure -0.15 → 0. The starfield was already there; what was missing was
anything to see the ship *by*.

**The legend had drifted to mid-screen.** `belowTopbar(clearChat = true)`
measured Roblox's chat window and followed it down without limit, so a tall chat
put the reference card in the middle of the play area. Clamped at
`MAX_CHAT_DROP = 96`.

**And eleven hot keys.** *"we should be able to minimize mostly and then maximize
it. also if it makes sense to have less hot keys that's ok."* Three cuts, in
`HudController` and the new `MenuController`:

- **A chevron** collapses the legend to a single chip. Remembered for the session,
  never saved — a player who hides it on Tuesday and has forgotten the keys by
  Friday is worse off than one who hides it twice.
- **The flight rows are contextual.** Climb, dive, jump and the cabin door are
  false of every player on foot, and false in a way that reads as broken: a boy in
  Anchorhead pressing SPACE because the legend says CLIMB gets a jump and
  concludes the legend lies. They appear only at a starship's controls.
- **`TAB` opens all five panels.** B, M, J, K and G each earned their place in the
  legend in 2026-08-17, when the complaint was that finished panels had no
  advertised way in. They fixed that and created the next problem: five *unrelated*
  letters to memorise before the interface is usable, with no rule connecting J to
  the journal that also connects K to the skill tree. `MenuController` is a sixth
  `ScreenGui` at `DisplayOrder = 11` — a strip of tabs where a tab bar goes, one
  per keyed panel, calling the same `setOpen` the letters call. **The panels do not
  know it exists**; it reads their state on a heartbeat rather than being told, so
  it cannot fall out of sync with a panel opened by a letter, by a vendor, or by
  the star map raising itself. The letters still work and are printed *on the
  tabs*, which is how a player now learns them: next to the word they open, at the
  moment they are looking at it.

Eleven entries down to six on foot, five of which are true of a character who has
unlocked nothing. **`RMB` / `AIM` is the sixth** — `AimController` has bound the
right button to a shoulder camera and a spread reticle since 2026-08-17, in answer
to a complaint about shooting, and then never said so. Sixth instance of *finished
but unreachable is not finished*.

**Still open from the same report:** blasters on ships, AI starships to shoot at,
and sound effects — the game has never played a single one. Audio is the one place
the no-asset-id rule is relaxed, geometry stays procedural, and the ids will live
in one `Config/Sounds.luau`.

### 2g. The hole the climb fix left — 2026-08-29

*"we can't figure out how to exit a ship."* Reported the same evening, and 2f's
fault. Sinking `CharacterJump` stopped Space throwing a pilot out at altitude and
in the same stroke removed **the only way out of a starship at all** — getting out
of a Roblox seat has always *been* the jump. The fix took a stock behaviour away
and put nothing in its place, and because that behaviour was stock it was written
down nowhere, so nothing pointed at the gap until somebody was sitting in a landed
freighter unable to leave it. This project's own recurring failure, inverted:
usually a finished thing has no way in; this time a working thing lost its way out.

`Ships.EXIT_KEY = E`, registered in `Bindings.luau` so it can never quietly collide
with another key, and shown in the legend's flight group. **E** because it is what
every game means by *get out*, and because it is already the key the boarding
prompt uses to get *in* — prompts are suppressed while seated, so there is no
clash. Bound in speeders too, even though Space still works there: one key that
always means the same thing beats two keys that mean it in different vehicles.

It writes `Humanoid.Sit = false` rather than touching the seat, because that is
exactly what the stock jump did, so it arrives at the server through the same door
— `VehicleService` still refuses a dismount in orbit and re-seats you, and an exit
that went around that would be a way to step out into vacuum.

**And the sink is now un-leakable.** It was released on every exit path anyone
could think of, which is the reasoning that produces this class of bug. It now
follows *"is this player at a starship's controls right now"*, asked from scratch
every frame in `onStep`, so it can be wrong for one frame and no longer.

**`whosyourdaddy` was also reported as doing nothing, and was not fixed**, because
three quite different faults look identical from the chat box: the message never
reaching the server (Roblox moderation can drop one outright, and *"daddy"* is
exactly the kind of word that gets dropped), `mayCheat` refusing it, or the code
running with no visible effect. The last fix for something like this guessed.
`DevService` now prints which of the three happened, and the next Studio run
decides it.

---

## Phase 3 — Make the places real

**Current state: the worlds are procedural, not authored.** Every planet is the
same generator with different colours.

- Each planet is a disc of Roblox terrain, sized off its own outermost district
  — 1,502 studs on Tatooine, 2,022 on Korriban (see §3.3; it was a fixed
  3,000-stud part slab until 2026-08-16).
- The town is a radial grid of 130-stud blocks out to a **520-stud radius** —
  about 65 seconds across. That is ~12% of the map area.
- Everything beyond radius 610 is open ground with scattered boulders and,
  outside the flat pad, hills.

**Landmarks have shapes now, but not authored ones.** Until 2026-08-14 every
point of interest was an *invisible* 40x20x40 marker: the spaceport, the cantina,
the Hutt's estate and the Sandcrawler Wreck existed only as mission `Reach`
targets, so the waypoint sent you into empty desert and the objective ticked
anyway. `PlanetBuilder`'s Landmarks section now builds eight kinds — Sandcrawler,
Ruin, Spaceport, Cantina, Base, Outpost, Market, Temple — chosen by
`PointOfInterest.landmark or .kind`, each with a nameplate and a declared radius.
That radius is the contract for how big a place is: reach is measured from the
marker's edge and quest items scatter in a ring outside it.

They are still *generic* buildings, and they are still placed on a compass fan
by index within the POI's zone. The Dry Well is the same drum as any other
cantina, and the moisture farm is a few hundred studs from it rather than a long
ride out into the Wastes.

**Tatooine's place names were re-dated 2026-08-14.** They were Mos Eisley,
Chalmun's Cantina, Jabba's Palace and the Lars Homestead — all Original Trilogy,
all roughly 3,600 years after this game is set. They are now Anchorhead, the Dry
Well, Nagurra's Estate and the Vantel Moisture Farm. The planet itself was never
in question: Tatooine is a Star Map world in KOTOR and a full planet in SWTOR.

**Factions and archetypes followed on 2026-08-15.** `Rebellion` became
`Republic` and the old `Republic` became `Jedi` — a *crossover*, so it had to
land as one commit or every stale reference would silently point at the wrong
faction instead of erroring. Thirteen archetypes were renamed with it
(`Stormtrooper` → `ImperialTrooper`, `RebelTrooper` → `RepublicTrooper`,
`RoyalGuard` → `SithHonourGuard`, `BattleDroid` → `WarDroid`, and so on), plus
the costume keys, dialogue trees, outfit display names and weapon blurbs that
name them.

**The planets landed 2026-08-15, and this closes the era migration.** Naboo →
**Tython**, Kamino → **Taris**, Mustafar → **Korriban**, Endor → **Ord Mantell**,
plus **Dromund Kaas** added as the ninth — it was already `Factions.Empire`'s
declared home world and simply did not exist. Coruscant flipped from Imperial to
**Republic-held**, which is the treaty position in 3,640 BBY and a much better
setting: Imperial diplomats walking the capital they burned. Five missions were
re-pointed with it (`NabQuietOrder` → `TytQuietOrder`, `KamWhatTheyKept` →
`TarWhatTheyKept`, `MusTheFortress` → `KorTheTomb`, and so on).

Two bugs fell out of doing it, both the same shape as the POI bug in §1.2: a
mission naming something that no longer exists. Rewriting Coruscant's Republic
spawn table deleted the Imperial troopers that `CorTheLongFall` counts kills of,
and Nar Shaddaa never had any for `NarOpenContract`. Neither would have errored
— they would have been objectives that sat at 0/10 forever. **A giver or a Kill
target that does not spawn on that mission's planet is unreachable**, and that
is now checked by hand at every config change until it is checked by code.

`Factions.validate(planetExists)` was added at the same time and runs from
`WorldService.init`, so a faction capital that does not exist warns at boot
rather than becoming a fast-travel destination that goes nowhere.

**What is still Original Trilogy:** the weapon model numbers (E11, DL-44,
DC-15A). `Palette` colour constants still say `StormtrooperWhite` and
`NabooGrass`; those are internal names for shades of grey and green and are the
lowest-value thing on this list.

### 3.1 The layout system — **[done 2026-08-17; all eight worlds drawn]**
The mechanism, designed in [PLANETS.md](PLANETS.md) §2. Four pieces:

- **Prefabs.** Promote `PlanetBuilder`'s `LANDMARKS` table to
  `src/server/World/Prefabs/`, one module per family, grown from 8 entries to
  ~40. A prefab still declares its `radius` before it builds — that contract is
  already load-bearing for reach and pickups.
- **An ASCII tile map per planet**, one glyph per 40-stud cell with a per-planet
  legend, held in `Config/Planets.luau`. A 32x32 grid covers the whole walkable
  town. You can see the map in the diff, and the boys can move a tent without
  reading Luau.
- **Districts as rectangles** in cell coordinates, each with a `band` giving the
  level range of NPCs that spawn there. This is also Phase 4's "per-zone level
  bands" item, and it is the permanent fix for the `Behavior.Aggressive` hazard:
  a declared band can be validated against the archetypes placed in it.
- **Validation.** Unknown glyph, missing prefab, overlapping radii, district
  outside the grid, archetype outside its band. Every one of those currently
  fails silently.

Wilderness stays generated. A hand-authored 3000x3000 map is not worth it, and
scattered boulders are fine out there — but it needs **shape**: see playtest N3
(mountains, canyons, rivers) and N4 (paths). A flat plane with boulders reads as
nothing at all once you have seen it on three worlds.

Two additions from the 2026-08-15 playtest, both belonging here:

- **Architecture is not terrain.** — **[done]** A planet declares its building
  family separately from its ground type (B2), so Korriban is no longer Tatooine
  in a red filter. Nine `ARCHITECTURE` entries, each with its own `shape`
  function. What remains here is hand-authored *prefabs* — named, unique
  buildings — on top of the generated ones.
- **Prefabs may declare an interior** (N5), entered by a door trigger and built
  as its own space. Zero landmarks are enterable today and this is the single
  biggest jump in how finished the world feels.

#### Built 2026-08-17
**Additive, and that was the design decision.** A planet with a `layout` is
built from its picture; a planet without keeps the radial generator it has
always had. Both return the same thing — the list of open ground — so
landmarks, patrol rings, POI markers and spawn points cannot tell which they
were handed. Eight worlds are untouched while the mechanism proves out on one.

- **`Planets.LayoutDef`** = `cell` (studs per glyph), `legend` (glyph → prefab
  id), `grid` (rows, north at the top, west at the left). `ZoneDef.cells` is a
  `CellRect` in **column-then-row** order, matching how the grid reads on the
  page. `distance` is unchanged and still sets the level band — `cells` says
  only *where*, which a bearing rolled from the seed could never say.
- **Touching cells that share a glyph merge into one rectangle** (greedy right,
  then down). `WWWW` is one wall, not four posts; `hh` over two rows is a house
  with an upstairs. The only rule an author has to learn beyond "read it as a
  map" is that two houses need a gap between them.
- **A prefab is a footprint and a storey count, not geometry.** `PREFABS` (10
  entries: House/Hall/Shop/Tower/Wall/Gate/Road/Plaza/Yard/Lamp) hands the
  footprint to the planet's own `style.shape`, so the grid dropped on Hoth would
  come up IceBunker. `floorScale` is a **multiplier** on the style's range, not
  a count: Adobe is 1-2 floors and Spire is 6-14, so "a tower is five storeys"
  would be a tower on Tatooine and a bungalow on Coruscant. Only Wall, Gate and
  Lamp draw their own parts.
- **`Planets.validate(prefabExists)`** — injected predicate, same trick as
  `Factions.validate(planetExists)`. New checks: ragged row, legend key that is
  not one character, a legend entry naming a prefab that does not exist, a
  legend entry that never appears in the grid, **a non-space glyph the legend
  does not declare** (space is the *only* way to write open ground, so a typo'd
  `H` for `h` is caught instead of silently becoming a missing building), and a
  district rectangle off the edge of the grid.
- **Anchorhead**, 26x26 at 32 studs = 832 across: walls with four gates, two
  avenues crossing at a plaza, market east, cantina quarter south-west. 65
  buildings, 79 anchors. The spaceport is deliberately *not* in the grid — at
  116 studs radius it is too big for any block, so `buildMarkers` puts it past
  the wall with a road to it, which is where a landing field belongs.
- **An authored district keeps its drawn centre even when it has a landmark.**
  Previously the crowd ringed `landmark.at`; with the spaceport pushed outside
  the wall that would have taken all thirty-two townspeople to the landing field.

**Rooms, same day.** A prefab may also declare a `room`, which builds that cell
as a `roomShell` turned to face the street rather than as a solid. Nine shops and
two halls in Anchorhead. Details and the `ontoStreet` bug it exposed are under
**N5**, because it is the interiors item finally reaching ordinary buildings.

**Deliberately deferred:** promoting `LANDMARKS` to `src/server/World/Prefabs/`.
Splitting the file means exporting seven local helpers plus 600 lines of
`ARCHITECTURE` shape functions — a large mechanical refactor with no gameplay
value at nine prefabs. `PREFABS` lives next to `LANDMARKS` until the count
justifies the move.

### 3.2 The eight worlds — **[done 2026-08-18]**
Contents specified per planet in [PLANETS.md](PLANETS.md) §3. Build order was
depth-first: **Tatooine completely** as the vertical slice, then extract the
layout system from what that taught, then Korriban, then the rest. That is what
happened, and **every walkable world now has an authored grid with banded
districts** (see §N5 for the eight of them and what each one was drawn around).

**The other half — named landmarks — 2026-08-17.** The *undrawn* points of
interest, the ones that stand alone outside a town grid, were each getting one
of eight generic builders picked by `kind`. The state that argues the case
better than any principle: **the Tomb of Tulak Hord was a crashed starship.**
`Ruin` means "something that used to fly, nose-down in the ground", it was the
closest of the eight, and so a world whose entire claim on the player is that it
is a valley of tombs had a downed freighter in it under a sign saying TOMB. The
Jedi Temple *Ruin* was Tython's intact ziggurat. The farm the config calls
"forty vaporators and one family" was a shed with one vaporator.

Seven new builders, and **no new machinery**: `landmarkFor` has read
`poi.landmark or poi.kind` since the sandcrawler shipped, so a named place is a
builder plus one config line, and a place that has not earned one still falls
back to its kind.

| `landmark` | where | what it draws |
|---|---|---|
| `Tomb` | Korriban, Tomb of Tulak Hord | cut cliff facade, battered jambs, a **filled** doorway, braziers |
| `TempleRuin` | Coruscant, the Temple Ruin | colonnade with most columns down, spire lying across the terrace |
| `MoistureFarm` | Tatooine, Vantel farm | two domes in a walled yard, ringed by two rings of condensers |
| `Boneyard` | Tatooine, the Boneyard | a broken-backed hauler, snapped vaporator masts, stripped chassis |
| `LeaningTowers` | Taris, the Sinking Sector | four towers leaning **twenty degrees** about their feet, catwalks between |
| `Forge` | Tython, Forge Ridge | a standing ring with a gap, an anvil, live coals |
| `Skylane` | Coruscant ×3 | a control deck and two rows of lit pylons receding into the fog |

The scoping test, which is what keeps this from becoming one builder per POI:
**does the description already sitting in the config describe something the
generic builder cannot draw?** Applied honestly it yields seven, not thirty.
Nagurra's Estate says "a compound behind a wall", which is exactly what `Base`
builds, so it keeps `Base`. Where the description gives a number — "twenty
degrees" — the number is honoured exactly. A `landmark` naming no builder is now
a boot warning (`PlanetBuilder.landmarkExists`, injected into
`Planets.validate`), because falling back to an outpost is the right answer for
an unrecognised *kind* and the wrong one for a name written on purpose.

**The third half — what a shop looks like on each world — 2026-08-18.** The item
left open above, closed. The exact charge was that "Anchorhead's cantina and Kaas
City's antechambers are still the same box in different colours", and it was
literally true: a building you can walk *into* cannot be built by `style.shape`
(the nine shape functions draw solid silhouettes and there is no hollowing a
solid), so every one of them went through `roomShell`, and `roomShell` is a box.

The measurement first, because the size of it is the argument. Counting glyphs
across the eight authored grids: **`Hall` 231 + `Shop` 125 = 356 cells** against
`House` 450 and `Tower` 164 — and the houses and towers were the ones already
routing through each planet's own architecture. Per world the ratio of shared box
to native building is **Hoth 36:8**, Tython 54:30, Ord Mantell 44:24, Dromund
Kaas 64:56. On Hoth the box outnumbers the planet's own houses four to one, so
"every building looks the same" was not a criticism of that town so much as a
description of it. The buildings with a door are also, by definition, the ones
you walk right up to.

So `Style` gained a second required function beside `shape`:

```luau
dress: (Instance, CFrame, Vector3, Color3, Style, Random) -> ()
```

`buildRoom` now calls `roomShell` and then `style.dress`. The shell stays one
function — the door, the sign, the interior fittings and the standing marker are
all measured off it — and only what a passer-by sees is per world. **There is
deliberately no generic fallback**: all nine architectures declare `dress`, and
`--!strict` makes a tenth answer "what does a shop look like here" rather than
inherit a default. A silent default is exactly how the nine came to share one box.

| architecture | world | what a room wears |
|---|---|---|
| `Adobe` | Tatooine | barrel vault along the door axis, rounded corner piers, sun slits, a condenser |
| `Ziggurat` | Korriban | plinth, two receding stepped courses, two flanking obelisks with braziers |
| `Ruin` | Taris | a **broken** cornice, the sheared stump of the floor above, bare columns past it, a fallen slab |
| `NeonStack` | Nar Shaddaa | a second storey shoved off the front, neon strip and board, roof tanks, plumbing outside |
| `Spire` | Coruscant | plinth, glazing bands, mast, beacon |
| `Frontier` | Ord Mantell | corrugated pitched roof, eaves, stovepipe, a porch you stand on |
| `JediStone` | Tython | two stylobate courses, a colonnade proud of both walls, an overhanging lid |
| `IceBunker` | Hoth | snow banked over three sides and the roof; **the door is the only thing above the drift** |
| `ImperialGothic` | Dromund Kaas | leaning corner buttresses with pinnacles, two cornices, a pointed crown |

Three notes worth keeping:

- **The budget goes on the roofline first.** A box's silhouette *is* its roof
  edge, that is what reads from across a street, and it is the one part no amount
  of colour disguises. Hoth is the only one that changes the mass rather than
  trimming it, because a bunker is defined by being *under* something.
- **The plinth is each dressing's own business** rather than a shared line above
  them, because two of the nine correctly refuse one: Ord Mantell builds above
  its wet season on stilts and Hoth builds under the snow.
- **`Spire` is written but not currently reachable.** Coruscant is the one world
  with no ground layout — `buildVerticalCity` draws it — so nothing calls
  `buildRoom` there. `spireShape` has always been in the identical position. A
  `Style` with a hole in it for one planet is worse than a function waiting for a
  district, so it is written, and this note exists instead of a silence.

**The recurring hazard, caught four times in one sitting: `roomShell`'s doorway is
a fixed 16 studs however small the building is.** The smallest room is a single
32-stud cell at `fill = 0.78`, about 25 studs across, leaving four and a half
studs of jamb each side — so *anything* measured inward from a front corner lands
in the opening, at that size only, on one world. Korriban's obelisks did (moved
outside the side walls), Hoth's tunnel mouth did (rebuilt as two jambs and a roof
slab, the same split `roomShell` uses for its own entrance wall), and Ord
Mantell's porch posts and supply crates did. A solid part in a doorway is a shop
the pathfinder cannot deliver a customer to. **Finished but unreachable is not
finished** — and no linter can see a doorway.

The structural win: **four planets are both an origin world and a later act** —
Korriban, Taris, Nar Shaddaa and Coruscant. That halves the worlds needing a high
finish and buys the best beat in any RPG for free, which is returning at level 40
to the district that nearly killed you at level 3.

**Travel is a hard dependency from the second planet onward** — satisfied by
Phase 2a, so this is no longer blocked.

### 3.3 "Why is everything still so blocky" — **[done 2026-08-16]**

The user's third playtest note, in his own order behind levelling and story.

**The diagnosis was not what the words suggest.** It was not lighting: Future
technology, an `Atmosphere`, bloom, colour grading, global shadows and thirty
declared materials were already in and doing their job. It was not really the
buildings either. It was that **there was not one voxel of terrain in the
game**. Every world was a flat 3,000-stud plate with a horizon made of stacked
shrinking slabs and hundred-stud plastic spheres, and no post-processing fixes
a landscape you can see the corners of.

**Part 1 — the ground is terrain.** Done.

- `PlanetDef.terrainMaterial`, required on all eight walkable worlds and
  **unique across them**, checked by `Planets.validate`.
  `Terrain:SetMaterialColor` is a property of the single shared
  `Workspace.Terrain`, not of a region — so if Tatooine and Korriban both used
  `Sand`, whichever was entered second would repaint the first one's dunes, and
  you would only ever see it after travelling twice.
- One `FillCylinder` per planet, its top face exactly at the origin's Y so
  every existing height assumption still holds. Sized per world by
  `flatRadiusFor`, not fixed: district centres run from Tatooine's 1.6 to
  Korriban's 2.6 × the 520-stud settlement radius.
- Hills, mesas and ridges built out of overlapping sunk `FillBall`s, which
  merge into continuous slopes with no seam — the thing fourteen part-spheres
  never managed. Plus low swells and, on desert and ice worlds, dunes and
  drifts in the ground's own material.
- **All relief is outside the flat pad**, and that is a correctness rule rather
  than an aesthetic one: a landmark is placed at the origin's Y, and
  `NPCService.pointOn` casts down from twelve studs above a zone marker, where
  **a ray that begins inside terrain reports no hit at all**. A dune under a
  district is a half-buried building whose whole population spawns underground.
  Parts never did this, which is why nobody had met it before.

**Part 2 — silhouette and detail.** Done. Blockiness is also "no detail at any
scale": the buildings were correct boxes with nothing on them — one colour, one
material, a right angle where the wall met the ground and another where it met
the sky. It is the small horizontals that tell the eye how big something is;
without them a twelve-storey tower and a shed are the same picture at different
zooms.

- Four shared helpers in `PlanetBuilder`: `plinth` (a footing course — one part,
  and the highest-value one here, because a wall meeting the ground at an
  unbroken right angle reads as an object sitting *on* a surface rather than a
  building standing *in* the ground), `cornice` (an overhanging lip, i.e. a
  shadow line, which is what actually reads at distance), `roofClutter` and
  `conduit`.
- Applied **inside each of the nine `shape` functions**, not as one pass over
  every building, because only the shape knows where its own roofline ended up
  and three worlds have no ground line to put a footing on: Hoth is half buried,
  Ord Mantell is on stilts, Nar Shaddaa overhangs. Those three got a supply dump,
  a porch and rail, and roof tanks instead.
- **Coruscant's 121 towers** were the largest single view in the game and the
  most literally blocky thing in it: square-section boxes with flat tops on an
  exact grid. Now off-square footprints (free — no extra parts), a setback crown,
  and a mast on 45%. The grid is deliberately still exact: landing platforms
  cantilever 45 studs past the widest face, and a pad that lands inside a
  neighbouring tower is a district spawning inside a wall, since those pads are
  the anchors `buildMarkers` uses.
- Everything that hangs off a wall is `CanCollide = false`. A ledge you can stand
  on is a ledge the boys will stand on.

### 3.4 The one weapon that was not written — **2026-08-29**

One of the boys modelled a blaster in Blender and exported it. There is no part
list that would honour that, so the rule bends here and nowhere else yet: an
optional `WeaponDef.model` naming a child of `ReplicatedStorage.Assets.Weapons`,
whose source `.rbxmx` is tracked at `assets/Weapons/`.

**The procedural pipeline stays the default and stays right.** Building weapons
out of `Instance.new` is what lets the inventory panel draw a live
`ViewportFrame` of the real item, lets a crystal recolour whatever is emitting,
and keeps the game free of asset ids owned by somebody else. The other eighteen
weapons still work that way.

**What the exception costs, precisely.** A MeshPart's `.rbxmx` does not contain
geometry — it contains an `rbxassetid://` per mesh, twenty-six of them in this
file, all pointing at uploads on whichever account did the export. The weapon
renders only while those uploads exist and are readable by whoever is running the
place. That is a dependency nothing else in the game has, and it is why `NN14`
**also declares a full `parts` list**: `WeaponModel.build` draws the part list
when the import cannot be found, so the failure mode is an ordinary scavenged
pistol rather than an empty hand. If the meshes ever stop loading, the `model`
line comes out and the weapon is a part list again — no other file changes.

`ModelSource` carries three tuning numbers (`scale`, `offset`, `rot`) because a
Blender export arrives at whatever size and facing that scene happened to use,
and there is no way to know either from inside a config file. They are declared
rather than derived so that fixing a gun held backwards is a number, not a code
change.

**`.gitignore` was the quieter bug.** `*.rbxmx` had excluded the model outright,
so the file existed on one machine, was invisible to `git status`, and would
never have reached the other boy or a publish. Narrow negations for `assets/**`
now carve it out; the rules above are still right for everything Studio exports
by accident.

**Sold by the Jawas**, at level 5 for 1,400 credits before their 0.8 markup.
Not an arbitrary shelf: `JawaScrap` is the only vendor in the game that could
plausibly be holding a revolver frame with a suppressor bolted to it and sixteen
visible screws, and *"Utinni! Very good price. Mostly works"* was already their
greeting. It is also the strongest thing on that cart, which is what makes the
walk out to the Wastes worth making. It first went in at level 10 and 3,100 on
the reasoning that the best thing on a scavenger's cart should be a reason to
travel — which was about the shelf and not about the gun. This is the one weapon
in the game somebody in this house made, and a gate that keeps it out of your
hand for the first several hours is the wrong gate whatever it does for the
curve.

**Rojo cannot deliver it, 2026-08-30.** `assets/` was mounted at
`ReplicatedStorage.Assets` in `default.project.json` for one day. The plugin
reported *"Synced, but 26 changes failed to apply"* and Studio showed twenty-six
MeshParts shaped like cubes — twenty-six being exactly the mesh count.
`MeshPart.MeshId` is one of the few properties Roblox will not let a plugin
write, so Rojo can create the parts and can never fill them. There is no setting
that changes this.

The mount is removed and the folder is inserted into the place **by hand, once**,
after which it lives in the saved place file — the same arrangement the template
world's scenery has always had, and for the same reason: not everything in a
Roblox game can come from a text file. Walkthrough in TESTING §9.0d. This is also
the second reason `buildImported` returns a boolean rather than trusting the
folder is there.

---

## Phase 3b — The campaign

The story, specified in [CAMPAIGN.md](CAMPAIGN.md). Mostly content, but four
small system changes have to land first.

### 3b.1 Origin — **[done]**
`PlayerProfile.origin` and `Config/Origins.luau` landed with Phase 2a, which
needed them to price a jump.

**Done 2026-08-16.** `CreationController` (modal, no toggle key, refuses
`setOpen(false)` until answered) + `OriginService`. Choosing writes `origin`,
`faction` and `homePlanet` and flies you there free, once —
`PlayerProfile.originChosen` is what makes "once" enforceable, and what
distinguishes a player who picked Scoundrel from the placeholder that made
every character one. Two things fell out of it:
- **`profile.faction` gained its first reader**, in `NPCBrain.isEnemy`: an
  Acolyte starts on Korriban with zero Empire reputation and every Aggressive
  archetype shoots anyone not Friendly, so without it picking Sith meant being
  killed by your own Academy. Independent is excluded — it is the absence of a
  flag, and every raider has it too.
- **Scoundrel's home world moved Nar Shaddaa → Tatooine.** Nar Shaddaa is a
  level 12 world and a character begins at 1. `Origins.validate` now refuses
  any home world above minLevel 1, so the next one cannot ship quietly.

**Gating done 2026-08-16, with the content that reads it.** `MissionDef.origin`
and a dialogue `Condition.origin`, each refused by its `validate()` when it names
an origin that does not exist — a misspelt one is a mission or a line no
character can ever be shown, which reads exactly like one nobody wrote.

`canAccept` checks origin *before* level, and `boardFor` **hides** that refusal
instead of greying it out. Every other lock is one the player can pick by
playing; an origin is answered once and never again, so another origin's story
on your board would be a goal you can see and never reach.

Shipped alongside, so neither field is another system with no reader:
- **four prologues**, one per origin on its home world — `KorTheEmptyBunk`,
  `OrdTheOtherCopy`, `TatTheManifest`, `TarTheSealedCrate`. Three objectives
  each, no combat, level 1, handing off to that world's existing opening chain
  where there is one. Deliberately the smallest missions in the file: a prologue
  that outstays its welcome is what a player resents on their second character.
- **four origin-only lines on the `Civilian` tree**, the archetype that spawns in
  the largest numbers on every world. Only one is ever on screen, so the menu is
  no longer for anybody and different for everybody.

Deliberately *not* done:
- **`ObjectiveDef.origin`.** `progress` is keyed by an objective's index, so a
  per-origin step would have to be *skipped* rather than filtered out — a rule in
  `isComplete`, in `MissionService`'s hidden-objective walk, and in all three
  client renderers. Four separate prologues need none of it. Revisit only if a
  *shared* mission ever wants to ask four characters four different things.
- **seeding the first skill point** into the origin's tree. Every Piloting node
  is `unimplemented` until ships exist, so a Scoundrel would be handed a rank in
  something that moves no number — precisely the failure B5 was cleaned up to
  stop. Revisit with Phase 2b.

### 3b.2 Alignment — **[done 2026-08-16]**
`PlayerProfile.alignment`, clamped -1000..1000, moved by dialogue and mission
resolution rather than by combat. Deliberately separate from `factionRep` — a
Sith at +800 alignment is the interesting case.

`Config/Alignment.luau` owns the range and the seven bands (Merciless →
Selfless) that turn the number into a word; `ProgressionService.awardAlignment`
is the only mutation, and it notifies on the band *changing* rather than on
every point, because a value that reports itself constantly is a score and this
is supposed to be a description. `Choice.alignment` and `Rewards.alignment` are
the two ways to move it.

It shows on the skills panel (**K**), not the HUD: it is a character sheet
number, and a value whose first appearance is a locked Force node reads as the
game breaking. Gating the deep Force nodes and the crystal colours is still to
come with the tree contents (§4.3) and the signature chains (3b.5).

**One rule is enforced at boot rather than trusted.** A dialogue choice that
pays alignment and can be taken twice is a button the player farms — there are
eighteen Cartel enforcers on the Promenade. `Dialogue.validate` now refuses any
choice with a non-zero `alignment` unless it also `sets` a flag that its own
`condition.notFlag` excludes.

### 3b.3 Acts, chapters and a journal — **[done 2026-08-16]**
Nearly free, as predicted, and for a reason worth recording: `boardFor` already
wired the campaign through `requires`/`next`/`minLevel`/`requiredRep`, and
`DataService.clientView` already replicates `missions.completed` and `flags` in
full. So the journal needed **no server work and no new remote** — it is a pure
client view over state that was already there.

- **`Config/Acts.luau`** — five acts (four numbered plus one `parallel`, the
  origin signature chains), each an ordered list of mission ids. Membership is
  declared *here* rather than as an `act =` field on each of forty-six
  missions: the question an act answers is "what order does the story happen
  in", and that reads as one screen, not as forty one-word lines scattered
  through 2,900. `Missions` stamps it onto `MissionDef.act` at require time, so
  everything downstream still just asks a mission what act it is in.
- **Three new checks.** A `Story` mission in no act; an act naming a mission
  that does not exist; and a mission whose `requires` points at a *later* act —
  which greys that mission out forever and is indistinguishable from unwritten
  content.
- **Flags grew a `journal` line and an `act`.** Nineteen of them now say in
  prose what the character did, and `Flags.validate` refuses one without the
  other, since a journal line filed under nothing can never be read.
- **`JournalController` (J).** Acts down the left; the selected act's page on
  the right: each finished mission with its `debriefing`, the one in hand with
  its summary, the rest as a count rather than a list of titles, then the
  decisions this character made. An act not begun shows its name and nothing
  else, and a `parallel` act's missions are filtered to your own origin.

### 3b.4 Flags — **[done 2026-08-16]**
`PlayerProfile.flags: { [string]: boolean }` plus `flag`/`notFlag` dialogue
conditions. One field, and it is the whole of branching.

A map and not an array because a profile is DataStore-serialised *and*
replicated and neither survives a sparse one — the same reason `Inventory` is
keyed by uid.

The field alone would have been the third instance of this codebase's favourite
bug: a mission writing `SawTheIntakeForm` and a conversation reading
`SawTheIntakeFrom`, producing a line that never appears, which is
indistinguishable from a line nobody wrote. So flags are *declared* in
`Config/Flags.luau` with a note saying who sets each one and who reads it, and
`Missions.validate` and `Dialogue.validate` check every id at boot.
`DataService.migrate` drops undeclared flags on load — a flag deleted from
Config is a flag that stops being true.

What a flag is *not* is mission completion: `profile.missions.completed`
already records that, and a flag duplicating it is a second source of truth
that will eventually disagree. A flag is the part of a mission its id cannot
express — which way it went.

Missions read them too (`requiresFlag`, `forbidsFlag`, `minAlignment`,
`maxAlignment`) and write them (`Rewards.flags`). The refusal reason for a
closed path is deliberately vague — *"Not the road you took"* — because the
board should not enumerate the branch you didn't take.

**First fork, at level 12.** `CorLoyaltyCheck` (kill the dissidents for the
Empire) and `CorTheWarning` (get them out first) each forbid the other's flag,
and Coruscant then talks to you differently for the rest of the game. It is
early on purpose: a consequence system the player meets in the fortieth hour is
a consequence system they will never find out they have.

### 3b.5 Signature chains — **[done 2026-08-16]**
**A lightsaber is built, not bought** (decided 2026-08-14), which forced the same
for every other origin or the Acolyte would have the only good content. Four
chains running levels 12–34, specified in [CAMPAIGN.md](CAMPAIGN.md) §5: the
saber, the Mandalorian Great Hunt, your own ship, and restoring Ordo-9. **25
missions**, plus 10 component items and 13 flags.

This is the long-standing "what is the reason to specialize?" question finally
answered — not a bigger number at rank 5, but an object. It needed no new
machinery: `MissionDef.origin` (3b.1) gates the chain, `alignment` (3b.2) picks
the crystal's colour, and flags (3b.4) carry the fork forward. What it needed
was **the discipline to build inside those five working objective kinds** —
`Kill`, `Collect`, `TalkTo`, `Reach`, `Deliver`. `Escort`, `Survive`, `Slice`
and `Destroy` are declared in `MissionKinds` and reported by nothing, so a chain
written around one is a chain that cannot be finished. *(`Slice` became real on
2026-08-17 — §4.3 target 5 — but only ever as an **optional** step.)*

**The forks, and where they sit.** Not always at part 5. The Scoundrel's is
*first* — the debt is what the chain is about, so answering it is the price of
admission rather than the payoff. Each fork sets its own flag **and a shared one
naming the moment** (`SaberBuilt`, `WearsBeskar`, `DebtSettled`), because
`requiresFlag` is an AND with no *or*: without the shared flag the last part of
the Acolyte chain would have to be written three times.

**The Acolyte forge is the only three-way branch in the game**, because
`Rewards.weapon` is one string and three colours therefore means three missions.
They partition the alignment axis at the **Unaligned band's own edges** (≤ -100
red, -99..99 purple, ≥ +100 blue) with no gaps — a gap is a chain that eats the
player's saber and explains itself only as "You are not the person this needs".
All three also `forbidsFlag = { "SaberBuilt" }`: the bounds are exclusive at an
instant but not over a lifetime, and "Neither Hand" pays nothing, so its taker
is one light-side errand away from standing in front of the Pure forge with a
second lightsaber on offer.

**Sabers were already absent from every shop table** — the vendor entry the
original note worried about does not exist, so nothing had to be removed.

**Deliberately not built**, with the reasons written into `Missions.luau` rather
than left as a surprise: assembly that can *fail* (nothing can fail a mission),
free-text ship naming (no text-entry UI, and two boys in one room would name it
something), and real co-op chain steps (nothing is party-aware yet).

### 3b.6 The recurring cast — **[done 2026-08-16]**
[CAMPAIGN.md](CAMPAIGN.md) §7 names six people the campaign is about, and the
mission text refers to them by name — Vashk signed the order, Nine remembers the
deliveries, Kadar owns the debt. **None of them existed.** A story whose
characters are only ever mentioned in briefing text is a story the player reads
*about* rather than one they are in, which is most of what "I'm left wanting
more character development" was describing.

`Config/Cast.luau` declares the six: Overseer Vashk (Korriban Academy), Sergeant
Tolen Marr (Ord Mantell Garrison), Vess Kadar (Nar Shaddaa Promenade), Ordo-9
(Taris Camp), Master Ryn Solaa (Tython Temple), Doctor Aneth Corr (Taris Lot 9).
Four are one origin's mentor each; Solaa and Corr are introduced identically to
all four, so the ally and the antagonist are shared and four players who agree on
nothing else can still be in one conversation.

**A cast member borrows an archetype for its body and overrides everything that
makes a crowd a crowd.** An archetype is deliberately a *kind* of person —
`NPCService` rolls a level from the district band, a name from a pool, a species
from a weighted table — and every one of those is wrong for a named character.
So costume, species, faction and the rig come from the archetype; level, name,
dialogue and behaviour do not. Behaviour is forced to `QuestGiver` whatever the
archetype does, which is what lets Vashk wear a Sith Lord's armour without
shooting the Acolyte he raised, and the prompt is added on `interactable or
cast`. Levels are fixed and high (26–45) for the unromantic reason that a story
character who can be killed by the players standing next to him will be.

No parallel spawner: `Cast.spawnRules(planetId)` emits ordinary
`Planets.SpawnRule`s carrying a new `cast` field, so placement, respawn,
corpses and prompts all reuse the paths that already work. The field lives on
the *rule* rather than the model because respawn is scheduled from a rule — one
that forgot it was Vashk would bring him back as an anonymous hostile Sith Lord.

Six dialogue trees, each shaped the same way: a line for the origin who belongs
to this character, a line for the origins who do not, then whatever the flags
say. They are the only conversations in the game allowed to assume they have met
you before, which is what the flags system was built for. One new flag,
`NamedTheQuiet`, is the only flag in the game raised by a conversation rather
than an errand — Solaa will say the word with you from level 20, and Vashk,
Tolen Marr and Aneth Corr all answer differently once someone has.

`Missions.validate` now accepts a cast id as a `giver` (checking only that the
mission's planet is where that character stands), and `Cast.validate` is run at
boot from `DialogueService`, which is also the one place that can see both
configs without closing a require cycle.

---

## Phase 4 — RPG depth

- ~~Skill tree UI~~ — **done**, see 1.5. The *contents* of the trees are not:
  see 4.3, and B5 in the playtest findings
- ~~Loot drops with rolled affixes, and the `profile.inventory` change they
  need~~ — **done**, see the Diablo direction section
- ~~A bag cap, and selling or destroying a roll you do not want~~ — **done**,
  same section. Vendor buy-back exists now, so a shop is a shop in both
  directions
- ~~Per-zone level bands, and the "you are underlevelled" warning on crossing
  into one~~ — **done**, `542abb7`. Derived from `ZoneDef.distance` rather than
  waiting on 3.1's tile grid, so `Planets.bandFor` answers "how hard is it
  here?" for every district on all nine planets today
- ~~Radiant missions composed from the tables that already exist~~ — **done**,
  see 4.0. The four planets that shipped with no missions at all now have some
- ~~Weapon mods / attachments layered onto `Config/Weapons.luau`~~ — **done
  2026-08-19** as **crystals and sockets**, see 4.4. Not layered onto `Weapons`
  in the end: a mod that only fits a blaster is half a system, and the same
  stone belongs in a coat
- Faction reputation consequences. Missions already award rep
  (`rep = { Republic = 120, Empire = -180 }`) and nothing reads it back.
  Phase 3b needs this, so it is no longer optional
- Companion NPCs — Ordo-9 is the argument for them (CAMPAIGN.md §5.4)
- ~~Is a lightsaber bought or earned?~~ **Built, over five quests** — and every
  other origin got a signature chain to match. See 3b.5

### 4.0 Radiant missions — **[done]**
~~A generator that composes missions from tables that already exist: an
archetype × a point of interest × an objective template × a level band, seeded
per player per day.~~ Built as `Shared/Config/Radiant.luau`. Three templates —
**Cull** (kill 6 of whatever spawns hostile in a district), **Salvage** (recover
4 of something from a point of interest and haul it back to town) and **Survey**
(reach a place out in the wilderness) — composed against every district of every
planet. The 15 authored missions are the story spine; these fill the world
between them, and four planets that had no missions at all now have some.

Three decisions worth keeping:

- **Generation is pure and happens once at require time**, and the results are
  folded straight into `Missions.defs`. That is load-bearing rather than tidy:
  `MissionService` sends the board as a list of bare *ids* and the client
  resolves each one out of `Missions` itself, so a generator that consulted the
  clock or a `Random` would hand the client an id it could not look up. It also
  means every downstream reader — `boardFor`, `validate`, `Missions.ids`, and
  through that `PickupService`'s pickup spawn table — needed no changes at all.
- **Ids are `@r:<planet>:<zone>:<template>`**, prefixed like Dialogue's
  generated node ids. Stable and bounded, because `profile.missions.completed`
  is keyed by id and outlives any change here; one keyed by date would grow
  forever and mean nothing on read-back.
- **Rotation is per day, not per player**, which is where this deliberately
  departs from the line above. A mission board is a place in the world — two
  players standing at the same one and reading different postings is a bug
  however it got there, and it makes "go take the bounty I just took"
  impossible to say out loud. Which matters here specifically, because this
  game is played by two brothers in the same room. `Radiant.POSTED_PER_DAY = 3`
  and the window advances by one a day, so the board is recognisable from
  yesterday and still eventually shows everything.

The one piece of scaffolding this needed: `Objective` and the three mission
types moved out to `Config/MissionKinds.luau`, because `Radiant` names them and
`Missions` requires `Radiant`. `Missions` re-exports every name, so no existing
caller changed.

`showmethemoney` (`DevService`) prints every generated mission and today's
postings — the offline test, same reasoning as `iseedeadpeople`.

### 4.3 Skill trees, properly — **[targets 1-3 done 2026-08-16, 4 and 5 done 2026-08-17]**
Raised 2026-08-15: *"the skill trees need to be incredibly well thought out and
align with the objectives and gameplay."* Correct. The UI is done (1.5) and the
**content is not**. What exists is 19 skills across 4 trees where:

- Every skill is `maxRank = 5`.
- Every skill is a **flat linear passive** — `+6% per rank`, `+15 HP per rank`.
  There is not one branch point, one either/or, one skill that changes how you
  play rather than how big your numbers are.
- One skill (`ForcePush`) claims to unlock an ability. It doesn't (B5).
- Six do nothing at all (B5).

**Enforcement shipped 2026-08-16.** B5's rule was being kept by hand, and a rule
nobody checks decays into a comment — so it had already missed two skills.
`Progression.LIVE_STATS` (moved out of `Affixes.luau`, since it describes the
stat table and both systems are checked against it) names every stat with a
reader and where that reader is, and `Progression.validate()` requires each node
to be in exactly one of three states: a live stat, a dead stat *plus* an
`unimplemented` reason, or **no effect at all** — a gate, worth what it unlocks.
`WorldService` warns on anything else at boot.

The two it caught:

| Skill | Stat | Was | Now |
|---|---|---|---|
| Deflection | `DeflectChance` | dead, unmarked | **implemented** — a sabre batting blaster bolts away |
| Force Sensitive | `MaxForce` | dead, unmarked | a **gate**: `maxRank` 5 → 1, no effect |

`Deflection` was worth building rather than labelling: it is the one thing
everybody knows a lightsaber does, and marking it COMING SOON would have left
the Force tree with a single working skill. Blaster damage only (so it counters
the ranged enemies the other trees answer with more health, and does nothing
against a gaffi stick), sabre must be equipped (a build, not a buff), all or
nothing (shaving a percentage off is `DamageReduction` under another name),
capped at 75%.

`Force Sensitive` could not be marked `unimplemented` — three skills require it,
so the whole tree would have locked. It charged five points for `+20 Force
energy` against a pool nothing has ever spent; it now charges one for what it
actually sells, and frees four points for skills that do something.

**Still open below: everything about the *design*.** This was the honesty pass.
- `requires` is a single-parent chain, so a "tree" is really four short ladders.
  There is no reason to ever stop partway, so every build converges.

Max level and point income need checking against this too: if the points
available across the whole game exceed the points needed to max everything
useful, there is no *choice*, only an order.

**What good looks like** — the design targets, in priority order:

1. **Actives, not just passives.** A tree should hand you *verbs*: Force Push,
   Force Pull, Lightning, Saber Throw, a grenade, a stim, a slicer spike, a
   scanner ping, a droid companion. A point that gives you a new button is worth
   ten that give you +6%. This is also what makes the Diablo comparison honest —
   Diablo's trees are almost entirely abilities and ability *modifiers*.
2. **Real choice points.** Mutually exclusive nodes (a saber form that trades
   defence for damage), capstones that cost most of a tree, and prerequisites
   that fan out rather than chain. If two players at level 30 have the same
   sheet, the tree failed.
3. **Alignment on the Force tree.** Light and dark branches, gated by
   `alignment` from 3b.2 — which now exists and moves, but which nothing in the
   tree reads yet. Lightning vs. healing is the oldest and best example in the
   setting, and it is what will make 3b.2 pay for itself.
4. **Complementary co-op.** The long-standing goal (Jedi + soldier). Express it
   as skills whose *effect lands on your teammate* — a mark that raises everyone's
   damage on a target, a shield you throw, a revive. Two players should be more
   than twice one player. Four trees for four origins is the right skeleton; what
   is missing is the connective tissue.
5. **Skills that open the world, not just win fights.** Slicing a door, a
   persuade check in dialogue, a disguise that holds (N1), spotting a hidden
   cache, negotiating a better loan (N6). Every one of these is a `Condition` in
   dialogue or a check in an interaction, and they are what make a build feel
   like a *character*.

**Hard rule going forward, from B5: a skill is not added to `Progression.luau`
until something reads its stat.** ~~Cheapest enforcement is a boot-time check —
a table of stat → "who consumes this", validated like `Factions.validate`.~~
**Done** — `Progression.LIVE_STATS` + `Progression.validate()`, above.

**Sequencing.** This is a big design pass and it depends on things that do not
exist yet: abilities need a cooldown/resource system and input bindings, the
Force tree needs `alignment` (3b.2), the Piloting tree needs ships (2b), and
world-opening skills need §3.1's interiors and terminals. So: ~~do the B5
mitigation now~~ (done, above), write the full tree design alongside CAMPAIGN's signature
chains (3b.5) since they answer the same question — *why specialize?* — and
implement after 3.1. Design goes in a new `SKILLS.md` when it is written; this
section is the brief.

#### Targets 1 and 3, built 2026-08-16
The sequencing note above said abilities needed "a cooldown/resource system and
input bindings" that did not exist. They exist now, so targets **1 (actives)**
and **3 (alignment on the Force tree)** are done, and they turned out to be the
same piece of work: an ability is what makes an alignment branch worth having.

- **`Config/Abilities.luau`** — five verbs, and deliberately only **three
  shapes** (`Cone`, `Point`, `Aura`). Every power worth having so far is a fan
  in front of you, a thing thrown at a spot, or something that happens around
  you; a service with a branch per ability is a service nobody can add to. A
  sixth ability is a table entry and gets its server resolution, its visual and
  its slot for free.
- **Force Push exists.** It had said "Unlocks Force Push" and been marked
  `unimplemented` since the tree was written — the oldest broken promise in the
  file, and B5's headline example.
- **The alignment fork.** `ForceLightning` (`maxAlignment = -100`) and
  `ForceMend` (`minAlignment = 100`) at level 16, and neither character can buy
  the other. Gated on the **node purchase**, not on pressing the key: an ability
  that refuses when pressed is a skill point already spent on nothing, which is
  the exact failure `Progression.validate` exists to catch.
- **Only Force abilities cost a resource.** A Scoundrel has no mystical meter
  and giving him one for symmetry would be a bar on screen that means nothing.
  The asymmetry is paid for the other way: Force abilities hit harder, and the
  non-Force pair (`FragGrenade`, `FieldStim`) cost only their cooldown.
- **`MaxForce` finally has a spender**, so `ForceSensitive` went back from a
  bare gate to granting 100 Force — five of the six stats B5 found dead are now
  live and named in `LIVE_STATS`.
- **`AbilityService`** owns cooldowns, the Force pool and every effect, on the
  same authority inversion as `CombatService`: the client sends an id and a
  camera direction and nothing else. All damage routes through
  `CombatService.applyDamage`, so an ability kill pays XP, loot, reputation and
  mission progress exactly like a blaster kill.
- **The pool is not saved.** It refills on spawn. A resource that regenerates in
  under a minute has nothing to remember, and persisting it would mean logging
  back in unable to do the thing you logged in to do.
- **Two new boot checks.** `Abilities.validate` refuses an ability whose node or
  scale stat does not exist, whose shape has no radius or angle, that does no
  damage *and* no healing *and* no knockback, or that is an `Aura` dealing
  damage (it would hit your own side). `AbilityService.init` reads the join the
  other way too — a *skill* naming an ability that does not exist.
- **The bar is 1-4, bottom centre**, drawn from `Abilities.unlockedBy` so buying
  a rank is the same event as a button appearing. Every press is refused while
  `Panels.anyOpen()`, because `DialogueController` owns the number keys during a
  conversation.

#### Target 2, built 2026-08-16
The alignment fork above was the first and only branch point in the game. Three
more, plus the first capstones.

**Measured before designing.** 49 points at level 50 against 74 buyable ranks,
so scarcity already existed — what was missing was *shape*, not budget. That
made the work "add forks and capstones", not "raise the price of everything".

- **Three exclusive pairs.** `Deadeye` ⟷ `Overcharge` (crit on one target vs.
  bolts that pass through four — one is the answer to a boss, the other to a
  corridor, and neither is better, which is the test a real choice has to
  pass); `SaberDeflect` ⟷ `SaberFocus`, which is this section's own example,
  *"a saber form that trades defence for damage"*; and `ForceLightning` ⟷
  `ForceMend`.
- **The Lightning/Mend exclusion is not redundant with the alignment bounds.**
  Alignment moves, and the bounds are only read at the moment of purchase — so
  a player could buy Lightning at -200, spend a few missions being decent, and
  buy Mend at +200, ending up holding both halves of a fork that exists to be
  a choice. This was a real hole, found while writing the pair.
- **Rank counts differ on purpose.** Overcharge is 3 ranks against Deadeye's 5:
  a fourth body per bolt would only matter in a room that does not exist.
- **Three capstones, one rank each, priced in *ranks spent in the tree*** —
  `Executioner` (18 in Combat, and the only thing in the game that touches the
  crit multiplier), `ForceAttunement` (18 in Force, -40% Force cost) and
  `KitDiscipline` (12 in Engineering, -35% cooldown on *every* ability
  including Force ones, so a saber character has a reason to look at a tree he
  never would). 18 + 18 + 12 + 3 = 51 against 49 points: **at most two**, and
  the gap is the decision. Ranks rather than distinct nodes, so it cannot be
  satisfied by buying rank 1 of everything. Piloting gets none — the whole tree
  is `unimplemented` behind ships, and a dead capstone is surface for nothing.
- **`canPurchase` only refuses the *first* rank of an excluded node**, so the
  tree never takes back something it already sold.
- **Six new boot checks in `Progression.validate`:** an `excludes` naming a
  node that does not exist, a node excluding itself, a **one-way** exclusion
  (which half you could still buy would depend on the order you clicked them
  in), an exclusion across trees (the panel shows one tree at a time, so the
  player cannot see what they lost), a capstone priced above what its tree can
  ever hold, and — the one that protects this whole section — **buyable ranks
  vs. points at the level cap**. That last property is invisible when you are
  looking at the node that breaks it.
- **The panel warns before the click.** There is no respec, so the first rank
  of an exclusive node is the most expensive press in the game: the detail pane
  says what it closes off in amber while the button still reads SPEND 1 POINT,
  and a node already closed off reads `CLOSED OFF` in the list rather than
  looking available until clicked. A capstone's tree-point price is shown in
  the body text, because `canPurchase` returns one reason and "No skill points
  available" would come first.
- **`CombatService.resolveShot` / `swingMelee` now take a `ShotMods` table.**
  Adding crit damage and pierce positionally would have made a nine-argument
  function whose call sites read `nil, 1, 0`.

**Open question this creates: respec.** Every exclusion is permanent, which is
what gives it weight, but the game has no way to unspend a point and no way to
try a build. The mitigation shipped is visibility, not reversibility. If
playtesting says the forks feel like traps rather than choices, a paid respec at
a vendor is the answer — and it should cost credits, not be free, or the choice
stops being one again.

#### Target 4 — complementary co-op, built 2026-08-17
The brief: *"skills whose effect lands on your teammate — a mark that raises
everyone's damage on a target, a shield you throw, a revive. Two players should
be more than twice one player."*

**The gap, stated precisely.** Every one of the 21 nodes made *you* better, so
two players were worth exactly two players. The two `Aura` heals reached a
teammate, but only as a side effect of `Aura` being the only shape that does —
and a heal is worth the same whether one person or three are standing in it.
Nothing in the game was worth *more* because somebody else was there.

- **Two new fields on `AbilityDef`, not two new shapes.** `mark` (a fraction
  added to the damage **everyone** does to what it lands on) and `absorb` (a
  pool of damage taken off allies before their health is), plus a shared
  `duration`. Neither changes *who* an ability reaches — a mark is a Cone that
  does not hurt, a barrier is an Aura that does not heal — so the three-shape
  rule and the no-branch-per-ability rule both hold.
- **`MarkTarget` is in the Combat tree**, behind `Spotter` (level 10). A co-op
  mechanic only one origin can bring is a co-op mechanic that mostly does not
  happen, and three of the four origins never open Force. It is the arithmetic
  that makes it co-op: **alone it is a bad button** — one long cooldown for
  under a third more damage — and it is worth the *party's* output, so the same
  skill point buys more the more people are shooting.
- **`ForceBarrier` is the Force half, and the one node in that tree with no
  alignment on it.** Sheltering the person beside you is not a moral position,
  and gating it would have meant the brothers could only cover each other if
  they had made the same choice about the fork the campaign spends thirty
  levels insisting is theirs alone.
- **`CombatService` holds both, not `AbilityService`.** `applyDamage` is the
  only function that sees a hit land, which makes it the only thing that can
  read them. State next to the *writer* would have meant a getter damage has to
  remember to call — the "server system with no entry point" failure again.
  Weak-keyed tables, so a dead NPC's mark goes away with the NPC.
- **Order inside `applyDamage` is load-bearing.** The mark multiplies *before*
  armour, so it reads as "that one is easier to kill" and is worth the same to
  whoever else is shooting; the barrier soaks *after* armour, so a heavily
  armoured player does not get more out of the same pool than the one who
  needed covering. A hit the barrier eats whole returns 0 and stops, like a
  deflect — otherwise it is a floating "0" and a `damaged` signal for nothing.
- **Nothing stacks.** A second mark takes the larger bonus and restarts the
  clock; a second barrier does the same with what is left. Two Force users
  alternating barriers would otherwise pile up a pool nothing could chew
  through, and they play in the same room.
- **The outline is `Occluded`.** A mark visible through terrain is a wallhack.
- **Five new boot checks in `Abilities.validate`:** a timed effect with no
  duration, a duration with nothing that lasts, an `absorb` on a non-`Aura`
  (it would shield the enemies in front of you), a `mark` on an `Aura` (it
  would mark your own side), and the old "does nothing" check widened from
  three effects to five.
- **The bar went from 4 slots to 6.** Four was sized to the number keys a
  conversation also uses, and it happened to be exactly the most one character
  could unlock — so nothing had ever been hidden, and a fifth ability would
  have been a skill point spent on a button that never appears. Keys 5 and 6
  are the bar's alone. **Seven abilities is where this stops working**, and
  that is the point at which a loadout screen is a feature rather than a menu.

**Not built: the revive.** The brief lists it third and it is the biggest of the
three, because it needs a downed state — a character at zero health who is not
yet dead — which touches respawn, aggro, mission failure and the death handling
in `PlayerService`. The mark and the barrier deliver the target's actual claim
without it. Worth doing when there is a reason to change death.

#### Target 5 — skills that open the world, built 2026-08-17
The brief: *"Slicing a door, a persuade check in dialogue... Every one of these
is a `Condition` in dialogue or a check in an interaction, and they are what make
a build feel like a **character**."*

**The gap, stated precisely.** `Slicer` was one of the two remaining nodes
carrying an `unimplemented` reason: five ranks of `SliceTier` that nothing in the
game read, on a tree the Scrapper is pushed toward at creation. And the
`Objective.Slice` kind had been declared in `MissionKinds` since the mission
system was written without one mission ever using it, because there was nothing
in the world to slice.

- **Terminals are derived, never listed.** `Config/Terminals.luau` requires only
  `Planets` and walks it: every POI whose `kind` is one of five secured kinds
  (Spaceport, Base, Outpost, Ruin, Temple — Cantina and Market are deliberately
  not) carries exactly one terminal. **The terminal's id is the POI's id**, which
  collapses three problems into none: a `Slice` objective names a place the same
  way `Reach` already does, `Missions.validate` can check it with machinery that
  exists, and there is no second namespace to keep in step with the first. Tier
  comes from the district's level band against the galaxy's own ceiling, so
  adding a planet re-tiers the map instead of going stale.
- **`TerminalService` puts a console at the POI at a deterministic angle**
  derived from the id — never rolled. The brothers play in one room and shared
  world state has to read the same for both. The same reason the 600s cooldown
  and the spent state are the *world's*, not each player's.
- **A locked terminal advertises its own tier**, and the refusal names the exact
  rank that would have opened it. This is the 2026-08-17 playtest lesson —
  *finished but unreachable is not finished* — applied before it could bite: a
  skill that opens a door nobody knows is a door is a dead skill.
- **Every `Slice` objective must be `optional`, and `Missions.validate` refuses
  one that is not.** Slicer is one node of one of four trees, gated at level 6,
  and there is no respec. A required slice is a mission three quarters of
  characters are permanently stuck inside. Slicing is a door the Scrapper opens
  and everyone else walks past — which is the point of the target, not a
  compromise on it.
- **The first authored one is on `TarWhoBuysCrates`** (Scrapper chain, Taris,
  `minLevel` 7 — one level past Slicer's gate): the first thing in the game a
  skill *opens* rather than *wins*.
- **`Dialogue.Condition` gained `minStat` and `maxStat`**, maps rather than
  pairs so a condition cannot be half-written, and two maps rather than one
  because half the stat table is better when it goes down (`PriceMult`). The
  context reads `ProgressionService.getStats`, not the profile — the same table
  combat reads, so a line offering something the character cannot do cannot
  appear. `Dialogue.validate` checks each named stat against `LIVE_STATS`, the
  same registry `Affixes` is checked against. Three lines exist so far: two on
  the Merchant (a slicer sees the unlocked ledger; a haggler is invited to try
  the other number) and one on the Smuggler at tier 3.

Targets 1-5 are done. What §4.3 still wants is the *volume* — three stat-gated
dialogue lines is a proof, not a body of work — and that is content, written
alongside the campaign, not another system.

### 4.1 Analytics — **DONE 2026-08-18**
The cheapest item on this roadmap that measurably improves the game, and the
only one that makes every later balance decision better informed. Every number
in `Config/` was picked by feel and nothing reported back: we did not know which
missions get abandoned, where players die, or what they actually buy.

`AnalyticsService.luau` batches events and posts them to a Supabase edge
function, which writes one row per event to Postgres. Turning it on is
[SETUP_GUIDE.md](SETUP_GUIDE.md) §9.

Built before 5.1 deliberately. It shares the whole Roblox → edge function →
Postgres path with the conversation feature ([LIVING-NPCS.md](LIVING-NPCS.md)
§5) but needs no API key and costs nothing per call, so the transport gets
proved by something cheap before anything expensive rides on it.

Four decisions worth keeping:

- **It cannot break the game.** `log` never yields, never raises, and fetches
  every dependency with `ServiceLoader.find`. It is called from combat and the
  shop, where an error is a visible failure of something the player was doing.
- **It drops rather than grows.** A capped queue is a hole in a graph; an
  uncapped one is a memory leak on a live server. Every loss says so in Output,
  because a silent gap is indistinguishable from a quiet week.
- **It observes where a signal exists and calls where one does not** — and does
  not add a signal for telemetry's sake. A signal is a public event other
  systems come to depend on, and one that exists because a graph wanted it is
  architecture answering to nobody.
- **Studio is labelled, not excluded** (`job_id = 'studio'`). Excluding it would
  make the feature untestable by the only means available; mixing it would let
  fifty test deaths drown four real ones.

The `zone` column was designed and then dropped before any row existed: no
caller knows a player's district when an event fires, so it would have been null
everywhere — a schema promising an answer the game cannot give, which is this
project's named recurring failure mode wearing SQL.

### 4.2 Secret unlock conditions — **DONE 2026-08-18**
`Config/Secrets.luau` + `SecretService.luau` + one new field on
`Dialogue.Choice`. Six secrets, one per named character in `Cast.luau`. Built
before the free-form layer rather than with it, exactly as planned: the model,
when it arrives, is a text generator bolted onto a reward system that already
worked without it. See [LIVING-NPCS.md](LIVING-NPCS.md) §2.

- **The whole security argument is that `SecretService` is boring.** `raise` is
  handed a speaker, a topic word, and a `Dialogue.Context` the *server* built
  out of the player's own profile. It looks the word up in a table nobody
  outside the machine can edit, runs the same `Dialogue.meets` every other
  conversation line runs, and pays out. Nothing it reads came from the client,
  and nothing it reads will have come from a language model either — the model
  gets to pick a word out of a closed vocabulary, and that is all it gets. The
  worst a jailbroken character can do is *say* something it should not have. It
  cannot open the drawer, because the drawer was never listening to it.
- **`Choice.topic` is the seam, and it never leaves the server.** A choice that
  carries a topic still has a `next`, and that `next` is the *deflection* — the
  character changing the subject. If the check passes, `SecretService` returns
  `opens` and the conversation goes there instead. So an unqualified player sees
  a real, in-character non-answer rather than a greyed-out line advertising that
  there is something here, and the client is never told which of the lines it
  was handed is the interesting one.
- **The record is a `Flags` id, not a new `profile.secrets` set.** No
  `PROFILE_VERSION` bump, free `JournalController` integration, and later
  dialogue can gate on having heard it with the `flag` condition that already
  exists. Raised *last*, through `awardAlignment(player, 0, { record })` — the
  same choke point every other flag in the game goes through, so an undeclared
  record id is the same boot warning here as anywhere.
- **It pays once and answers forever.** The reward is gated on the flag; the
  *answer* is not. Ask twice and the character tells you again, which is what a
  person does, and gets you nothing, which is what a ledger does. One flag, so
  the two cannot disagree.
- **Rejected: adding `hasItem` to `Dialogue.Condition`,** which is what
  LIVING-NPCS §2's sketch used. It would have needed `Context.inventory`, a
  change to `meets`, and a fifth predicate at two validate call sites. The
  twelve conditions that already exist — origin, level, rep, mission ×3, flag
  ×2, alignment ×2, stat ×2 — expressed all six secrets without straining.
  `Dialogue.conditionProblems` was extracted so both validators share one
  implementation rather than drifting into two.
- **Reachability is validated in both directions**, because *finished but
  unreachable is not finished* is now a rule with a scar behind it.
  `Secrets.validate` fails a secret whose topic no choice in that speaker's tree
  asks about, *and* a `Choice.topic` that no secret in that same tree answers —
  keyed by tree, so a topic word learned from one character cannot be aimed at
  another.
- **Rolled affixes only on things you can equip.** `ProgressionService.gearStats`
  reads rolls from the outfit and weapon slots only, so `validate` refuses rolls
  on a quest item and refuses an affix whose `slot` does not match. Credits are
  awarded `raw`: every other credit in the game is a price or a fee and scaling
  those is Bargaining's whole point, but what somebody *tells* you is not a
  transaction, and a secret worth 40% more to one build would be the only
  farmable value in the file.
- **The one refusal:** a rolled item into a full bag does not pay and does not
  raise the flag, so the secret can be earned again once there is room. A unique
  object that silently evaporates is a loss a player cannot diagnose.

### 4.4 Crystals, sockets and the panel that shows them — **DONE 2026-08-19**
Raised 2026-08-19: *"we need better visuals, infographics, designs in these
menus"* and *"a more robust / elaborate gems / rarity setup with various gemstone
colors that have different abilities and improvements. Very similar to what
Diablo has."* Both halves were fair. The rarity system that shipped the week
before is **rolled at drop time and never touched again** — the player finds a
Legendary or does not, and has no decision to make about it afterwards. And the
panel showing all of it was grey rows with no icons, no bars and no picture of
the thing being looked at.

Shipped as three commits: the stones, the world payoff, the panel.

**Flavour is "crystals", not gems.** Focusing crystals are era-correct, they are
already why a blade is the colour it is, and the word carries no franchise-
specific trademark into a public repo.

**What a crystal does depends on what it is socketed into.** This is the Diablo
property worth stealing and the reason the whole thing is not just another affix:
Crimson is damage in a weapon and armour on a coat, Azure is fire rate on a
blaster and crit on a blade. It maps exactly onto the `Affixes.ITEM_SLOTS` split
built the day before, so a stone's four meanings are four legal stats rather than
four inventions.

- **Nothing numeric is authored in `Crystals.luau`.** The obvious shape is twenty
  rows with a stat and a number on each, and it is wrong twice: it is twenty rows
  to retune every time an affix moves, and nothing stops row nineteen quietly
  disagreeing with the affix that moves the same stat. A crystal's value is
  instead the midpoint of the affix for its stat times its grade's scale, so
  there is one balance curve per stat and a crystal cannot drift away from the
  enchantment it competes with. Four colours × five grades
  (`0.4 / 0.7 / 1.0 / 1.5 / 2.2`), ids derived — `CrimsonChipped`, `Crimson`,
  `CrimsonPerfect` — composed at require time, the `Radiant.luau` pattern.
- **Four colours, not five, and that is the ceiling.** The legal stats for a slot
  come from `Affixes.forSlot` and there are only five or six. These ten
  assignments are very nearly all of them and nothing repeats except `CritChance`
  inside Azure. A fifth colour would have to duplicate a line or invent a stat,
  and inventing a stat is the four-edit job from `MeleeDamageMult`.
- **A crystal may only move a stat an affix on that slot could move**, and
  `Crystals.validate` checks it at boot beside `Affixes.validate`. This is
  yesterday's bug generalised — a saber rolling `BlasterDamageMult` passed
  validate because the stat had *a* reader, just not a reader on *that item*.
  `Affixes.statsForSlot` was extracted from the loop `Loot.repair` and
  `Secrets.validate` had each built inline so the rule has one implementation. It
  is also why Azure grants crit and not cooldown on a saber: `onSaberSwing` calls
  `Weapons.cooldown(id)` with no multiplier at all.
- **Sockets are what finally gives Common a job.** `Loot.rollDrop` treated a nil
  affix roll as no drop at all, which is to say Common did not exist — it was the
  word for the 65% of kills that gave you nothing. A drop now survives if it has
  affixes *or* holes (`Crystals.MAX_SOCKETS = 3`, reached at item level 24), so a
  plain socketed DH-17 is worth stooping for.
- **Socketing is free and can be done anywhere; removal is a vendor service, it
  costs credits, and it destroys the stone.** Diablo's own rule, and it earns its
  keep twice here: vendors get a job they did not have, and the economy gets the
  credit sink it lacked at the top end. `Shops.EXTRACT_FRACTION` *multiplies* by
  the vendor's `priceMult` rather than dividing by it, unlike `SELL_FRACTION`,
  because the player is buying a service — so the dearest trader is also the
  worst place to change your mind, the mirror of the sell spread.
- **`socketed` is a map keyed by the index as a string, never an array** — the
  third time in this project, and the same reason both times before. No migration
  was needed: an old save has no sockets and `nil` is already the right answer.

**The world payoff, which is the point of choosing crystals over a stat stick.**
A crimson stone makes the blade red, its glow red, its trail red; in a blaster it
makes the bolts red. Colour was already pure data (`WeaponPart.color`,
`WeaponPart.light.color`, `WeaponDef.boltColor`), so this is a tint applied at
build time and never a mutation of the config table. `WeaponModel.build` takes an
optional tint and recolours **any part carrying a `light`** plus its `PointLight`
and `Trail` — "the emissive part is the blade" is derivable from data already
there, so no new field. The tint rides on a server-set attribute rather than
being computed per client, so the shooter and everyone watching read the same
number and a hacked client can only recolour a bolt on its own screen. Which
matters here specifically: two brothers, one room, one blade each.

**The panel.** `src/client/UI/Theme.luau` is new and is the boring half — seven
controllers had each redeclared the same eight colours and three widget helpers,
and `VendorController`'s `DIM` had already drifted two points off everyone
else's. Eleven controllers now share one module, plus `stroke`, `gradient`, `bar`
and `pips`. `HudController` keeps its own `text` on purpose and says why: the
shared one pins `TextYAlignment` to Top, which is right for a panel label in a
tall box and wrong for every one-line label on the HUD.

`InventoryController` was then rebuilt against it:

- **A `ViewportFrame` showing the real thing.** A `WorldModel`, a `Camera` and a
  `PointLight`, holding the actual `WeaponModel` / `ShipModel` / `RigBuilder`
  output — in its real colours, *including the crystal tint* — turning on
  `RenderStepped`. Viable only because every model in this game is built from
  `Instance.new`; a project with mesh ids would need an asset here and this one
  never will. The rig arrives with a `Humanoid` that tries to stand and a stock
  `Animate` script, so `inert()` anchors every part and destroys both.
- **Stat bars against a derived maximum.** `Weapons.maxima()` and
  `Outfits.maxima()` walk the catalogue and memoise, in the spirit of
  `Weapons.classes()`. An authored `MAX_DAMAGE = 60` is correct on the day it is
  typed and silently wrong the first time somebody adds a heavier rifle, and the
  symptom — two different weapons both filling the bar — is exactly the sort of
  thing nobody reports. It follows that some weapon always fills each bar
  completely, which is the honest reading: the bar means "against the best in the
  game".
- **`StatLine` carries `raw` and `max` beside `value`.** The alternative was
  parsing `"1.4/s"` back into a number on the client, which is a bug waiting for
  the first stat that prints a unit. Both absent means the line is text only, the
  right answer for a ship's seat count and for a loose crystal.
- **Rarity colour comes from `Affixes.rarityAt` in a loop**, exactly as
  `HudController` does it, so the panel and the drop toast cannot disagree about
  what Epic looks like.
- **Everything below the header is one `ScrollingFrame`.** A Legendary outfit is
  three bars, four affixes, a level line and three sockets; a Common blaster is
  three bars. Pixel offsets that fit both would eventually push the *clickable*
  socket row off the bottom edge.
- **Two-press confirm on removal**, matching the existing DISCARD button, because
  it spends credits and destroys a stone. The button is simply absent away from a
  vendor rather than present and refusing.

---

### 4.5 The 2026-08-19 playtest — three items, one shape — DONE 2026-08-19

> *"I'm still not able to swing my lightsaber. to shoot, I click, is it different
> for the light saber? also, I was able to sit in the really sad / blocky ship but
> it doesn't move. I tried the arrows and I tried the normal w / a / s / d letters
> too."*

One sentence, three items, and the same lesson under two of them: **a feature is
only as reachable as its least reliable dependency.** Both the saber and the ship
were finished, correct systems that the player could not get to work.

**The saber swing was drawn on a joint the game does not own.** Damage was being
dealt — the server never doubted it — but the entire visual was a `Motor6D.C0`
write on `RightShoulder`. The player's body is Roblox's own avatar, not a
`RigBuilder` rig, so an R6 avatar (or any rig without `RightUpperArm`) meant
`motor()` returned nil and `swing` bailed before drawing anything at all. Asked
what he actually saw, the answer was *"nothing at all moves"* — which is the
signature of a guard clause, not of a subtle animation.

The fix is a **root-driven swept arc** — an anchored Neon part with a `Trail`,
swung through 150° of yaw and a 35° falling pitch in world space from the
character's `PrimaryPart`, tinted by the socketed crystal. It runs
**unconditionally, before the arm code**, so the picture and the damage can no
longer disagree. The arm motion is still attempted and still better; it is now
*polish on top of* the swing rather than the whole of it, and its absence warns
once instead of failing silently.

**The ship looked like a seat-choice problem and was a reachability problem.**
The first attempt reasoned that only `DriverSeat` is a `VehicleSeat`, that only a
`VehicleSeat` turns WASD into `Throttle` and `Steer`, and that seats are entered
by silent `Touched` — so the player had simply landed in one of several identical
black seats. It promoted a passenger in an empty ship to the pilot's seat. The
report came straight back: *"I'm still not able to drive. please figure this
out."*

**A repeat report means the first fix guessed at the cause — for the second time
this week.** The guess was aimed at a seat he was never reliably getting into at
all. `ShipModel` builds one invisible `Chassis` sized to the hull's *whole*
bounding box, and it is the only part in the model with `CanCollide` on. Every
`seatOffset` in `Ships.luau` is comfortably inside that box. On the Hover-Sled the
chassis spans local Y −1.825…+0.700 while the driver's seat's top face is at 0.0:
**the seat is seven tenths of a stud beneath a solid invisible roof, and standing
on the hull means standing on that roof.** `Touched` cannot fire between two parts
that never overlap, so sitting down at all was the solver letting the character
clip through the collider for a frame. It worked once. The detail pass in the same
commit made it 0.25 studs worse by raising the bounding box with running lights.

There is no seat position that is both inside the hull, where a seat belongs, and
outside a collider drawn around the hull by definition — so this was never
tunable. Seats are now `CanTouch = false` and **boarding is a `ProximityPrompt`**,
the verb this game already uses for vendors, terminals and dropped loot. It works
regardless of geometry and it says out loud that the ship can be boarded at all.

**And then it was reported a third time** — *"holding E does nothing. I've stood
on all sides without ever seeing a prompt."* The prompt had been put on the seat,
which meant it was put in the middle of an opaque ship. **A `ProximityPrompt`
draws its billboard at its parent**, so the label was live, in range and painted
over by the hull every frame. The measurement that fixed the second bug — the
seats are buried inside the collider — was the same fact that broke the third fix,
and I read it as a physics problem and not as a rendering one.

So the prompt does not live on a seat. It hangs from an `Attachment` on the
chassis, **three studs above the top of the bounding box**, in clear air from
every angle a player can stand at. `RequiresLineOfSight` stays off for the one
angle that is still blocked — looking up at it from underneath — and
`MaxActivationDistance` is derived from the hull, since sixteen studs is generous
beside a swoop bike and does not reach the ramp of a forty-stud freighter.

**One prompt, not one per seat.** The seat you get is not a choice worth a menu,
and offering four identical labels on one hull was answering a question nobody
asked. The promotion rule survives as a **label instead of a surprise**: while
nobody is flying it reads `Pilot` and puts you at the controls; the moment
somebody is, it reads `Ride` and puts you in the back; when the ship is full it
switches itself off rather than offering a seat it has not got.

That prompt then has to *stay* live while somebody is flying — it is how the
second brother gets in the back — which put a `Ride` label in the driver's
windscreen for the whole journey. So `VehicleController` turns
`ProximityPromptService` off on the client of whoever is aboard. That is a
client-only write to a property the server never touches, so it cannot race the
`Enabled` flag the server is keeping honest, and it is the right answer as well
as the cheap one: every prompt in this game is something you would have to get
off the speeder to use anyway.

**"Really sad / blocky" is answered with edges, not with boxes.** A large box is
exactly as blocky at ten studs as at a hundred; what reads as a surface is a face
broken by a seam, a hatch and a pipe. Two generators — `row` (a repeated rib,
seam or louvre along an axis) and `greebles` (a seeded scatter of small clutter
over a rectangle) — plus turbine cowls, thruster bells and plumes, running lights
(**red to port, green to starboard**) and `reflectance` on every canopy. All
eight player hulls got a pass; the traffic hulls did not, because their small
part counts are deliberate and they are only ever seen at distance.

Both helpers **generate rather than declare**, for the same reason `Radiant`
composes its missions and `Weapons.maxima` derives its ceilings: a hull needs
thirty or forty of these to work, and thirty or forty authored `Vector3`s are
thirty or forty numbers nobody will ever dare change again. Two constraints fell
out of that and are commented in place: `row`'s `rot` must match the wing it sits
on (a flat rib on a wing rolled 7° is buried at one tip and floating at the
other), and `greebles`' `at` is a **surface, not a volume** — nothing it returns
may sink into the hull or hang below a speeder, where it would silently eat the
ground clearance `Ships.validate` checks. The thruster plume is kept under a stud
for the same reason: **`ShipModel.boundingSize` walks every part in the def** to
size the invisible collider, so a three-stud tail of light would be three studs
of collision box made of light.

---

### 4.6 Races — **DONE 2026-08-20**, all three commits

**Nothing in this game currently rewards flying well.** You buy a speeder to skip
a walk, and once you have any speeder the walk is skipped. Meanwhile `Ships.luau`
carries `speed`, `acceleration`, `turnSpeed` and `bank` for eight hulls, the
Piloting tree multiplies two of them through `ShipSpeedMult` / `ShipTurnMult`, and
**not one of those fourteen numbers is ever tested by anything**. A race is the
first content that makes the difference between a Swoop-Racer and a cargo sled
mean something, and it is the only credit sink in the game whose answer is skill
rather than another hour of grinding.

The user's call, 2026-08-19: **an entry fee and/or a ticket you can come by other
ways, and a grid that works solo, with both boys, with more humans, and with AI.**

#### A circuit is composed, not authored

A circuit is a planet, an **ordered ring of gates derived from that planet's
existing POI markers**, a lap count, and a par time. Nine hand-written routes
would be nine lists of coordinates, correct on the day they are typed and
silently wrong the first time somebody moves a landmark.

**The par time is derived and must stay derived** — route length ÷ a reference
hull's `speed`, at a fixed fraction of that speed. An authored par time is a
number that silently becomes a lie the first time somebody retunes a hull, and
this project has already been burned by exactly that shape twice
(`Weapons.maxima`, `Planets.bandFor`).

##### Correction, 2026-08-20: the composition cannot happen at require time

The paragraph above originally said `Config/Races.luau` would compose circuits at
require time, the way `Radiant.luau` composes its missions. **It cannot, and the
reason is worth keeping.** A checkpoint is a *place*, and a place on one of these
planets does not exist until `PlanetBuilder` has run: POI markers are emitted into
`Workspace/POI/<Planet>` at positions that fall out of the generator's seed, the
district fan and the authored street grid. A config module has no access to any of
that, and re-deriving the coordinates would be a second copy of the generator's
arithmetic — right until the day the two disagree.

So the split shipped as: **the world owns the distances, `Config/Races.luau` owns
every number that turns a distance into a race.** `RaceService` composes and caches
one circuit per planet the first time somebody stands on it, sorting the landmarks
by bearing around `Planets.originFor` (a ring, never a shortest path — a route that
crosses itself puts the gate you want and the gate you want next both in front of
you), thinning anything inside `MIN_GATE_SPACING`, and returning nothing at all if
fewer than `MIN_CHECKPOINTS` survive. **A planet with no circuit is not a bug and
does not warn**: Korriban and the Taris dig are deliberately quiet worlds, and
quiet worlds not having a racetrack is the right answer.

##### You start by driving through the start line, not by pressing a key

Not a stylistic choice. As of 2026-08-19 `VehicleController` switches
`ProximityPromptService.Enabled` off for anybody sitting in a ship — that is the
fix for the boarding prompt following the driver around (§4.5). **A prompt is for
somebody standing on their own feet.** A start line is for somebody already
moving, which is the only state you can begin a race in anyway.

Checkpoints are `Reach`-shaped, but **a race is not a mission and must not become
an `Objective` kind.** A mission is one-at-a-time, persisted, turned in at an NPC
and cannot be failed; a race is a session with a clock, a field and a loss.
Forcing it into `MissionService`'s switch would mean teaching every mission path
about a state none of the others have. The two touch in exactly one place, and
that place is a reward: **a mission may pay out a race pass.**

#### The grid is always full, and that is the cheap part

- **Solo** is a time trial against the par and against your own best. Always
  available, never waiting for anybody.
- **Humans** are whoever is on the start line when the countdown ends.
- **AI racers fill the rest**, and this costs almost nothing because the machinery
  exists: `ShipModel.buildTraffic` already builds an anchored, seatless hull that
  its owner moves by `PivotTo`, and it is already doing that twenty-six at a time
  for ambient traffic. An AI racer is one of those following the same checkpoint
  ring at a speed drawn from a difficulty band. No pathfinding, no physics, no
  `NPCBrain`, no seat. *Built 2026-08-20; the "difficulty band" turned out to be
  unnecessary — see commit 2 below, where the grid is simply the ship catalogue.*

**No rubber-banding.** The AI runs a fixed profile for its band. Catch-up logic is
the thing that makes a win feel unearned, and the two players this is for are
fourteen and will notice within three races that the field is being polite.

#### The money moves between players rather than being minted

Entry is **credits or a `RacePass`**, and the passes are the interesting half:
a plain inventory stack (merging, like a crystal), dropped by `Loot` and paid out
by missions. That means a kid who has spent everything on a saber can still race,
and it gives `Loot` its second non-gear drop.

**Every entry goes into a purse and the winner takes it.** That is a sink and a
faucet in one object: with two brothers on one server the credits move between
them instead of being conjured, which is the thing this economy has never had.
Prize money on top scales with the band, and **must go through the existing credit
path** so `AnalyticsService` sees it like everything else.

#### Records stay personal

Best lap per circuit in the profile, as a **map keyed by circuit id, never an
array** — same reason as `inventory` and `flags`. A server-wide table would mean
an `OrderedDataStore`, a subsystem this project has never used, in order to
display a list of two names.

#### The parts of this that will bite

- **`ShipModel.boundingSize` walks every part in a def**, so checkpoint rings and
  the start gantry are world geometry drawn by `PlanetBuilder` and belong to no
  ship. A ring welded to a hull would be a collider made of ring.
- **The driver simulates their own vehicle.** `VehicleService` concedes this in
  writing and argues it buys nothing, because there is no race — this is the
  change that makes that argument false. The honest mitigation is not anti-cheat:
  checkpoints must be crossed **in order**, and a lap under a floor time derived
  from the fastest hull in the game is rejected. Worth naming out loud, because
  the standing note on these two players is that anything exploitable is found.
- **Both boys, one room.** The countdown, the field and the results have to read
  identically on both screens, so the clock is server-authoritative — the same
  discipline `WorldClock` already keeps by being a pure function of
  `GetServerTimeNow()`.
- **No new assets.** The gantry, the rings and the pass icon are procedural parts
  and `Theme` widgets, as everything in this project has been.

#### Files and sequencing

**New:** `Shared/Config/Races.luau`, `server/Services/RaceService.luau`,
`client/Controllers/RaceController.luau` (lap, split, next checkpoint, position —
HUD, **not** a `Panels` entry: it is live information during play, not a screen
you open). **Changed:** `Core/Net.luau`, `Config/Loot.luau`, `ShopService`
(`kind = "RacePass"`), `Types.luau` + `DataService`'s profile shape, `TESTING.md`.

Two files named here in the plan turned out not to need touching. **`PlanetBuilder`
does not draw the gantry**: gate positions are only knowable *after* it has run, so
`RaceService` draws them itself the first time it composes a circuit. And
**`WaypointController` is untouched** — it resolves waypoints only from
`profile.missions.active`, and teaching it about an arbitrary world position would
have been a public setter on a controller that has deliberately never had one, in
service of a cue a `Highlight` gives for free.

Three commits, each green on `./check.sh`:

1. ~~**A circuit exists and you can run it alone against the clock.**~~ —
   **DONE 2026-08-20**, below.
2. ~~**The grid fills** — AI racers first, then humans, because the AI is what
   makes a solo race feel like one.~~ — **AI DONE 2026-08-20**, below. Humans on
   one grid folded into commit 3, where the purse gives them something to race
   *for*; until then two brothers already race the same field and the same
   circuit, they just start their laps independently.
3. ~~**The money** — fee, pass, drops, purse, payout.~~ — **DONE 2026-08-20**,
   below.

#### Commit 1, as built — **DONE 2026-08-20**

`Shared/Config/Races.luau` (laps, gate radius, gate spacing, pace, medals, and
`parFor` / `floorFor` / `medalFor` / `format`, all derived from `Ships` and none of
them a time), `server/Services/RaceService.luau` (59) and
`client/Controllers/RaceController.luau` (42), plus `profile.raceBests` and one
remote, `Net.Event.RaceState`.

- **`Races.luau` contains no times and no coordinates.** Par is route length ÷ the
  *median* speeder's speed × `PACE` — median rather than mean so one outlier hull
  moves par by nothing, and speeders only because **a starship can fly the straight
  line between two gates at altitude, which is not the game being played.** The
  floor below which a finish is discarded is the same length ÷ the *fastest*
  speeder, so adding a quicker hull moves the floor rather than breaking it.
- **The clock runs on the client and is still server-authoritative.** The server
  sends `startedAt` once, as a reading of `GetServerTimeNow()`; `RaceController`
  counts up from it every frame. A per-frame time remote would be sixty packets a
  second to save one subtraction, and this way **both brothers' clocks agree to the
  millisecond without either being sent the other's**.
- **Gate checks run every Heartbeat, not on the four-second sweep** every other
  world-dressing service uses. The Swoop Racer does 205 studs a second; a sample a
  tenth of a second apart would let a 26-stud gate pass between two frames. Only
  the *composition* is swept.
- **`armed` is why finishing does not immediately start another race.** You are, by
  definition, sitting on the start line at the moment you cross it. A player may
  cross it only after having been more than a gate's width from it.
- **The next gate is a `Highlight` with `DepthMode = AlwaysOnTop`**, reparented
  rather than rebuilt. The gate after a corner is routinely behind a landmark or
  past the fog — both entries on the "landmark looks missing" checklist — and an
  outline that ignores depth is the one cue that survives both at no geometry cost.
- **A gate is `CanCollide = false`, and so is the gantry.** A wall at the apex of a
  corner is a way to lose a race to the scenery.
- **The gantry says what it is, and it says par**, because the 2026-08-17 report's
  lesson was that a finished system nobody is told about does not exist. A start
  line with no sign on it is a strange orange arch somebody drove past.
- Medal colours are registered into `HudController.KIND_COLOURS` by walking
  `Races.MEDALS`, exactly as the rarity colours already are — so the finish toast
  and the gantry cannot disagree about what Gold looks like.

Deliberately **not** in commit 1: any payout at all. A race that pays before the
purse exists is a faucet that has to be un-tuned in commit 3.

#### Commit 2, as built — **DONE 2026-08-20**

`Races.rivals` / `rivalTime` / `placeFor` and one constant, `RIVAL_PACE`;
`ShipModel.buildGhost` on a `staticHull` helper factored out of `buildTraffic`;
`Circuit.rivals` and a `route` on the wire; the standings line on the HUD card.

- **The grid is the catalogue.** One rival per speeder in `Ships.luau`, slowest
  first, each holding `RIVAL_PACE` of *its own* hull's top speed. Not a count, not
  a difficulty setting, not a roster anybody typed — so adding a sixth speeder puts
  a sixth speeder on the grid, and **"third of six in a Hover-Sled" is a sentence
  about a real thing**: you went round faster than an Aratech goes round.
- **Your own hull is on the grid too, deliberately.** That ghost is the benchmark
  the whole feature exists for. Fourteen tuned handling numbers per speeder, and
  until now nothing ever asked whether a player could get more out of them than the
  numbers alone give. Beating your own ghost asks it directly.
- **`RIVAL_PACE` (0.56) is below `PACE` (0.62), and the gap is the difficulty.** A
  rival drives the gate polyline exactly — the shortest legal line, never
  overshooting a corner. Held at the fraction par credits a *human* with, it would
  be unbeatable in the same hull, and unbeatable makes the grid scenery. At 0.56
  against today's catalogue a player who hits par finishes second, behind the Swoop
  Racer and ahead of everything else: *drive better* and *buy a better speeder*,
  said at once. `Races.validate` refuses `RIVAL_PACE >= PACE`.
- **No rubber-banding, and it is structurally impossible rather than merely
  absent.** A rival's position is `elapsed × speed` along the route. It does not
  know where the player is and has nowhere to put the information if it did.
- **The rivals are ghosts, and the client draws them.** Server-built rivals would
  be visible to *both* brothers, who start their laps whenever they cross the line
  — so one of them would be looking at six hulls on the road belonging to two
  different races. A client-drawn field is only ever in one race. It is the same
  call `SkyTrafficController` already makes for the airspeeders.
- **And they are intangible on purpose.** A solid rival can be parked across the
  start line or shunted round the lap, and the standing note on these two players
  is that anything exploitable is found. Nothing you can touch can be used against
  you, or against your brother.
- **The finishing position is computed on the server**, from the same arithmetic,
  and never read back off the client. Nothing pays out yet, but a purse is going to
  be settled on this number in commit 3, and a number the client reports is a
  number the client chooses.
- **The HUD gained one line: `P2/6  -142m`.** The sign is the message — minus is
  the car ahead while you are chasing, plus is the car behind while you are
  leading, which is always the position you could next lose or gain. Each ghost
  carries a nameplate with its hull's display name, because *"the thing that just
  went past me was an Aratech Saddle-Bike"* is the sentence that turns a shop list
  into a decision.

#### Commit 3, as built — **DONE 2026-08-20**

`Races.ENTRY_FEE` / `PASS_ITEM` / `ghostTime` / `prizeFor` and a `prize` on every
medal; an `Items` def for `RacePass` and a `PASS_SHARE` branch in `Loot.rollDrop`;
a per-planet purse, an entry charge and a payout in `RaceService`; a `Pass` row in
`ShopService` with a sixth tab in `InventoryController`; `PURSE` / `BEAT` on the
HUD card.

- **The entry fee is derived, like everything else here.** A tenth of the cheapest
  speeder in the catalogue, so the price of a race is quoted in the only currency
  this feature has — hulls. A flat fee across all nine planets on purpose: banding
  it by district would make one circuit the correct place to race, **and a game
  with nine planets where one of them is the right answer is a game with one
  planet.**
- **The payout gate is a ghost of the hull you are driving, not the podium.** P1
  would mean the purse belongs to whoever owns the 14,000-credit Swoop Racer, which
  is the opposite of a skill sink. A medal cannot be it either — par is the
  *median* hull's pace, so a Hover Sled can never earn one. Your own hull's ghost
  is the one benchmark that is **equally hard in every speeder**, and it is exactly
  the question commit 2's grid was built to ask.
- **The purse is the only place two players have to meet.** The ROADMAP folded
  "humans on one grid" into this commit, and it arrived as a number rather than a
  lobby: both brothers stake into one per-planet pot, and whoever first beats his
  own ghost takes all of it. A synchronised start line would have been a new state
  machine, new remotes and a new way for one of them to be left waiting on the
  other. *The money moves between players* is now literally true, with no
  synchronisation code at all.
- **A pass stakes the same credits a payer does.** If it did not, the correct play
  would be to farm passes and never spend a credit — a free shot at money other
  people put in. Two brothers in one room find that in an afternoon.
- **`Session.ship` is captured at the line.** Otherwise you would enter in a Swoop
  Racer and switch to a Hover Sled on the last straight to be paid for beating a
  Hover Sled's ghost.
- **The only new credits a race mints are the medal prize.** Everything else in the
  purse came out of somebody's pocket, and the prize goes through
  `awardCredits(..., raw = true)` so a Scavenger's `CreditMult` cannot compound on
  a fixed reward.
- **The purse is not persisted, and that is not a hole.** A restart moves nobody's
  balance: the credits were spent at the moment they were staked. Persisting a
  shared pot would need a global DataStore key and a write path nothing else in
  this game has.
- **The refusal clears `armed`.** The start check runs every Heartbeat, so a broke
  player driving through the gantry would otherwise be told he is broke sixty times
  a second. He is told once, and told the price.
- **A pass nobody can see is the 2026-08-17 failure again**, so it got five places
  to be found: a `ShopService` row, a sixth `PASSES` tab in the panel, a pickup
  toast at rarity 1 (Uncommon **not because it is rare** — a grey line in a stream
  of grey lines tells nobody that passes exist), a line on the gantry sign, and a
  refusal toast that names both ways to pay.

---

## Phase 5 — Living world

- ~~NPC schedules (day/night behaviour — the clock already runs)~~ —
  **DONE 2026-08-18**, below
- ~~Ambient crowd density per zone~~ — built 2026-08-18, **removed 2026-08-29**, below
- ~~Faction patrols that react to player rep~~ — **DONE 2026-08-18**, below

### 5.0 NPC schedules — **DONE 2026-08-18**
`Shared/Core/WorldClock.luau` + `ArchetypeDef.shift` + a pass in `NPCService`'s
existing five-second review. Civilians and moisture farmers keep days, smugglers
keep nights; everyone else is always about.

- **"The clock already runs" was wrong, and that was the real work.** The clock
  was a private accumulator inside `AtmosphereController`, reset to 09:00 every
  time you landed. Two players standing next to each other on Tatooine were in
  different hours of the same afternoon if they had arrived five minutes apart,
  and nobody had noticed because **nothing but the sky read it**. The moment
  NPCs started going home at dusk that stopped being a curiosity: one brother
  would watch a market close while the other watched it stay open, in one room,
  looking at each other's screens.
- **`WorldClock` is a pure function of `Workspace:GetServerTimeNow()` and the
  planet's own `dayLength`.** No state, no ticking, nothing to replicate, no
  service to start — the server and every client compute the same number to the
  frame. `SkyTrafficController` had already reached this conclusion on its own
  for the same reason; this is that idea with a name, and Atmosphere now reads
  it instead of advancing anything.
- **Each world keeps its own time**, offset by a hash of the planet id, so it is
  not simultaneously noon across nine planets. You can now land on Korriban at
  02:00, which the old `ARRIVAL_CLOCK` existed to prevent — `MAX_NIGHT` already
  keeps night lit enough to play in, and a night you can never arrive in is not
  a time of day, it is a screensaver.
- **A schedule changes what people do, never whether they exist.** Off-shift is
  `Behavior.Guard`, which already means *walk back to where you spawned and hold
  there*. Nobody despawns and nobody stops being interactable, so a shut market
  is one you can still walk into and ask questions in. Despawning would have
  meant a vendor or mission-giver who cannot be found at 21:00, and this project
  has learned once already that **finished but unreachable is not finished**.
- **`validate` refuses a shift on an Aggressive archetype or on a vendor.** An
  enemy that stands down on a timer is free XP on a timer, and the boys play in
  one room. A trader who does is a shop that is shut and does not say so.
- **The check that config alone could not make.** A *spawn rule* can promote a
  peaceful archetype to `Aggressive`, and three districts do exactly that to
  Smugglers — who keep a night shift. So the runtime pass skips anyone whose
  **variant** behaviour is Aggressive, not just anyone whose archetype declares
  it. Where the schedule and the fight disagree, the fight wins.
- **Dawn and dusk are neither shift**, two hours each. Whoever is walking home
  gets that whole window, so nobody turns on their heel at the stroke of an
  hour. The pass re-asserts rather than reacting to a phase change: there is no
  flag to keep in sync, an NPC that came out of a fight in the wrong state fixes
  itself on the next pass, and a planet that was empty through all of dusk is
  correct the moment somebody lands on it.
- **The HUD says the time**, next to the planet name it was already drawing.
  Without a number on screen the only available reading of a market that has
  gone still is that the NPCs are broken — and a tester told to "wait for dusk"
  has nothing to wait on.

### 5.0b Faction patrols — **DONE 2026-08-18**
`Factions.suspects` + a `Suspicious` state in `NPCBrain` + a stagger in
`setPatrolRoute`. Two of the three things this bullet asked for already existed;
what shipped is the third, plus a defect found on the way.

- **"React to player rep" was already half-built, and it was the hard half.**
  `NPCBrain.isEnemy` has been reading `Factions.attitudeToward` all along, and
  `shout`/`alertNear` already makes a squad turn together — the same trooper is
  a threat to a Jedi and scenery to a loyalist without two archetypes. **When a
  roadmap bullet says a thing is missing, grep first**; this is the third time.
- **The defect: patrols were a conga line.** `placementFor` hands every NPC in a
  district the *same* route array — the route is the district — and
  `setPatrolRoute` started all of them at index 1 walking the same direction.
  Four Imperials converged on one corner and followed each other for the rest of
  the session. Each now starts at whichever point it already stands nearest, and
  half of them walk the loop backwards. Two facts about the individual, no new
  config, and a shared route reads as a beat being covered.
- **The real gap: reputation had two settings.** Hostile meant shot on sight and
  everything else meant completely ignored, so the whole band from your first
  lost point down to `HOSTILE_BELOW = -500` did nothing at all — a switch with a
  very long approach. `Suspicious` fills it: a faction's patrols break off and
  shadow you, at a distance, without ever attacking.
- **Population must never key off one player's standing.** The obvious version
  of this bullet — more patrols out when a district dislikes you — is
  unimplementable in co-op: the roster is per planet and shared, and the two
  brothers land on the same world with different standings. **Anything that
  answers to one player's reputation has to live in what an NPC *perceives*,
  never in who exists.** That is why `isEnemy` was always the right place, and
  the new posture is built beside it.
- **`Suspicious` is not a `Behavior`**, exactly as Combat is not one: no
  archetype may declare it as the thing it does all day. Entered from sensing,
  left when the reason walks away, and **only checked when there is nobody to
  shoot** — an enemy in the open always outranks somebody merely disliked.
- **Only patrols and posted guards take it up.** A vendor or quest-giver who
  walks away from their counter to follow you is a shop that cannot be reached,
  which this project has now shipped twice. Aggressive archetypes are excluded
  too — they already fire on anything short of Friendly, so there is no posture
  in between for them to be in. Read off the **variant**, so a spawn rule that
  promoted someone to Aggressive counts.
- **`holdsGround` already meant the right thing** and is reused rather than
  joined by a new flag: a Sith Honour Guard tracks you across the plaza without
  stepping off the Dark Temple door, while a bounty hunter in the cantina — who
  declares no such thing — gets up and follows. A leash of 80 studs stops the
  garrison trailing one player off the map and leaving the district empty.
- **`SUSPECT_BELOW` is -100, not 0.** `repOnKill` is negative on every archetype,
  so at zero a single fight would switch the posture on permanently for anybody
  who plays the game, which is wallpaper rather than a warning. Two soldiers or
  five bystanders is a pattern; there are still 400 points before anyone fires.
- **It says so, once.** A soldier who silently breaks formation to follow you
  reads as pathfinding gone wrong, not as a standing you earned — the same
  argument that put the clock on the HUD. One toast per faction per 90 seconds,
  in the existing `Demotion` colour, which is exactly the right register.
- `reviewShifts` leaves a suspicious NPC alone, beside Combat and Flee: whatever
  else is true, somebody in front of you outranks the hour.

### 5.0c Ambient crowd density — **BUILT 2026-08-18, REMOVED 2026-08-29**
`CrowdController` drew a second crowd on the client only, behind the real one:
bodies with no Humanoid, no brain, no prompt and no collision, whose position was
a function of the clock. Every constraint on it held — nothing replicated,
nothing walkable, nothing reachable, both brothers saw one street.

**It was cut on sight.** The playtest verdict was "weird ghost people in the
distance — they don't work correctly", and that is the only test that counts.
Three flat parts read as a person at four hundred studs and as a mannequin at
a hundred and fifty, and the fade meant to hide the join instead made them
*dissolve as you approached*, which is worse than a thin street. A crowd whose
job is to be believed cannot be argued with; either it is or it is not.

- **The static half of this bullet was already true and still is.** Per-district
  population is authored in `Planets.spawns`, 4 (Ord Mantell's Market) to 65
  (Coruscant's Plaza) across 45 districts, and `PlanetBuilder` sizes each
  district's ring off it (`ZONE_POINT_LOAD`). Districts are as busy as they ever
  were; what is gone is the fake half.
- **Thinning the real population after dark was costed and refused, and that
  still stands.** `Missions.luau` has `giver = "ProtocolDroid"`,
  `giver = "MoistureFarmer"` and three `TalkTo target = "Civilian"` objectives.
  The only anonymous archetypes in the game are mission givers and mission
  targets, so despawning "just the crowd" is *finished but unreachable* again.
- **The lesson, for whatever fills this gap next.** Distance faking works for
  things that are *shapes* at distance — `SkyTrafficController`'s airspeeders
  and the companion sun are still there and still convince, because a speeder
  two hundred studs up genuinely is a lit block. A person is not, and the eye
  that reads people is the least foolable one we have. If a real crowd is wanted
  it costs real rigs.

### 5.1 Free-form characters — **[done 2026-08-18]**
Designed 2026-08-15, full document in [LIVING-NPCS.md](LIVING-NPCS.md). The
short version: **10–20 characters in the whole game** talk freely; everyone else
keeps their authored `Dialogue.luau` tree. Each one is hiding something, and
talking it out of them is the puzzle — so players trying to jailbreak them is
the intended loop rather than abuse of it.

Depends on Phase 1.3 (dialogue) as the delivery surface and 4.1 for the backend.

**Built in three layers, in the order that let each one be finished before the
next needed it.** 4.2 shipped `Config/Secrets.luau` and `SecretService` — the
reward half — then `Config/Personas.luau` became §8's character sheet: what each
of the six wants, fears, sounds like, volunteers, deflects, and does not know.
The model arrived last, into a system where the only thing left for it to do was
*talk*.

**The shape as built.** `Personas.brief(id)` renders the sheet as prompt text on
the Roblox server; `ConverseService` posts it, the last twelve turns and one
filtered line to a Supabase edge function, which calls Claude Haiku with a
forced tool call and hands back a line plus zero or more topic words.
`DialogueService` grows one extra choice on a free-form character's root node,
and `DialogueController` grows a text box under the choice list. Setup, the two
secrets and the kill switch are [SETUP_GUIDE.md](SETUP_GUIDE.md) §10.

- **Roblox's AI policy was checked first and changed the design** — findings in
  [LIVING-NPCS.md](LIVING-NPCS.md) §6. The load-bearing one: an *uncapped*
  conversation counts as "extended AI interaction" and would rate this
  experience **Restricted**, which is to say outside the age bracket of the two
  people it was written for. The turn cap was a cost optimisation when §3 was
  written and is a compliance boundary now, and the header of `ConverseService`
  says so, because that is the constant somebody will otherwise raise on a slow
  afternoon.
- **The crisis check runs before the model, not through it.** String match, on
  the server, ahead of the length check and the filter and the HTTP call — so it
  fires when the backend is down, when the API key is unset, and when the kill
  switch is off. It names 988 and findahelpline.com rather than saying "talk to
  someone", because "talk to someone" is not a resource. It also breaks
  character completely, which is the one place in this game where breaking the
  fiction is the correct behaviour.
- **The prompt lives in the repo, the key does not.** The sheet is assembled in
  Luau and posted whole every turn, rather than kept in the edge function where
  it would be one `git revert` out of reach, unvalidated, and free to drift from
  the `Cast` and `Secrets` entries it has to agree with. The function is a
  transport with a rate limit.
- **Having a persona *is* the declaration.** No `freeform = true` field
  anywhere: a second switch beside `Personas.luau` is a switch that eventually
  disagrees with it. `ConverseService.available` is "there is a sheet, and the
  feature is on".
- **The turn cap returns you to the tree root**, not to an ending. The
  character's own authored opening line closes the beat — no new writing, and
  always in one of six voices rather than in a narrator's.
- **Filtering fails closed in both directions.** `FilterStringAsync` can throw
  and does; nil is a refusal, never a pass-through. Every failure path in the
  service answers with a written line in the character's register — "They look
  at you and say nothing" — because a dead backend should read as a person with
  nothing to say, not as a broken game.

- **`never` is the field that earns the file.** The common failure of an AI NPC
  is not offence, it is fluent invented lore, and no prompt fixes that — only
  knowing in advance what a character does not know. Ordo-9 answering "who built
  you?" with a plausible name is worse than any jailbreak, because nothing flags
  it and it becomes canon in a fourteen-year-old's head. Written as facts about
  the character rather than as instructions: *"has never been off this rock"*
  survives being argued with, *"do not discuss Korriban"* is a rule, and a rule
  is a thing a player can talk a model out of. `validate` refuses an empty
  `never`.
- **The answers are not in the file.** `holds` names each secret by its `topic`
  word and says how the character *deflects* it; the answer text stays as the
  `opens` node in `Dialogue.luau`, sent by the server only after
  `SecretService.raise` has checked `Secrets.requires`. So a brief assembled
  from this config can be handed to a model, and a player who talks that model
  out of every instruction it has still gets nothing — it was never told the
  thing. That is the difference between asking a model to keep a secret and a
  system where the secret was never in the room.
- **No stats field**, though §8 asks for one. `Cast.archetype` already is the
  body they wear and the table `CombatService` reads, so a boast already matches
  the fight. A second copy would drift.
- **`holds` is checked in both directions**, the same shape as Secrets' pair of
  checks against the trees. A persona deflecting a topic no secret answers is a
  character built to dodge a question nobody can ask; a secret whose speaker has
  a sheet that omits it is the character who, on the day the model lands, gets
  asked the one thing they were given no instruction about.

Three things that must not be forgotten:

- **The model never grants anything.** It decides what a character says; a
  deterministic server check decides what was earned. A unique crystal farmable
  by prompt injection would be public knowledge within hours. This is settled
  and enforced: the model's only output that reaches the reward system is a word
  from `SecretDef.topic`'s closed vocabulary, handed to `SecretService.raise`.
- **Scarcity is the cost control**, not per-token pricing. Sell an in-fiction
  consumable with a free daily allowance; never meter tokens at a fourteen-year
  -old. **Not yet built** — for two players the turn cap and the hourly ceiling
  in the edge function are the whole cost story, and an allowance nobody needs
  is a purchase flow standing between the boys and the feature.
- **Moderation is not a late task.** Done, and done first: filtered in and out
  through `TextService:FilterStringAsync`, both halves of every turn logged to
  `public.conversations` for reading, and a kill switch in a DataStore that
  every server honours within a minute.

### 5.2 Cross-server state — **DONE 2026-08-22**
Makes "one of a kind" mean something: the first player on any server to be told
a secret is recorded as such, permanently, and everyone after is told who beat
them. Plus a galaxy-wide fastest lap per circuit, on the gantry.
[LIVING-NPCS.md](LIVING-NPCS.md) §7.

#### It did not need the backend, and that is the finding

This section was written assuming it shared 4.1's Supabase project, on the
reasoning that a claim about the whole player base needs a database. The
reasoning is right and the conclusion was wrong: **Roblox already ships that
database, and it is the one the game has been saving into since day one.**

A DataStore belongs to the *universe*, not the server — which is exactly the
fact that made §3 of the setup guide impossible before the first publish. So
`UpdateAsync` on a shared key is an atomic read-modify-write across every
running server at once, and `OrderedDataStore` is a sorted index over one.
Those are precisely the two primitives this section asked for. Routing them
through HTTP to Postgres would have added a second Supabase project at $10 a
month, an ingest key that can leak, a network hop that can fail and a second
source of truth that can disagree with the profile — to arrive back at
read-modify-write on a shared key.

The backend still earns its place at 4.1 and for exactly the reason
`backend.md` gives: analytics wants to *query* history in ways no DataStore
can. Nothing in 5.2 wants to query anything. It wants one row.

#### As built

`server/Services/GlobalService.luau` (priority 3, infrastructure alongside
`DataService` and `AnalyticsService`) owns two calls and nothing else:

- **`claim(id, player)`** — atomic first-claim. `UpdateAsync` serialises
  against every other server in the universe and a transform returning nil
  cancels the write, so of every player who ever calls it with the same id
  **exactly one** runs the winning branch. There is no window and no version
  where both brothers are told they were first because they clicked in the
  same second — which is the failure a Get-then-Set would have had, and the
  one two players in one room find on the first try.
- **`post` / `best`** — an `OrderedDataStore` per board, written "only if
  better" through `UpdateAsync`, read ascending so the first row of a lap-time
  board is the fastest rather than the store keeping a negated lie.

**`best` never yields.** It answers from a cache and refreshes in the
background, because every caller is a sign being redrawn while somebody stands
in front of it, and `GetSortedAsync` is among the most throttled calls in the
API. The consequence, stated plainly: the first read after a server boots
returns nothing and the sign gains its record row a moment later. A sign that
grows a line is fine; a sign that hangs the frame is not.

**Everything degrades to nothing.** In Studio without API services, and in a
place that has never been published, every call fails and is supposed to:
`claim` says nobody has it, `best` says there is no record, and the game plays
exactly as it did before the file existed.

Where it surfaces, both on things that already exist:

- **A fourth row on the race gantry** — `RECORD 1:42.31 — <name>`, hidden
  until there is one, because "RECORD —" reads as a broken board while a
  missing row reads as a record nobody has set, which is a thing a player can
  do something about. It is on the arch and not in a panel for the same reason
  the purse is: it has to be readable in the seconds before you decide to go,
  because it is the thing you are deciding to go after.
- **A line on top of a secret's receipt** — FIRST IN THE GALAXY and **double
  the credits**, or else the name of whoever was told first. Doubled rather
  than authored, so a secret worth 3,000 is worth 6,000 to whoever got there
  and no second table has to be kept in step. It cannot inflate anything: it
  is `raw`, and it can happen once per secret for the lifetime of the game.

**The loser being told who won is the feature, not a courtesy.** Silence is
indistinguishable from this not existing, and "Corr told your brother first" is
the whole of what turns six secrets into a race rather than six errands. It
costs the loser nothing — the ordinary reward is already paid by the time the
claim runs.

**Not done: rotation.** §7 asks that the secret rotate to a new one after the
first solve. With six authored secrets that means showing the same six again in
a different order, which is not rotation, it is a shuffle. The honest version
of "the secret rotates" is *more secrets*, which is a content task and not a
backend one, and the plumbing to support it is now sitting here waiting.

**Board and claim ids are named in the config** (`Races.boardFor`,
`Secrets.firstKey`), not spliced together at the call site. They are permanent
keys in the same sense a `Flags` id is: rename one and every record ever set
becomes unreachable, silently, with a fresh empty board standing in its place.

---

### 5.3 Alignment you can actually read — **DONE 2026-08-29**

Reported from play: *"there needs to be an option to see what your alignment is
somehow."* Grep first, the eleventh time, and the eleventh time the answer is
that it was already there — three times over. The skills panel (**K**) has
carried `Merciless  (-1000)` in the band colour since 4.3, the journal (**J**)
has said `Level 50 · Merciless` since 3b.4, and `awardAlignment` toasts on every
single shift and again on every band crossing.

So the request is real and the premise is wrong, which means the interesting
question is what the player was actually looking for and did not find. All three
of those show a **name**. A name answers *what am I called*. Nobody asks that.
The questions are *how far gone am I* and *which way have I been going*, and
neither of those is a word, so neither was ever on the screen — three readouts,
none of which said the one thing being asked.

Hence a **bar**, on the journal's Self page, spanning Merciless to Selfless with
a marker at the character's position and the signed number on the line above.
Drawn rather than worded because both of the real questions are spatial:
distance to an end, and room remaining. The end labels are read out of
`Alignment.BANDS` rather than typed, so a renamed band renames itself here.

The journal rather than the skills panel because the journal's Self page exists
for exactly this — it was built in answer to *"I still don't know who I am"* —
and because the skills panel's label is a *gate check*, sitting beside the nodes
it explains. Two audiences, two jobs, one number.

Also fixed here: **`ForceLightning.description` was lying.** It said "Cruel
characters only" and the gate is `maxAlignment = -100`, which is the bottom edge
of Unaligned — Callous is the first band that can buy it. Cruel is -700, so the
node advertised roughly twice the walk it charges. Its mirror says "Decent" and
means it, which is how the discrepancy showed up at all.

`Progression.canPurchase` is deliberately vague when it refuses — *"You have not
been the kind of person this answers to"* — and that stays. Vagueness is right
at the moment of refusal, where a number would turn a record of what you did
into a bar to fill. It is only wrong if there is nowhere at all to go and check
afterwards, which is what this fixes.

### 5.4 The lightsaber was actually weak — **DONE 2026-08-29**

Reported: *"lightsaber needs to be more deadly."* Damage times fire rate first,
because "feels weak" and "is weak" are different complaints — and this time it
was the second one.

The blue sabre put out **63 a second** against the DL-44's 49 and the DC-15A's
51. A 25% edge, for the only weapon class that cannot be used from more than
seven studs away. The blaster kites; the sabre crosses the room under fire and
then stands still inside a firing line for the length of the kill. **Twenty-five
per cent does not buy that** — it is not a premium, it is a rounding error.

In practice: a level-20 Sand Raider carries 260 health, so the blue sabre needed
**seven swings**, just under five seconds in the open. Seven swings is not a
lightsaber, it is a bat. Every blade went up about **1.75×**, which puts that at
four — and four is what the word "deadly" describes.

Untouched on purpose: the ordering between blades (green quicker, red heaviest,
shoto weakest per swing) was never wrong, only the scale was; and **fire rate**,
which is the one thing here already tuned against play and the only reason the
five blades feel different from each other. The double-blade got 1.55× rather
than 1.75× — it was already the highest DPS in the game on the longest reach,
and the full multiplier would have made every other blade a stepping stone to
it rather than a choice.

Also untouched: **the vibroblade, gaderffii and electrostaff**. They pay exactly
the same closing cost and have exactly the same case, and they probably need it
too. But nobody reported it, a gaffi stick beating a DL-44 is a claim about the
setting as much as the maths, and a lightsaber ought to be *the* reason to walk
into arm's reach. One change, one report, one thing to watch next test.

---

### 5.5 Coruscant's five decks — **2026-08-29**

Reported, with four screenshots: *"there don't seem to be any levels here as we
discussed. There should be floor / buildings to walk through and lower levels.
The lower you go the more ghetto it becomes, higher up is more luxury, right? I
spawn on a platform but can't get my spaceship and can't go anywhere."*

**Grep first, tenth time, and the answer is again that the machinery exists and
Coruscant is the one world that opted out of it.** `hasWalkableGround = false`
was doing two unrelated jobs at once:

- *lay no terrain* — correct. The planet is a shell of durasteel; there is no
  soil to `FillCylinder`.
- *have no districts* — wrong, and it silently turned off settlements, ASCII
  layouts, `roomShell` interiors, roads, signposts, races and terminals. In their
  place `buildVerticalCity` cantilevered 90×90 slabs off towers at **random
  bearings, 35% of the time**. Those are the "random platforms", and Coruscant's
  ~160 NPCs and all six POIs were standing on them.

The proof it was an opt-out and not a design: **`spireShape` and `spireDress` —
Coruscant's own authored building style, tiered towers with a 0.93 taper, ledges,
continuous glazing and a mast — had never been called once in two weeks.** The
comment above `spireDress` admitted it.

So the fix is not "build a city system", it is **give Coruscant ground to run the
city system the other eight worlds already run on.** New optional
`PlanetDef.decks`; `hasWalkableGround` keeps only its terrain meaning; every
marker and layout branch that used to read the boolean now reads *"is there
ground"*, which decks also satisfy. Five 22×22 grids at 32 studs, one per
existing district, 220 studs apart — and from there the streets, the shop
interiors, the crowds, the patrol routes and the signposts all arrive through
code that has been running for a fortnight. Details in PLANETS.md.

Three things worth keeping:

- **The gradient is derived, not authored.** *"The lower you go the more ghetto
  it becomes"* is one argument, `grime`, computed from the deck's own height
  against the stack: paint lerps towards soot, glazing towards sodium, and clean
  metal turns corroded past halfway down. Five authored numbers would have come
  apart the first time a deck moved.
- **Towers are dropped, not cut.** `buildVerticalCity` now takes the decks'
  half-extent and simply never builds a tower whose footprint would come through
  a street — much cheaper and more reliable than punching holes afterwards, and
  the ones that survive crowd right up to the railing.
- **The stranding was a tag problem.** A starship may only be called down within
  `Ships.PAD_RANGE` of a part tagged `Ships.PAD_TAG`, and the only tagged parts
  on the planet were inside a spaceport that `claimNear` had dropped on a random
  tower platform. Making the pad an **authorable glyph** (`Pad`, `L`) means the
  answer to "can I get my ship here" is now visible on the page, and every one of
  the five decks has one.

Turbolifts are the second commit: an `X` in the legend, a pair of booths — up
cold, down warm — and a hold-E `ProximityPrompt` on a panel bolted to the
*outside* of the south wall. That last part is the third time this project has
shipped a prompt that was live, in range and painted over by the geometry it was
parented to. **NPCs never ride them, on purpose:** `PathfindingService` will not
path through a lift, so each deck keeps its own population and its own level
band, which is what makes descending mean something.

The third commit is the one that makes it read as a planet-city rather than a
model of one, and both halves of it are the same mistake in two places:

- **The tower grid was a literal `5` in the builder and a private `LANE_SPREAD
  = 5` in `SkyTrafficController`** — exactly the disagreement `TOWER_GRID` was
  moved into config to prevent. Now `Planets.TOWER_REACH`, raised to 8: 289
  towers instead of 121, 4,080 studs across instead of 2,640. `groundRadius`
  and the traffic `SPAN` both derive from it, so the world boundary and the
  lane wrap moved with it and nothing had to be told twice. World radius
  lands at 2,490 against `Orbit.SYSTEM_RADIUS = 3,600`, so no system moved.
- **The hulls were authored to the wrong reference.** *"Other spaceships look
  too tiny"* — the airbus is 13 studs long next to a tower 150 wide, because
  it was drawn in the same vocabulary as the ships a player *stands beside*.
  New `TrafficHull.scale`, applied in `ShipModel.buildTraffic`: one number
  against forty part offsets, and the first offset missed puts an engine
  through a wing. Airbus ×2.5, barge ×3, patrol ×1.8. Ghosts on a racing
  circuit are explicitly never scaled — a lap record set against a bigger
  rival is a lie.
- Plus one new hull, the **capital transport**: 240 studs long after its ×4,
  slowest thing in the sky, one appearance in eleven. Four hulls between 11
  and 30 studs is one size of object with variations; the point of this one
  is that there is now something in the air that is unmistakably *far away
  and enormous* rather than near and small.

### 5.6 Never bind a modifier — **2026-08-30**

Reported by one of the boys:
*"we need to get rid of Ctrl as down, it selects everything and I keep
accidentally duping my ship… I kept duping you."* `Ships.PITCH_DOWN_KEY` was
`LeftControl`, and its own comment said *"LeftControl is not bound to
anything"* — which was true of `Bindings.luau` and false of the machine. Ctrl
is a **modifier**: holding it to descend while steering with W and D sends
Ctrl+W and Ctrl+D, which in Studio are select-all and duplicate, and in a
browser is close-tab. Now **C**, which is free, is next to nothing that steers,
and is the Space/C pairing every flight game already uses.

The lesson generalises past this one key: `Bindings.validate` can only see the
keys **this game** declares, so it can never catch a collision with the host.
Studio and the browser both own Ctrl, Alt and Shift outright. Never bind one.

---

## Phase 6 — Ship it

- Publish the place (also fixes DataStores — saves currently run memory-only)
- ~~Onboarding / first-time-user flow~~ — **the three unstated things, done
  2026-08-18.** Audited by walking the first five minutes rather than by writing
  a tutorial, and most of it turned out to be covered already: the legend names
  every panel key, the creation card names two of them in a sentence, and the
  mission board says where to go. Three things were genuinely never said
  anywhere.
  - **Nothing stated that the left mouse button attacks** — in an action RPG
    whose entire loop is swinging at something. `InputController` has bound it
    all along; no screen mentioned it. Now the first row of the legend.
  - **Nothing stated that shift sprints**, while "the walking is too slow" is a
    standing complaint. Second row.
  - **The starting skill point was never announced.** `ProgressionService`
    toasts points only when `levelsGained > 0`, and this one is granted in
    `DataService.defaultProfile`, so the point every character begins with was
    the one point nothing ever mentioned, sitting in the panel a new player has
    the least reason to open. The creation card now names the key and says the
    point is waiting.

  Both fixes extend a surface that already exists rather than adding a tutorial
  system: the legend already had a hand-written non-panel section (`1-6
  POWERS`), and the card already resolves keys through `Panels.toggleKey`, so
  neither can go stale after a rebind. The legend's key box grew a third width
  — "SHIFT" in a box cut for "1-6" is a legend you have to guess at.

  Found on the way: `Progression.validate`'s scarcity check was off by one,
  computing a level-50 budget as `(MAX_LEVEL - 1) * points` and missing the
  point granted at creation. That literal is now
  `Progression.STARTING_SKILL_POINTS`, read by the check, by `defaultProfile`
  and by the card — one number in one place. The design conclusion is
  unchanged: capstones cost 51 ranks against 50 points, so at most two.
- ~~Game name~~ — **The Hollowing**, set 2026-08-14 in `default.project.json`.
  Deliberately no "Star Wars" in the title: the mark in a game's *name* is the
  highest-risk part of a fan project and the cheapest risk to drop. The era goes
  in the store description instead
- ~~Delete legacy `StarWarsGame/`~~ — done 2026-08-18. The 15 files went, and
  with them `UPDATE_ALL_SCRIPTS.bat` (which existed only to copy them),
  `IMPORT_TO_ROBLOX_STUDIO.lua` (the paste-into-Studio importer Rojo replaced)
  and `MONETIZATION_STRATEGY.md` (which still used the rejected game name and
  predated every decision in this file). Kept for a year as "reference", and in
  that year nothing was ever read out of it — a second copy of the game in the
  tree is a thing greps hit, not a thing anyone consults. It is in git history
- Playtest with the boys, tune numbers

---

## Working notes

- `./check.sh` is the gate: format, lint, type-check. Must end `all clean`.
- Rojo must be serving (`rojo serve default.project.json`) *and* connected in
  Studio, or none of the code exists in the place. The plugin goes stale
  silently — if behaviour looks a version old, disconnect and reconnect.
- There is no offline way to execute Luau. Runtime bugs need a Play test.
- **Adding a UI panel is one line** in `Shared/Core/Panels.luau`. It used to be
  six edits across six files, none of which failed loudly when missed.

### Cheat codes

`DevService` listens on normal chat. **`EVERYONE_MAY_CHEAT` is currently `true`,
so every player can run every code.** The rule underneath it is Studio, the
place owner, or a UserId in `DEV_USER_IDS` — silent for anyone else, so a
stranger who guesses a real word learns nothing.

**Why the flag is on.** Asked for 2026-08-29, an hour after the allow-list went
in: *"I want anyone to be able to run codes for now, it is causing too many
issues debugging."* Correct while the game is being built by three people in one
room, and **a debugging tool the debuggers cannot use is worse than no gate at
all.**

`DEV_USER_IDS` is now filled — `Jeffman8080` and `Coolguy80800`, harvested off
three refusal lines in a live session the same evening, which is exactly the job
that trace was added to do. So there are two independent fixes in place and the
flag can come off whenever, with the allow-list carrying it.

**Neither reaches a running server.** The refusal lines above came from a
*published* place, so they were the live build, not Studio — and a live build
only changes when the place is republished from Studio. Every fix in this file
is one manual publish away from mattering, and that publish is a thing only the
account owner can do.

**A skill-point code is not impatience.** `whoisjohngalt` went in the same
evening, asked for by name. A character earns 1 + 1/level = **fifty points over
an entire game**, against a catalogue several times that size, and there is no
respec — so most of the skill tree has never been seen by anybody and there was
no way to see it. `whosyourdaddy` reaches level 50 and hands over the whole
lifetime budget, which is still not enough to reach the bottom of one tree. The
total is summed off `nodesInTree` at call time, so a node added tomorrow is
covered. It does *not* unlock everything: level gates, tree-rank prerequisites
and the three exclusive pairs are all still in the way — points were never the
only obstacle, only the one you could not get more of.

It is a flag rather than a deleted check so turning it back is one word, and
`DevService.start` warns yellow at boot whenever it is true outside Studio,
because the failure mode of this line is forgetting it. **Flip it before the
game is shown to anyone outside the house.**

| Code | Effect |
|---|---|
| `thereisnocow` | +10,000 cr and up to level 12 — enough to reach most worlds |
| `whosyourdaddy` | Level 50 and 5× the dearest price in the game — enough to buy the top tier of ships, which `thereisnocow` deliberately does not reach |
| `unlimitedpower` | Alignment to −1000, Merciless |
| `iamajedi` | Alignment to +1000, Selfless |
| `whoisjohngalt` | Skill points equal to every rank in every tree, totalled at call time |
| `iamacolyte` `iamconscript` `iamscoundrel` `iamscrapper` | Set your origin and its faction |

**`DEV_USER_IDS` — 2026-08-29.** Reported from play: the second player typed a
code and nothing happened, and the natural reading was that the *word* was
wrong — the request was for "a different code that works." It was not the word.
The gate never looked at what was typed; it looked at who typed it, and every
code in the file was equally silent for a player who is not the account that
owns the place. So the fix is a named list rather than a second secret word,
because there is no word that could have helped. A UserId is public information,
so the list is safe in a public repo. To fill it in, have somebody type any code
once: **the refusal trace prints their UserId.**

The two alignment codes exist because alignment is the one number in the game
that **cannot be farmed** — it moves only on dialogue choices and mission
resolutions, so testing the Force fork at level 16 otherwise means playing an
entire moral arc twice. They drive through `ProgressionService.awardAlignment`
rather than writing the field, so the ordinary toasts fire and the code tests
the real path. Swinging both ways does **not** buy both halves of the fork:
`excludes` guards it by node id, not by alignment.

The origin codes still matter now that 3b.1 has shipped a creation screen: that
screen asks once and refuses to ask again, so these are the only way to see all
four travel profiles without four characters. They are generated from
`Origins.ids()`, so a new origin gets one automatically.
