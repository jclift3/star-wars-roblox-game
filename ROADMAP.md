# Roadmap

Where the game actually stands, and what has to happen to make it a game rather
than a sandbox. Ordered so that each phase produces something playable.

Status legend: **[done]** shipped · **[gap]** built but unreachable in-game ·
**[todo]** not written yet.

---

## The one-line summary

The systems are largely built. The *seams between them* are missing. A player
today can walk, shoot, buy, and level — but cannot accept a mission, talk to
anyone, or leave the planet. Phase 1 is almost entirely about connecting things
that already exist.

---

## Design direction — Diablo-style (decided 2026-08-14)

The target is an action-RPG loop: kill things, level, spend points, find better
gear, walk somewhere harder. Three consequences, in the order they should be
built:

1. **Skill tree screen** — **[done]**, see 1.5.
2. **Loot with rolled affixes.** The real Diablo loop. Blocked on a data-model
   change: `profile.inventory` is `{ [itemId]: count }`, a bag of counts, so it
   cannot hold two different rolls of the same blaster. That change gets more
   expensive with every system that reads inventory, so it should be made
   before the shop and mission systems grow.
3. **A large world banded by level.** Enemies of varying level, laid out so
   walking outward means walking into harder things. `ZoneDef.distance`
   (`Config/Planets.luau`) is already the difficulty dial — it needs a level
   band per zone, and a warning when the player crosses into one well above
   them rather than a silent death.

Also wanted, not required: **complementary co-op classes** — a Jedi and a
soldier who play differently and cover each other. The four skill trees
(Combat / Piloting / Force / Engineering) are already shaped for this; what is
missing is a reason to specialize, which means abilities that only deep
investment unlocks, not just bigger numbers.

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

### 1.3 Dialogue system — **[gap]**
`StartDialogue` / `DialogueChoice` / `EndDialogue` remotes are declared
(`Net.luau:354-356`) with no server handler and no client UI. `TalkTo` has a
report path (`MissionService.luau:413`) with no caller.

Build: dialogue trees in `src/shared/Config/Dialogue.luau`, a server service, a
client panel. This also unblocks `TalkTo` objectives and gives quest-givers a
purpose beyond standing still.

### 1.4 Vendor discovery — **[todo]**
`ShopService` finds vendors within 30 studs, but there is no in-world cue. You
open the panel and hope. Needs a billboard prompt (or Roblox `ProximityPrompt`)
over shop NPCs.

### 1.5 Skill tree UI — **[done]**
`SkillTreeController.luau`, opens with **K**. A tab per tree, rank pips per node,
an XP bar, and a preview of what the next rank buys. The Spend button carries the
refusal reason straight from `Progression.canPurchase`, so it explains a locked
node instead of doing nothing.

Points had been accumulating unspendable since the first kill: `SpendSkillPoint`,
`ProgressionService.purchaseSkill` and the 18 nodes all existed, and nothing on
the client ever fired the remote.

> With 1.1 and 1.2 done, the Tatooine chain is completable end to end. The
> remaining blocker is `TalkTo` (1.3), which gates every mission with a
> quest-giver conversation in it.

**Phase 1 exit criterion:** a new player can spawn, be pointed at a quest-giver,
accept a mission, complete every objective kind, and turn it in for credits.
That is the actual game loop, and it does not exist today.

---

## Phase 2 — Space and the galaxy

The single biggest content multiplier: eight planets are authored
(`Config/Planets.luau`) and only one is reachable.

**There is no ship code today** — not a config, not a model, not a service. The
word "ship" appears in `Planets.luau` only as flavour text and one comment about
fuel range (`:593`). This is a from-scratch phase.

### 2a. Travel without flight
- Galaxy map UI + planet selection
- `TravelService` — swap planet folders, reuse the existing per-planet gravity
  and atmosphere transition (both already work)
- Fuel / credit cost model. Per your note: fast travel costs credits, normal
  travel is free or fuel-based

Ship this **before** flyable ships. Travel alone unlocks seven planets of
existing content; flight is a separate, much larger problem.

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

**Landmarks are not modelled and do not match canon.** Points of interest are
placed by dividing a circle evenly by index, at a fixed radius of 286 studs
(`PlanetBuilder.luau:625-632`):

```lua
local angle = (index - 1) * (math.pi * 2 / #planet.pointsOfInterest)
local distance = SETTLEMENT_RADIUS * 0.55
```

So Mos Eisley, Chalmun's Cantina, Jabba's Palace and the Lars Homestead are four
*invisible* 40x20x40 marker parts, 90 degrees apart on one circle, all the same
distance from downtown. They exist only as mission `Reach` targets. Canonically
the Lars homestead is a long ride out into the Jundland Wastes; here it is 286
studs from the cantina.

To do:
- Hand-authored landmark geometry for the headline locations — Chalmun's
  Cantina interior, Jabba's Palace, the Mos Eisley docking bays
- Per-planet layout data (landmark positions) instead of `evenly spaced on a
  circle`, so the map has a shape you can learn and navigate by memory
- Decide the scale target. If speeders land in Phase 2b, the map can grow;
  without them, 3000 studs is already near the limit of tolerable walking.

Worth deciding early: **canon-accurate or canon-flavoured?** Accurate layouts
mean hand-building each site and living with their real distances. Flavoured
means recognizable landmarks arranged for playability. The current answer is
neither — it is random.

---

## Phase 4 — RPG depth

- ~~Skill tree UI~~ — **done**, see 1.5
- Loot drops with rolled affixes, and the `profile.inventory` change they need
- Per-zone level bands + an "you are underlevelled" warning on entry
- Weapon mods / attachments layered onto `Config/Weapons.luau`
- Faction reputation consequences. Missions already award rep
  (`rep = { Rebellion = 120, Empire = -180 }`) and nothing reads it back
- Companion NPCs

---

## Phase 5 — Living world

- NPC schedules (day/night behaviour — the clock already runs)
- Ambient crowd density per zone
- LLM-powered dynamic dialogue (your note). Needs Phase 1.3 first as the
  delivery surface
- Faction patrols that react to player rep

---

## Phase 6 — Ship it

- Publish the place (also fixes DataStores — saves currently run memory-only)
- Onboarding / first-time-user flow
- Game name. `OuterRimOdyssey` is a placeholder in `default.project.json`
- Delete legacy `StarWarsGame/`
- Playtest with the boys, tune numbers

---

## Working notes

- `./check.sh` is the gate: format, lint, type-check. Must end `all clean`.
- Rojo must be serving (`rojo serve default.project.json`) *and* connected in
  Studio, or none of the code exists in the place. The plugin goes stale
  silently — if behaviour looks a version old, disconnect and reconnect.
- There is no offline way to execute Luau. Runtime bugs need a Play test.
