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
than at the moment someone flies there. Coruscant's `Spire` is declared but not
drawn: `hasWalkableGround = false` sends it down the vertical-city path.

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
things roads lead to are the Reach objectives. Still open: vehicles, and the
vertical-city case, which is the harder half of this item.

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
galaxy is now drawn.** Eight grids; **Coruscant is the one planet that should
not get one**, since `hasWalkableGround = false` genuinely sends it down
`buildVerticalCity`. The last three were each drawn around a single sentence the
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

`TrackMission` was left unimplemented on purpose: the HUD already renders *every*
active mission (`HudController.luau:260`), so a single tracked mission is not a
concept the game has.

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

### 2b. Ship classes
Proposed `Config/Ships.luau`, same shape as `Weapons.luau` — stats as data,
geometry procedural via a `ShipBuilder` mirroring `RigBuilder`.

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

### 2c. Flight and interiors
- Flight controller, hangar spawn/despawn, landing pads at existing Hangar POIs
- Ship interior customization (your note)
- NPC ships flying over Coruscant (your note)

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

### 3.2 The eight worlds — **[layouts done 2026-08-17; named prefabs still todo]**
Contents specified per planet in [PLANETS.md](PLANETS.md) §3. Build order was
depth-first: **Tatooine completely** as the vertical slice, then extract the
layout system from what that taught, then Korriban, then the rest. That is what
happened, and **every walkable world now has an authored grid with banded
districts** (see §N5 for the eight of them and what each one was drawn around).

What is left here is the *other* half of the item: **named, unique prefabs**.
Today a grid cell hands a footprint to the planet's own `style.shape`, which is
why one legend works on nine worlds — but it also means Anchorhead's cantina and
Kaas City's antechambers are the same box in different colours. The per-planet
prefab vocabularies in PLANETS.md §3 (`MoistureVaporator`, `HullSection`,
`CitadelSpire`…) are all still unbuilt, and they are what would make a place
recognisable rather than merely legible.

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
- Weapon mods / attachments layered onto `Config/Weapons.luau`
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

### 4.1 Analytics — **[todo]**
The cheapest item on this roadmap that measurably improves the game, and the
only one that makes every later balance decision better informed. Right now
every number in `Config/` was picked by feel and nothing reports back: we do not
know which missions get abandoned, where players die, or what they actually buy.

A Roblox server posting events to an HTTP endpoint, and Postgres behind it. No
dependency on anything else in Phase 4 or 5 — it can ship the day someone wants
it. Design and the backend shape are in [LIVING-NPCS.md](LIVING-NPCS.md) §5,
because analytics and the conversation feature share one backend.

### 4.2 Secret unlock conditions — **[todo]**
Ordinary Luau config declaring "this reward is granted when the server sees
these conditions," with a `validate()` pass like `Missions.luau` has. Works
against authored dialogue on day one and needs no backend.

Worth building before the free-form layer rather than with it: it is the half
that must be deterministic and testable, and doing it first means the model,
when it arrives, is only a text generator bolted onto a reward system that
already works. See [LIVING-NPCS.md](LIVING-NPCS.md) §2.

---

## Phase 5 — Living world

- NPC schedules (day/night behaviour — the clock already runs)
- Ambient crowd density per zone
- Faction patrols that react to player rep

### 5.1 Free-form characters — **[todo]**
Designed 2026-08-15, full document in [LIVING-NPCS.md](LIVING-NPCS.md). The
short version: **10–20 characters in the whole game** talk freely; everyone else
keeps their authored `Dialogue.luau` tree. Each one is hiding something, and
talking it out of them is the puzzle — so players trying to jailbreak them is
the intended loop rather than abuse of it.

Depends on Phase 1.3 (dialogue) as the delivery surface, 4.1 for the backend and
4.2 for the reward half. Three things that must not be forgotten:

- **The model never grants anything.** It decides what a character says; a
  deterministic server check decides what was earned. A unique crystal farmable
  by prompt injection would be public knowledge within hours.
- **Scarcity is the cost control**, not per-token pricing. Sell an in-fiction
  consumable with a free daily allowance; never meter tokens at a fourteen-year
  -old.
- **Moderation is not a late task.** Filter in and out through
  `TextService:FilterStringAsync`, keep a kill switch back to authored trees,
  and read Roblox's current AI policy before building — it governs whether this
  is publishable at all.

### 5.2 Cross-server state — **[todo]**
Same backend as 4.1. Makes "one of a kind" mean something: the first player on
any server to crack a secret gets the unique version and the secret rotates.
Also where a galaxy-wide war state, leaderboards or a shared economy would live.
[LIVING-NPCS.md](LIVING-NPCS.md) §7.

---

## Phase 6 — Ship it

- Publish the place (also fixes DataStores — saves currently run memory-only)
- Onboarding / first-time-user flow
- ~~Game name~~ — **The Hollowing**, set 2026-08-14 in `default.project.json`.
  Deliberately no "Star Wars" in the title: the mark in a game's *name* is the
  highest-risk part of a fan project and the cheapest risk to drop. The era goes
  in the store description instead
- Delete legacy `StarWarsGame/`
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

`DevService` listens on normal chat. **Studio or the place owner only** — silent
for anyone else, so a stranger who guesses a real word learns nothing.

| Code | Effect |
|---|---|
| `thereisnocow` | +10,000 cr and up to level 12 — enough to reach most worlds |
| `iamacolyte` `iamconscript` `iamscoundrel` `iamscrapper` | Set your origin and its faction |

The origin codes still matter now that 3b.1 has shipped a creation screen: that
screen asks once and refuses to ask again, so these are the only way to see all
four travel profiles without four characters. They are generated from
`Origins.ids()`, so a new origin gets one automatically.
