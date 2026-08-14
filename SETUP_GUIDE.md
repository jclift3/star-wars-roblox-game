# Setup guide

Everything needed to go from a fresh clone to a running game, and then to
changing it. The [README](README.md) covers what the systems are and why; this
covers what to type.

---

## 1. Install the toolchain

The project pins its tool versions in `rokit.toml`, so everyone runs the same
Rojo and the same formatter.

**macOS / Linux:**

```bash
curl -fsSL https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | iex
```

Then, from the repository root:

```bash
rokit install
```

That gets `rojo`, `stylua` and `selene` at the pinned versions. Verify with
`rojo --version` — it should print 7.4.4.

---

## 2. Connect Studio

```bash
rojo serve
```

Leave that running. In Roblox Studio:

1. Install the Rojo plugin. Easiest is `rojo plugin install` in another
   terminal; otherwise find "Rojo" in the Studio toolbox.
2. **File → New** to get an empty baseplate.
3. Open the **Rojo** tab in the Studio ribbon and click **Connect**.
4. You should now see `Server`, `Shared` and `Client` appear in the Explorer
   under ServerScriptService, ReplicatedStorage and StarterPlayerScripts.

Saving a file on disk now updates Studio live. The reverse is not true — Rojo
syncs one way, so anything you create by hand in the Explorer will be lost.
That is intentional.

---

## 3. Turn on API services

Player profiles save to a DataStore, and DataStores are unavailable in Studio
until you allow them:

**Home → Game Settings → Security → Enable Studio Access to API Services.**

Without this the game still runs — `DataService` falls back to an in-memory
profile — but nothing persists between test sessions, and you will see a warning
in the Output window saying so.

---

## 4. Play

Press **Play** (F5). On boot you should see, in Output:

```
[ServiceLoader] 7 services started.
```

If instead you get a banner reading `N SERVICE(S) FAILED`, the lines under it
name the service and the error. That is the fastest way to find a mistake in
this codebase — read the banner first, before anything else.

You will spawn on Tatooine, in a generated settlement, with NPCs walking
around.

### Controls

| Input | Action |
| --- | --- |
| Left mouse | Fire / swing |
| Shift | Sprint |
| E | Interact with an NPC |

---

## 5. Everyday commands

```bash
./check.sh                 # format, lint and type-check everything
rojo serve                 # live-sync (what you leave running while working)
rojo build -o game.rbxl    # build a place file for uploading
```

### What `check.sh` does

Three tools, in order:

- **StyLua** formats. Tabs, because that is what the Roblox ecosystem uses.
- **Selene** lints. `selene.toml` sets `undefined_variable = "deny"`, which
  catches typo'd globals — a real class of bug in Luau, where a misspelled
  variable is silently `nil` rather than an error.
- **`luau-lsp analyze`** type-checks, using a Rojo-generated sourcemap so it can
  resolve `require(Shared.Config.Planets)` the same way Studio does. This gives
  you Studio's own diagnostics without having to press Play, and it is the
  reason to bother running the script: it has already caught a
  `CFrame * Vector3` mistake that would have errored on every NPC spawn.

The script is expected to end with `all clean`. Run it before every Studio
session; it takes a few seconds and saves a reload-and-replay cycle.

### It still is not a test suite

There is no way to execute Luau outside Roblox, so nothing above catches a
mistake that only appears at runtime. Two things soften that:

- `ServiceLoader` catches a failing service instead of taking the whole server
  down with it, and reports every failure in one banner at the end of boot.
- Several config modules validate themselves on boot and warn — an archetype
  pointing at a weapon that does not exist, a mission objective naming an
  unknown NPC. Those appear as `[NPCService] archetype config: ...` lines.

For the same diagnostics live as you type, the
[Luau Language Server](https://marketplace.visualstudio.com/items?itemName=JohnnyMorganz.luau-lsp)
VS Code extension reads `default.project.json` directly.

---

## 6. Changing the game

Almost everything is a config table in `src/shared/Config/`. These are the
common edits.

### Add a planet

Add an entry to `Planets.luau`:

```lua
def({
    id = "Dantooine",
    displayName = "Dantooine",
    coords = V3(...),           -- position on the galaxy map
    gravity = 180,              -- studs/s²; 196.2 is Roblox standard
    terrain = "Forest",         -- drives ground colour and scatter
    hasWalkableGround = true,   -- false means a vertical city
    minLevel = 5,
    maxLevel = 12,
    spawns = { { archetype = "Farmer", count = 8, zone = "Fields" } },
    pointsOfInterest = { { id = "OldRuins", ... } },
    -- ...fog, ambient light, day length
})
```

Nothing else needs to change. The generator will build it, the atmosphere
controller will light it, and `NPCService` will populate it the first time
somebody stands on it.

### Add an NPC type

Add an entry to `NPCArchetypes.luau` — species pool, costume, faction,
behaviour, level range, and optionally a weapon and a `weaponChance`. Then
reference its id from a planet's `spawns` list.

### Add a weapon

Add an entry to `Weapons.luau`. A weapon is a list of welded parts plus its
stats. The convention `WeaponModel` relies on: **the grip is at the model
origin, and the barrel points down -Z**, matching the direction a Roblox
character faces.

### Add a mission

Add an entry to `Missions.luau`: an objective list, a level requirement, and
rewards. Objective kinds are constants in that file (`Objective.Kill`,
`Objective.TalkTo`, `Objective.Reach`, `Objective.Collect`) — never write the
string literal.

### Change how a planet looks

Terrain colour, fog and light live on the planet definition. The *shape* of
settlements is in `src/server/World/PlanetBuilder.luau`, in `styleFor` —
building colours, floor counts, whether roofs are domed, what gets scattered
around.

To replace generated worlds with hand-built ones entirely, build the map in
Studio and have it emit the three marker folders described in the README
(`Workspace/Spawns/<Planet>`, `Zones`, `POI`). Nothing else in the codebase
knows where the geometry came from.

---

## Troubleshooting

**Studio shows nothing after connecting.** Check `rojo serve` is still running
and that you clicked Connect on the right port (34872 by default).

**"no spawn point for X; using origin".** `WorldService` did not build that
planet, or the build errored. Look further up the Output for a
`[WorldService] failed to build` warning.

**Profiles reset every test.** Studio Access to API Services is off — see step
3.

**Nothing happens when I press Play.** `CharacterAutoLoads` is deliberately off:
players spawn only after their profile has loaded and the game knows which
planet they were last on. If nobody ever spawns, `DataService` failed — check
the boot banner.
