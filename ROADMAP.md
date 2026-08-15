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

This file stays the build order. Those two are the content.

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
Korriban, Tython, Taris and Dromund Kaas, plus Ord Mantell as a ninth. Eight
archetypes are renamed, one is cut, seven are added. All 15 missions are
rewritten — they were 5 unconnected chains with no theme, so that was owed
anyway. Every service, weapon, outfit and skill is untouched: the engine does not
care what era it is.

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

> With 1.1, 1.2, 1.3 and 1.5 done, every objective kind now has a way to be
> completed and every mission has a person to take it from.

**Phase 1 exit criterion:** a new player can spawn, be pointed at a quest-giver,
accept a mission, complete every objective kind, and turn it in for credits.
**Met on paper — needs a playtest to confirm it in practice.** 1.4 is the last
piece of polish: vendors work, but nothing in the world says where they are.

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
**Every other world still needs the same pass** — the archetypes are still named
Stormtrooper and the factions still Empire and Rebellion.

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
scattered boulders are fine out there.

### 3.2 The eight worlds — **[todo]**
Contents specified per planet in [PLANETS.md](PLANETS.md) §3. Build order is
depth-first: **Tatooine completely** (layout, ~12 prefabs, banded districts,
Act 1) as the vertical slice, then extract the layout system from what that
taught, then Korriban, then the rest.

The structural win: **four planets are both an origin world and a later act** —
Korriban, Taris, Nar Shaddaa and Coruscant. That halves the worlds needing a high
finish and buys the best beat in any RPG for free, which is returning at level 40
to the district that nearly killed you at level 3.

**Travel is a hard dependency from the second planet onward.** Phase 2a before
this goes past Tatooine.

---

## Phase 3b — The campaign

The story, specified in [CAMPAIGN.md](CAMPAIGN.md). Mostly content, but four
small system changes have to land first.

### 3b.1 Origin — **[todo]**
`PlayerProfile.origin`, a `Config/Origins.luau`, a creation screen on the
existing 760x470 panel convention, and an `origin: string?` field on
`ObjectiveDef` and on the dialogue `Condition`. That last one is what makes four
prologues affordable: one mission and one conversation can serve all four
origins and say something different to each.

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

- ~~Skill tree UI~~ — **done**, see 1.5
- Loot drops with rolled affixes, and the `profile.inventory` change they need
- ~~Per-zone level bands~~ — moved into 3.1, where districts declare a `band`.
  Still owed here: the "you are underlevelled" warning on crossing into one
- Weapon mods / attachments layered onto `Config/Weapons.luau`
- Faction reputation consequences. Missions already award rep
  (`rep = { Rebellion = 120, Empire = -180 }`) and nothing reads it back.
  Phase 3b needs this, so it is no longer optional
- Companion NPCs — Ordo-9 is the argument for them (CAMPAIGN.md §5.4)
- ~~Is a lightsaber bought or earned?~~ **Built, over five quests** — and every
  other origin got a signature chain to match. See 3b.5

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
