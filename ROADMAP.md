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
generator in nine colours (Phase 3), and that the character you are has no
moment where you choose it (Phase 3b.1).

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
faction drives it, which is also finally a *reader* for faction reputation
(currently written and never read — a standing gap).

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

Still open: ordinary settlement buildings are still solid, and shops, tombs and
apartments have no interiors. Neither needs new machinery — `roundWall` and
`roomShell` plus an `interior` offset is the whole pattern.

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
| Scoundrel | Piloting | Nar Shaddaa | bought passage | never | ×0.6 | 20 s |
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

**Not yet choosable.** `DataService.defaultProfile` assigns `Origins.DEFAULT`
("Scoundrel") to everyone, and `migrate` repairs any profile whose origin is
missing or renamed. Until 3b.1 ships a creation screen, every character travels
on Scoundrel terms — the differences are built and tested but invisible.

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

- Each planet is a **3000 x 3000 stud** slab (`PlanetBuilder.luau:39`) — roughly
  840 m square, ~3 minutes to walk corner to corner at default walkspeed.
- The town is a radial grid of 130-stud blocks out to a **520-stud radius**
  (`:42-44`) — about 65 seconds across. That is ~12% of the map area.
- Everything beyond radius 610 is empty ground with scattered boulders.

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

### 3.1 The layout system — **[todo]**
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

### 3.2 The eight worlds — **[todo]**
Contents specified per planet in [PLANETS.md](PLANETS.md) §3. Build order is
depth-first: **Tatooine completely** (layout, ~12 prefabs, banded districts,
Act 1) as the vertical slice, then extract the layout system from what that
taught, then Korriban, then the rest.

The structural win: **four planets are both an origin world and a later act** —
Korriban, Taris, Nar Shaddaa and Coruscant. That halves the worlds needing a high
finish and buys the best beat in any RPG for free, which is returning at level 40
to the district that nearly killed you at level 3.

**Travel is a hard dependency from the second planet onward** — satisfied by
Phase 2a, so this is no longer blocked.

---

## Phase 3b — The campaign

The story, specified in [CAMPAIGN.md](CAMPAIGN.md). Mostly content, but four
small system changes have to land first.

### 3b.1 Origin — **[partly done]**
`PlayerProfile.origin` and `Config/Origins.luau` landed with Phase 2a, which
needed them to price a jump. Still outstanding:
- a **creation screen** on the existing 760x470 panel convention — without it
  every character is silently `Origins.DEFAULT` and the four travel profiles are
  dead code
- an `origin: string?` field on `ObjectiveDef` and on the dialogue `Condition`.
  That is what makes four prologues affordable: one mission and one conversation
  can serve all four origins and say something different to each.
- the origin should also decide the **starting planet** (`Origins.homePlanet` is
  already declared and currently only used for flavour) and seed the first skill
  point into its `tree`.

### 3b.2 Alignment — **[todo]**
`PlayerProfile.alignment`, clamped -1000..1000, moved by dialogue and mission
resolution rather than by combat. Gates the deep Force nodes, the saber crystal
colours already sitting in `Weapons.luau`, and the endings. Deliberately
separate from `factionRep` — a Sith at +800 alignment is the interesting case.

### 3b.3 Acts, chapters and a journal — **[todo]**
Nearly free: `MissionDef` already has `requires`, `next`, `minLevel` and
`requiredRep`, and `boardFor` already respects all four. A campaign is a
correctly wired `requires` graph. Needs `MissionDef.act`, and a journal view —
the board is a to-do list, and a mystery needs a record of what happened.

### 3b.4 Flags — **[todo]**
`PlayerProfile.flags: { [string]: boolean }` plus a `flag` dialogue condition.
One field, and it is the whole of branching.

### 3b.5 Signature chains — **[todo]**
**A lightsaber is built, not bought** (decided 2026-08-14), which forced the same
for every other origin or the Acolyte would have the only good content. Four
five-part chains running levels 12–34, specified in [CAMPAIGN.md](CAMPAIGN.md)
§5: the saber, the Mandalorian Great Hunt, your own ship, and restoring Ordo-9.

This is the long-standing "what is the reason to specialize?" question finally
answered — not a bigger number at rank 5, but an object. It needs no new
machinery beyond `MissionDef.origin` from 3b.1 and `alignment` from 3b.2, which
is what determines the crystal's colour and gives `SaberBlue/Green/Purple/Red` a
meaning at last.

**Sabers come out of the shop tables.** `Weapons.luau` currently sells one at
level 10 for 7,500 credits; the vendor entry becomes a hilt component instead.

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

### 4.3 Skill trees, properly — **[todo]**
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
   `alignment` from 3b.2 — which is currently a value with almost nothing
   reading it. Lightning vs. healing is the oldest and best example in the
   setting, and it makes 3b.2 pay for itself.
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
| `iamacolyte` `iamconscript` `iamscoundrel` `iamscrapper` | Set your origin |

The origin codes are the ones that matter: until 3b.1 ships a creation screen
they are the only way to see that travel differs by background at all. They are
generated from `Origins.ids()`, so a new origin gets one automatically.
