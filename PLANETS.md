# Planets

What each world is for, what stands on it, and who lives there. Nine planets,
each with a job in the campaign — see [CAMPAIGN.md](CAMPAIGN.md) for the story
they serve.

Written 2026-08-14, after the decision to author layouts by hand rather than
generate them.

---

## 1. Most planets have two jobs

The single best structural decision available: **three planets are both an origin
world and a later act.**

| Planet | First visit | Second visit |
|---|---|---|
| Korriban | Acolyte prologue, lvl 1–6 | Act 4, lvl 36–46 |
| Taris | Scrapper prologue, lvl 1–6 | Act 2, lvl 18–26 |
| Nar Shaddaa | Scoundrel prologue, lvl 1–6 | Act 2, lvl 15–24 |
| **Ord Mantell** | **Conscript prologue, lvl 1–6** | **never — and that is the point** |

This cuts the number of worlds that have to be built to a high standard, and it
buys the best beat in any RPG for free: coming home at level 40 to the place that
nearly killed you at level 3, and finding it small. The districts that were
lethal are now scenery; the districts you could not enter are now the content.

**Ord Mantell is the deliberate exception.** The Conscript could have started on
Coruscant and saved a world, but Coruscant would have made his prologue a story
about serving greatness; Ord Mantell makes it a story about serving anyway. It is
also the only planet you never return to, which is its own kind of ending — the
war he left is still going on when the credits roll, and nobody ever explains
what it was about.

`PlanetDef.minLevel/maxLevel` become a range wide enough to hold both, and the
level banding happens per *zone* rather than per planet — which is exactly what
the roadmap's "large world banded by level" item asks for.

---

## 2. How a map gets authored

The problem: today every settlement is a radial grid of 130-stud blocks and every
point of interest sits on one circle, evenly divided by index. The map has no
shape you can learn, and it changes if anyone touches the seed.

The fix has three parts.

### 2.1 Prefabs — a vocabulary of buildings

`PlanetBuilder`'s Landmarks section already has the right shape: a table of
named builders, each declaring a `radius` before it builds anything. Promote it
to `src/server/World/Prefabs/`, one module per family, and grow the vocabulary
from 8 entries to ~40.

```lua
type PrefabDef = {
	radius: number,               -- footprint; the placement contract
	build: (Instance, CFrame, Style, Random) -> number,  -- returns height
	tags: { string }?,            -- "Interior", "Enterable", "Vendor"
}
```

Buildings stay procedural code, so they stay in git and in Rojo, and a
`DomedHut` on Tatooine and one on Tython differ only by the `Style` palette
passed in. What changes is that **where they stand is a decision, not a seed.**

### 2.2 Layout — an ASCII tile map per planet

Authored as a grid of characters in `Config/Planets.luau`, one glyph per 40-stud
cell, with a per-planet legend. A 32x32 grid covers a 1280-stud settlement, which
is the whole walkable town, and fits on a screen.

```lua
layout = {
	cell = 40,
	legend = {
		["H"] = "DomedHut",
		["h"] = "SunkenHut",
		["V"] = "Vaporator",
		["T"] = "JawaTent",
		["S"] = "MarketStall",
		["="] = "Road",
		["+"] = "Junction",
		["D"] = "DockingBayPit",
		["C"] = "CantinaBlock",
	},
	grid = {
		"................................",
		"....H.H....V......H.H...........",
		"....H.H..=========.H............",
		".........=......=...............",
		"...TTT...=..SSS.=....HH.........",
		"...TTT...+======+....HH.........",
		".........=......=...............",
		"......DD.=..CC..=......VV.......",
		"......DD.=..CC..=......VV.......",
		"................................",
	},
}
```

Why this format and not a list of `Vector3`s:

- **You can see the map in the diff.** A pull request that moves the cantina
  looks like a moved cantina.
- **Your sons can edit it.** Nobody has to understand Luau to move a tent.
- **It cannot drift.** There is no seed and no index arithmetic; the map is the
  file.
- Roads need no pathfinding: adjacent `=` cells tile into a continuous surface
  because the cells are the same size.

Rows run north to south, columns west to east, centred on the planet origin.
Everything outside the grid is still generated wilderness — a hand-authored
3000x3000 map is not worth the effort, and scattered boulders are fine out there.

### 2.3 Districts — rectangles, not rings

`ZoneDef.distance` stays for wilderness. Inside the grid, a district is a
rectangle in cell coordinates:

```lua
districts = {
	{ id = "Market", from = Vector2.new(10, 4), to = Vector2.new(18, 10), band = { 6, 9 } },
	{ id = "Docks",  from = Vector2.new(4, 12), to = Vector2.new(12, 20), band = { 9, 13 } },
}
```

`band` is the level range of NPCs that spawn there. That is the "large world
banded by level" requirement, and it is also the fix for the
`Behavior.Aggressive` hazard already documented: a district with a declared band
can be validated against the archetypes placed in it, so a level 18 hunter can
never be put in a level 3 district by accident.

### 2.4 Validation

`Planets.validate` already rejects undeclared zone names; extend it to reject:

- a glyph with no legend entry
- a legend entry naming a prefab that does not exist
- two prefabs whose declared radii overlap
- a district rectangle outside the grid
- an archetype whose level range does not fit its district's `band`
- a point of interest whose `zone` is a district with no cells

Every one of these is a bug that currently fails silently, which is the third
recurring failure mode in this codebase.

### 2.5 Authoring tooling — optional, later

Typing a 32x32 grid by hand is fine. Typing eight of them is tedious. A small
Studio plugin that dumps selected parts to a grid, or a web page that lets you
paint tiles, would pay for itself around planet three. Not a blocker.

---

## 3. The nine planets

Each entry: what it is for, its level band, its districts, its building
vocabulary, who lives there, and the beats it has to carry.

---

### Tatooine — the crossroads

**Act 1, levels 6–15.** Build this one first: it is the most finished, and all
four origins land here, so it is the only planet that has to work four ways.

**Feel:** heat, salvage, and nobody in charge. Twin suns (already built).

**Districts**

| District | Band | Contains |
|---|---|---|
| Anchorhead Landing | 6–8 | Docking bay pits, Czerka customs, the first vendor |
| The Market | 6–9 | Stalls, Jawa traders, the general goods shop |
| Cantina Row | 8–11 | The Dry Well, back rooms, the Mandalorian |
| The Flats | 7–10 | Moisture farms, vaporators, sunken courtyard homesteads |
| Jundland Wastes | 11–14 | Rock, the sandcrawler wreck, Sand People territory |
| Dune Sea | 13–16 | The downed Czerka transport. Nothing else. Deliberately empty. |
| Nagurra's Estate | 12–15 | Gate, audience chamber, the collection |

> **Names are era-locked.** Anchorhead and Czerka are the KOTOR/SWTOR-era
> settlement and corporation; Mos Eisley, Chalmun, Jabba and the Lars family are
> all Original Trilogy and roughly 3,600 years too late. Tatooine itself is
> correct for 3,640 BBY and stays — it is a Star Map world in KOTOR — so only the
> signage needed changing. The same rule applies to every other planet here.

**Prefab vocabulary:** `DomedHut`, `SunkenHut` (courtyard farmstead), `Vaporator`,
`JawaTent`, `SandcrawlerHull`, `MarketStall`, `DockingBayPit`, `CantinaBlock`,
`PalaceGate`, `MoistureCistern`, `Boulder`, `BantheBones`.

**Population:** Moisture Farmer, Jawa, Merchant, Smuggler, Civilian, Tusken
Raider (Wastes and Dune Sea only), Cartel Enforcer, Mandalorian Hunter (Cantina
Row, and *not* aggressive), Imperial Scout (light presence — the Empire does not
own this planet), one **Hollowed** wandering the Market.

**Beats:** the salvaged crate; the buyer chain through the market; the Mandalorian
who wants the same transport; the Hutt's collection; the Czerka recovery team and
the shipping code that points at Nar Shaddaa.

**Cameo:** Mandalore the Vindicated, in the cantina, sanctioning entry to the
Great Hunt.

---

### Korriban — the school and the tombs

**Acolyte prologue levels 1–6; Act 4 levels 36–46.**

**Feel:** red rock, no water, and a valley of mausoleums bigger than the city
that serves them. Everything here is a grave with a door.

**Districts**

| District | Band | Contains |
|---|---|---|
| Academy Grounds | 1–5 | Dormitories, training pits, Overseer Vashk |
| Dreshdae | 3–7 | The one settlement. Czerka office, cantina, the only vendor |
| Valley of the Dark Lords | 5–8 / 38–44 | Four tomb façades. Entrances sealed at level 5 |
| Tomb of Marka Ragnos | 40–44 | Act 4 only |
| Tomb of Tulak Hord | 42–46 | Act 4 only. The ritual is written here |
| The Wastes | 6–9 / 36–40 | Tuk'ata, shyrack caves |

The two-visit structure at its clearest: at level 3 the Valley is a skybox you
walk past and the tombs are locked doors. At level 40 the doors are the game.

**Prefab vocabulary:** `TombFacade`, `Obelisk`, `AcademyBlock`, `TrainingPit`,
`SithColumn`, `Sarcophagus`, `Brazier`, `CliffStair`, `DreshdaeDome`.

**Population:** Sith Acolyte, Sith Overseer, Sith Inquisitor, Imperial Trooper,
Czerka Foreman, Merchant, and — in the Wastes — beasts, which needs a
non-humanoid rig the game does not have yet. Substitute Assassin Droids if that
is not built.

**Beats (prologue):** three trials; your friend goes hollow; Vashk has her put
down; you are sent away. **Beats (Act 4):** the tomb the Academy forbids;
Vashk's thirty years of notes; the method.

---

### Taris — the warehouse

**Scrapper prologue levels 1–6; Act 2 levels 18–26.**

**Feel:** a city that died standing up. Twenty-eight thousand years of
architecture, bombed flat from orbit and then left. Everything is at an angle.

**Districts**

| District | Band | Contains |
|---|---|---|
| Resettlement Camp | 1–5 | Prefab huts, the Republic's optimistic little colony |
| The Dig | 2–6 | Salvage cranes, spoil heaps, where Nine was found |
| Sinking Sector | 6–9 / 18–22 | Collapsed towers at 20 degrees. Vertical traversal |
| Czerka Lot 9 | 20–26 | The warehouse. Locked in the prologue |
| The Undercity | 22–26 | Below the rubble line. No sky |

**Prefab vocabulary:** `RuinedTower` (a family — upright, leaning, sheared),
`PrefabHut`, `SalvageCrane`, `SpoilHeap`, `CollapsedSpan`, `CargoStack`,
`CzerkaWarehouse`, `RubbleField`, `CatwalkRun`.

Taris is the planet that justifies the prefab system: the same three tower
prefabs at different rotations and scales make a whole city, and a hand-authored
grid is what stops it looking like a random field of boxes.

**Population:** Scrapper civilians, Republic Trooper (thin presence), Czerka
Foreman, Czerka Security Droid, Assassin Droid, Cartel Slicer, and in the
Undercity the **Hollowed** in numbers — Czerka stores them here.

**Beats (prologue):** Czerka strips your dig; you find the container.
**Beats (Act 2):** Lot 9; Nine remembering; the manifests.

**Cameo:** HK-47's parts, in Lot 9 — shipped here from Anchorhead on Tatooine,
where the player met him intact and could not afford him. Optional and missable.

---

### Nar Shaddaa — the market

**Scoundrel prologue levels 1–6; Act 2 levels 15–24.**

**Feel:** a moon with no ground, lit entirely by advertising. Everything is for
sale and the price is posted. `lawLevel = 0.0` should mean something: no
authority responds to anything, ever.

**Districts**

| District | Band | Contains |
|---|---|---|
| The Promenade | 1–6 / 15–18 | Neon, crowds, every vendor in the game |
| Docking Bay 41 | 3–7 | Freighters, Vess Kadar's office |
| Refugee Sector | 5–9 / 16–20 | The people the war made. Where Czerka recruits |
| The Corellian Run | 18–22 | Cartel territory. Enforcers, slicers |
| Shadow Town | 20–24 | Below the vent line. The auction |

**Prefab vocabulary:** `NeonSign` (many), `PromenadeSpan`, `MarketKiosk`,
`FreighterBerth`, `RefugeeShelter`, `CantinaNeon`, `VentStack`, `Skybridge`,
`AdvertScreen`, `CartelDen`.

Nar Shaddaa is `hasWalkableGround = false` in the good way — it is a stack of
platforms, and the existing Coruscant vertical-city code applies directly.

**Population:** Smuggler, Cartel Enforcer, Cartel Slicer, Merchant (several,
with different stock), Civilian, Mandalorian Hunter, Czerka Scientist, Hollowed
being sold.

**Beats (prologue):** the courier run; the cargo is a person.
**Beats (Act 2):** the market for Force-sensitives; Vess Kadar chooses a side;
the auction.

**Cameo:** Nico Okarr, selling a bad ship and a good tip.

---

### Ord Mantell — the ugly little war

**Conscript prologue, levels 1–6.** The ninth world, added 2026-08-14 rather
than starting the Conscript on Coruscant.

It earns the extra planet by being the only honest place to begin a character who
enlisted at fifteen because the army fed him. Ord Mantell is a Republic world
losing a grubby civil war to its own separatists — a war with no principles on
either side, which the Republic does not talk about and would like to finish
quietly. Coruscant would have made the Conscript's prologue a story about
serving greatness. This makes it a story about serving *anyway*, which is the
character.

It is also the smallest planet in the game and should stay that way: one town,
one battlefield, one swamp, ~20 minutes of play.

**Feel:** mud, rain, and a war being fought over a hill nobody can name.

**Districts**

| District | Band | Contains |
|---|---|---|
| Fort Garnik | 1–3 | Republic garrison. Barracks, armoury, Sergeant Marr |
| Drelliad Village | 2–4 | Civilians who have been "liberated" three times |
| The Savrip Fields | 3–5 | Trenches, wire, artillery craters. The prologue's set piece |
| Jagged Wilds | 4–6 | Swamp. Separatist camps, and the wreck you are not supposed to find |

**Prefab vocabulary:** `GarrisonBlock` (shared with Coruscant), `Sandbag`,
`TrenchSection`, `ArtilleryPiece`, `VillageShack`, `WaterTower`, `WireLine`,
`CraterPool`, `SwampStilt`, `MedTent`.

Cheap to build: `TrenchSection` and `Sandbag` tile along a grid row, which is the
tile map format doing exactly what it is for.

**Population:** Republic Trooper, Republic Veteran, Sergeant Marr, Civilian
(frightened, and not grateful), Separatist Militia (a new archetype — poorly
armed, badly led, and the first people you kill), Merchant, Protocol Droid.

**Beats:** basic training compressed into one action; the garrison push that goes
wrong; your unit's Jedi liaison going hollow mid-firefight and you dragging her
out; command filing it as fatigue and ordering you not to write it down. You
leave with a document that says it did not happen.

**No cameo.** Deliberately. The Conscript's prologue is the one place in the game
where nobody important is watching, and that is the point.

---

### Coruscant — the cover

**Act 3, levels 26–34.**

**Feel:** the difference between the two halves. Thirteen years after the
Sacking, the Senate District is spotless and the Underlevels are still rubble
with people living in it.

**Districts**

| District | Band | Contains |
|---|---|---|
| Senate Plaza | 26–30 | Polished. Nothing happens here except conversation |
| The Works | 27–30 | Resettlement blocks. Where the Sacking's refugees still are |
| Jedi Temple Ruin | 30–34 | Not rebuilt. Deliberately. |
| Skylanes | any | Traffic, the existing SkylaneAlpha/Beta/Gamma POIs |
| Underlevels | 28–34 | Rubble line and below. No sky, no law |

**Prefab vocabulary:** `SenateColonnade`, `PlazaTier`, `SpeederLane`,
`GarrisonBlock`, `ResettlementStack`, `RubbleSpan`, `TempleRuin`, `SkybridgeLong`,
`StatuePlinth`, `HoloBoard`.

**Population:** Republic Trooper, Republic Marshal, Republic Veteran, Imperial
Officer (an embassy — the treaty is still nominally in force, which is a great
source of tension), Civilian, Protocol Droid, Jedi Knight (a handful, wary).

**Beats:** taking the evidence to the Republic, and being sincerely thanked and
quietly buried. The Conscript gets an extra thread here — the document from Ord
Mantell saying it never happened turns out to have a signature on it, and the
person who signed it is still in the building.

**Cameo:** Darth Malgus walks through a room you are hiding in. No health bar.

---

### Tython — the Order

**Act 3, levels 30–36.** No prologue. The one beautiful planet.

**Feel:** green, quiet, and old. The Jedi came back here after Coruscant burned.
Everything is deliberately unfortified, which is either faith or denial.

**Districts**

| District | Band | Contains |
|---|---|---|
| The Temple | 30–32 | Archives, council chamber, Master Ryn Solaa |
| Kalikori Village | 30–33 | Twi'lek settlement that predates the Jedi's return |
| The Gnarls | 32–35 | Wilderness, training grounds, Flesh Raiders |
| Forge Ridge | 34–36 | Where sabers are made. The Acolyte's problem |

**Prefab vocabulary:** `TempleHall`, `MeditationTerrace`, `StoneArch`,
`KalikoriHut`, `RopeBridge`, `ForgeAnvil`, `StandingStone`, `Waterfall`,
`AncientTree`.

**Population:** Jedi Knight, Jedi Padawan, Civilian, Republic Marshal, Flesh
Raider (aggressive, in the Gnarls only, correctly banded).

**Beats:** Ryn Solaa names the Quiet; the Council declines; the archives hold
the first written account; whichever path you took, you are betrayed here or on
Coruscant.

**Cameo:** Grand Master Satele Shan. One conversation, in which she refuses to
help and is right to.

---

### Hoth — the evidence

**Act 4, levels 38–46.**

**Feel:** cold as a mechanic, not a texture. And the graveyard — thousands of
starship hulls from a battle nobody can now explain, half-buried, walkable.

**Districts**

| District | Band | Contains |
|---|---|---|
| Aurek Base | 38–40 | Republic salvage operation. The only warm place |
| The Graveyard | 40–44 | Hulls as terrain. Traversal is the content |
| Glacial Fissure | 42–45 | Ice caves, wampas |
| The Transport | 44–46 | The ship that has been making the same run for a century |

**Prefab vocabulary:** `HullSection` (a family — bow, spine, engine block),
`SnowBunker`, `HangarShed`, `IceSpire`, `WreckField`, `Crevasse`, `HeaterPylon`.

`PlanetDef.gravity = 210` is already set heavier, and cold could be a real
mechanic — a slow drain outside heated zones, which turns `HeaterPylon`
placement into level design. Optional, but it is the one planet where a survival
pressure would fit.

**Population:** Republic Trooper, Republic Veteran, Imperial Scout (racing you
for the same wrecks), Mandalorian Hunter, wampa if beast rigs exist.

**Beats:** find the transport; read its century of manifests; get a destination
that is not on any chart.

---

### Dromund Kaas — the household

**Act 5, levels 46–50.**

**Feel:** permanent storm. Lightning, black stone, and a jungle that is
aggressively alive. The Sith Empire's capital, and the least free place in the
galaxy.

**Districts**

| District | Band | Contains |
|---|---|---|
| Kaas City | 46–48 | Imperial citadel, the Dark Council's antechambers |
| The Nexus Road | 47–49 | The road out of the city. Guarded the whole way |
| Dark Temple Grounds | 48–50 | The caretaker's household |
| The Dead World | 50 | Reached from here. No zones, no NPCs, no weather, no sound |

**Prefab vocabulary:** `CitadelSpire`, `ImperialArch`, `StormPylon`,
`JungleCanopy`, `DarkTempleWall`, `Obelisk`, `RainSlick`.

**Population:** Sith Lord, Sith Inquisitor, Imperial Guard, Sith Trooper,
Imperial Officer, Civilian (terrified).

**Beats:** the caretaker's household and the last living witnesses; then the
dead world, where the Force tree's abilities do not function and a Sith player is
the weakest person in the room. Three endings.

---

## 4. Build order

Depth first, not breadth. One finished planet teaches more than nine sketched
ones, and the prefab vocabulary built for Tatooine is 60% reusable everywhere.

1. **Tatooine, completely.** Layout grid, ~12 prefabs, districts with bands, Act
   1 missions, the Hollowed archetype. This is the vertical slice: if the game is
   fun here it is fun.
2. **The layout system itself,** extracted from step 1 as it is written. Grid
   parser, prefab registry, district rectangles, validation.
3. **Ord Mantell,** because it is the smallest planet in the game and the second
   use of the layout system should be a cheap one. Also gets one origin
   playable end to end.
4. **Korriban,** which is both the Acolyte prologue and the Act 4 payoff, so it
   proves the two-visit structure works.
5. **Nar Shaddaa and Taris,** the Act 2 pair. Nar Shaddaa reuses Coruscant's
   vertical-city code; Taris proves the prefab family idea.
6. **Coruscant,** already partly built, needs the Works and the Underlevels.
7. **Tython, Hoth, Dromund Kaas** — the back half, once the pipeline is boring.

Travel (roadmap Phase 2a) is a hard dependency from step 3 onward: the moment a
second planet has content, a player has to be able to reach it.

The signature chains ([CAMPAIGN.md](CAMPAIGN.md) §5) cut across this order — the
saber alone touches Taris, Nar Shaddaa, Tython and Korriban. Nothing before step
5 can deliver a complete one, so build them chain-part-by-chain-part as their
planets land rather than trying to finish one chain early.
