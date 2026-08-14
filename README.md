# Outer Rim Odyssey

A free-roam Star Wars RPG for Roblox. Eight planets, procedurally generated
cities, a crowd of NPCs with their own lives, blaster and lightsaber combat, and
a level-and-skill-tree progression system that persists between sessions.

Everything in this repository is code. There are no `.rbxl` files to merge, no
marketplace asset IDs, and nothing that only exists inside somebody's copy of
Studio. Characters, weapons, cities and the HUD are all built at runtime from
config tables, which means a change to `Planets.luau` changes the game.

> **Note:** this is a rewrite. The original 2024 project is still in
> `StarWarsGame/` for reference and is no longer wired into anything.

---

## Getting it running

You need [Rokit](https://github.com/rojo-rbx/rokit) (a toolchain manager) and
Roblox Studio.

```bash
# 1. Install the pinned tools listed in rokit.toml
rokit install

# 2. Start the sync server
rojo serve
```

Then, in Studio:

1. Install the **Rojo** plugin if you have not already
   (`rojo plugin install`, or from the Studio toolbox).
2. Open a new, empty baseplate place.
3. Open the Rojo plugin panel and click **Connect**.
4. Press Play.

The world builds itself on the first server frame, so the baseplate does not
need anything in it. You can delete the default baseplate part.

### Everyday commands

```bash
./check.sh                # format, lint and type-check everything
rojo serve                # live-sync src/ into Studio
rojo build -o game.rbxl   # produce a place file, for uploading
```

### Checking your work

`./check.sh` runs StyLua, Selene and `luau-lsp analyze` over the whole tree. The
last of those is the important one: it gives you the same type errors Studio
would, without having to press Play. It is worth running before every Studio
session — it has already caught a `CFrame * Vector3` mistake that would have
errored on every single NPC spawn.

It is not a substitute for playing the game, though. Nothing here can catch a
mistake that only shows up at runtime, so also watch the Output window on boot:
`ServiceLoader` prints a banner listing any service that failed to load, and
several config modules validate themselves and warn about problems (an archetype
pointing at a weapon that does not exist, a mission objective referencing an
unknown NPC) rather than failing silently.

---

## How it fits together

```
src/
  shared/          ReplicatedStorage.Shared -- config + code both sides use
    Config/        the game's data: planets, weapons, species, missions...
    Core/          Signal, Net, ServiceLoader
    Rig/           character and weapon model construction
  server/          ServerScriptService.Server
    Services/      one file per system, loaded by ServiceLoader
    NPC/           the NPC state machine
    World/         the procedural planet generator
  client/          StarterPlayerScripts.Client
    Controllers/   input, effects, HUD, atmosphere
```

### Services

Both the server and the client boot the same way: `ServiceLoader` requires every
ModuleScript in a folder, runs `init()` on all of them in priority order, then
runs `start()` on all of them. `init` may only touch itself; `start` may call
anything. That two-phase split is what removes load-order bugs — no service
needs to care which file loaded first.

| Service | Priority | Owns |
| --- | --- | --- |
| `DataService` | 1 | Profiles, DataStore persistence, session locking |
| `WorldService` | 5 | When each planet gets generated |
| `ProgressionService` | 10 | XP, levels, skill points, derived stats |
| `PlayerService` | 20 | Spawning, per-planet gravity, sprint, travel |
| `CombatService` | 30 | Firing, damage, kills, weapon equipping |
| `NPCService` | 40 | Spawning, ticking and retiring the crowd |
| `MissionService` | 50 | Accepting, tracking and rewarding missions |

Client controllers follow the same pattern: `ClientState` (1), `InputController`
(20), `EffectsController` (30), `HudController` (40), `AtmosphereController`
(50).

### The design rules

A few decisions run through the whole codebase. They are worth knowing before
changing anything.

**The server decides everything.** The client sends intent — "I pressed fire,
aiming there" — and never a result. The server re-derives which weapon is held,
whether the cooldown has elapsed, what the spread is, what was hit and how much
damage it did. Every remote goes through `Net`, which rate-limits per player and
validates arguments before the handler ever runs.

**Config tables are the game.** Adding a planet, a weapon, an NPC archetype or a
mission means adding an entry to a table in `shared/Config`. No new code, no new
Studio objects. Remote payloads carry ids, never config rows, so the client
cannot be lied to about what a weapon does.

**Compared strings live in constant tables.** The original project had a bug
where NPCs were spawned with behaviour `"PATROL"` and the state machine checked
for `"Patrol"`, so no NPC ever patrolled — silently, for a year. Anything that
gets compared (`Behavior`, `Objective`, faction names) is now a named constant.

**Nothing is built by hand in Studio.** The HUD, the character rigs, the
weapons, the cities. A GUI assembled by hand in `StarterGui` is invisible to
version control and impossible to review.

---

## The systems

### Characters

`RigBuilder` builds R15 characters through
`Players:CreateHumanoidModelFromDescription`, then welds procedural armour,
robes and accessories onto them. Using a real HumanoidDescription rig — rather
than assembling parts from scratch — means the result has correct `Motor6D`
joints, so stock Roblox animations and `PathfindingService` both work with no
extra effort.

Species (`Species.luau`) set proportions and skin tones; costumes
(`Costumes.luau`) set the armour. A Twi'lek and a Wookiee are different heights
and builds, a stormtrooper's plates are welded parts, a Jedi's robe is a welded
skirt of tapering blocks.

Every distinct (species, costume, size) combination is built once and cached in
ServerStorage; every later NPC is a clone. The starting planet's combinations
are warmed at boot, before anyone can join, because building a rig yields and
the first one on a cold server is a visible hitch.

### NPCs

`NPCBrain` is a state machine — Idle, Wander, Patrol, Flee, Combat — and
`NPCService` owns the population. Every brain is stepped from one Heartbeat
accumulator at 8 Hz, not from its own `while true` loop, and stepping is
level-of-detail'd by distance to the nearest player: full sensing inside 220
studs, movement only inside 520, a slow heartbeat beyond that. One brain
erroring cannot stop the rest.

Being shot overrides disposition — a farmer who takes a bolt reacts to it
whatever the reputation table says — and an NPC entering combat shouts to allies
within a radius, which is what makes a patrol behave like a squad rather than
five individuals.

Planets populate lazily: a world's crowd spawns when a player is standing on it
and despawns 90 seconds after the last one leaves, so eight worlds can share one
server.

### The world

`PlanetBuilder` generates each planet deterministically from a hash of its id,
so every server builds the same world. Ground-based planets get terrain, a
street-grid settlement with plazas and tapering towers, and scattered dunes or
rocks or trees. Coruscant has no ground at all: it is towers from far below up
to the flight ceiling, with cantilevered landing platforms at intervals.

The generator's output is a contract, not an implementation:

```
Workspace/Spawns/<Planet>   -- where players appear
Workspace/Zones/<Planet>    -- where NPCs live; a multi-part zone is a patrol route
Workspace/POI/<Planet>      -- mission "reach this place" targets
```

Nothing else in the codebase knows how the world was made. A hand-built map can
replace the generator entirely as long as it emits those three folders.

### Combat

Damage is hitscan — resolved instantly by raycast on the server — while the
visible bolt is a client-side effect that travels at the weapon's projectile
speed. That combination is what makes blasters feel responsive and look right at
the same time.

Blasters have spread, falloff, fire modes and cooldowns; lightsabers have swing
arcs and can deflect. Damage scales off the attacker's level and skills, and a
critical roll comes from a derived stat rather than a hardcoded number.

### Progression

Kills, missions and discoveries award XP. Levels award skill points, and skill
points buy nodes in a tree whose effects are *derived stats* — `MoveSpeedMult`,
`CreditMult`, `HealthRegen`, `CritChance` — that every other system reads. This
is why no system needs to know what a skill is: `PlayerService` asks for a move
speed multiplier, not for whether the player has bought Sprinter.

Profiles save to DataStore with session locking, so the same player joining a
second server cannot fork their save.

### Missions

Missions are objective lists — kill N of something, talk to somebody, reach a
place, collect an item. Every source of progress funnels through a single
function, `MissionService.report`, so combat and dialogue never need to know a
mission exists. Rewards scale with level and with the player's credit multiplier.

### Atmosphere

Each planet declares its own fog, ambient light, sky tint and day length, and
`AtmosphereController` cross-fades Lighting between them over two seconds when
you arrive. Gravity is per-planet too, applied as a `VectorForce` on each
character — Roblox only has one global gravity value, so the force cancels the
difference. Jump height and fall speed both follow from that for free.

---

## What is not built yet

- **Ships and space travel.** Planets have coordinates, fuel costs and fast
  travel prices in config; the flight model and the galaxy map are not written.
- **Dialogue.** The remotes and the NPC interaction hook exist; the dialogue
  trees and the UI do not.
- **Shops.** Archetypes can declare a shop id; nothing serves one yet.
- **Mission board UI.** The server answers `GetMissionBoard`; nothing on the
  client asks.

## Open questions

- **The name.** `OuterRimOdyssey` is a placeholder in `default.project.json`.
- **The old project.** `StarWarsGame/` is dead code kept for reference. It is in
  git history either way, so it can be deleted whenever.
