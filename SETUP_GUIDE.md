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

## 7. Publishing

Everything above runs the game on one machine. Publishing is what lets somebody
else press Play, and it is the only step in this document that cannot be done
from a terminal — it needs a Roblox account, so it is a Studio action performed
by whoever owns the game.

### First publish

1. Have `rojo serve` running and Studio **Connected**, so the place in front of
   you is the current code and not a stale copy.
2. Press Play once and read the Output. Publish from a boot that printed
   `[ServiceLoader] 7 services started.` and nothing else in red. A published
   place is what other people load; a failed service is a broken game for them,
   not a warning they can ignore.
3. Stop the playtest. **File → Publish to Roblox As…**
4. Choose **Create new game**. Name it **The Hollowing**. Put the era in the
   description — "a free-roam RPG set in the Old Republic, some three and a half
   thousand years before an Empire" — and *not* in the name. That distinction is
   deliberate and is explained in ROADMAP.md.
5. Publish.

Roblox has now created a **universe** (the game) containing one **place** (the
starting level). Everything the codebase does with DataStores is keyed against
that universe, which is why this step matters more than it looks.

### Let the others in

**Home → Game Settings → Permissions → Playability.** The three settings mean:

| Setting | Who can join |
| --- | --- |
| Private | Only you |
| Friends | Anyone on your Roblox friends list |
| Public | Everybody |

**Friends** is the one to want for a while. It requires that the accounts you
want to play are actually friends of the owner account — being family is not a
Roblox relationship.

### DataStores start working here

`DataService` writes real, persistent profiles — levels, credits, skill points,
mission state — but a DataStore belongs to a universe, so before the first
publish there is nothing to write to. Up to this point the service has been
running its in-memory fallback and warning about it in Output.

This means the first published session is the first one whose progress is real.
Anything the boys did in a Studio playtest is gone, and that is expected rather
than a bug.

Note that step 3's **Enable Studio Access to API Services** is a *separate*
switch and still matters: it is what lets your Studio playtests read and write
the same live DataStore the published game uses.

### Publishing again

**File → Publish to Roblox** (Alt+P) overwrites the same place, no dialog.

The thing to internalise: **Rojo syncing does not publish.** `rojo serve` moves
code from disk into your open Studio session, and that session is a working
copy. Until you press Alt+P, everyone else is playing the last snapshot you
uploaded. A change that "did not take effect for the boys" is almost always
this.

If a publish turns out to have been a mistake, the Creator Dashboard keeps
**Version History** for the place, and restoring an older version is two clicks.
That is the undo, and it is worth knowing about *before* needing it.

---

## 8. Talking to a backend

Two switches, both in Studio:

**Home → Game Settings → Security → Allow HTTP Requests.**

`HttpService` is server-only and refuses anything that is not HTTPS, so a client
cannot see, spoof or replay a backend call. That property is why the design in
[LIVING-NPCS.md](LIVING-NPCS.md) can put a secret behind an edge function rather
than in the game.

**Enable Studio Access to API Services** (step 3) also matters here, because the
endpoint and key are read out of a DataStore — see below.

---

## 9. Turning on telemetry

`AnalyticsService` posts gameplay events to a Supabase edge function, which
writes them to Postgres. It is off until configured, and a fresh clone with no
configuration runs the entire game normally — that is the intended default, not
a degraded mode.

### Why the configuration is not in this repository

Two reasons, and they are the same two that apply to every secret this project
will ever have:

1. **This repository is public.** An endpoint and key committed to it are an
   open write handle to the database.
2. **A secret in the place file cannot be rotated without republishing.** Server
   scripts are not visible to players, but they are still baked into the
   uploaded build, so changing a key would mean a new deploy of the game.

So both live in a DataStore, written once. Rotating them later is one command,
no republish, no commit.

### Setting it

In Studio, with API services enabled, run this in the **command bar** — once
per universe, not per session:

```lua
game:GetService("DataStoreService"):GetDataStore("Config"):SetAsync("analytics", {
	url = "https://<project>.supabase.co/functions/v1/ingest",
	key = "<the ingest key>",
})
```

The same key goes in Supabase under **Project Settings → Edge Functions →
Secrets**, as `INGEST_KEY`. The function refuses every request until it is set —
it fails closed, so an unset secret never means "no authentication".

On the next boot, Output will say:

```
[AnalyticsService] telemetry on, posting to https://...
```

If that line is missing, nothing is being recorded. This is deliberate: the
failure mode of an analytics system is being quietly off, and "no data arrived"
otherwise looks exactly like "nobody played".

### What gets recorded

One row per event in `public.events`, with the planet and level filled in
automatically. The vocabulary is `AnalyticsService.Kind` — sessions, level-ups,
deaths and where they happened, missions accepted, completed and **abandoned**,
purchases and what was actually paid, who gets talked to, secrets, and travel.

No names, no chat, no positions except the spot a character died on.

Studio playtests are recorded too, under `job_id = 'studio'`, so a developer's
fifty test deaths can be excluded with one `where` clause instead of making the
feature impossible to test.

---

## 10. Turning on free-form dialogue

Six named characters can be talked to freely instead of picking from a list —
Ordo-9, Vess, and the other four with an entry in `Config/Personas.luau`. A
`converse` edge function assembles their character sheet and calls Claude; the
Roblox server does the filtering, the counting, and every decision about what a
player has actually earned.

Like telemetry, it is **off until configured, and a fresh clone runs the whole
game normally without it** — the six characters simply keep their authored
trees, which is what every other NPC does anyway. Nothing looks broken, because
nothing is.

### The two secrets

Both go in Supabase under **Project Settings → Edge Functions → Secrets**, and
neither belongs in this repository or in the place file, for the two reasons in
§9:

| Secret | What it is |
| --- | --- |
| `ANTHROPIC_API_KEY` | From console.anthropic.com. Bills real money. |
| `CONVERSE_KEY` | Invented here; the shared secret between the Roblox server and the function. |

`CONVERSE_KEY` exists so that the endpoint, which is public and unauthenticated
by necessity, cannot be used by anyone who finds the URL to spend the API key.
The function **fails closed**: with either secret unset it answers 500 and calls
nothing, so a half-finished setup never means "no authentication".

### Setting it

In Studio, with API services enabled (step 3), in the **command bar**, once per
universe:

```lua
game:GetService("DataStoreService"):GetDataStore("Config"):SetAsync("converse", {
	url = "https://<project>.supabase.co/functions/v1/converse",
	key = "<the converse key>",
	enabled = true,
})
```

On the next boot, Output will say:

```
[ConverseService] free-form dialogue on for 6 characters
```

If that line is missing, the six are on their authored trees and the extra
"Actually — I want to ask you something." choice does not appear.

### The kill switch

Set `enabled = false` and re-run the snippet. Every running server re-reads the
config on a 60-second timer and logs
`[ConverseService] free-form dialogue OFF (config changed)` — no republish, no
restart, nobody kicked, and the conversation someone is *already* in reverts on
its next line rather than being allowed to finish. That is the whole point of
the field: at 2am the game should degrade to last week's behaviour rather than
go down.

### What Roblox requires, and where it lives

Free-form AI text has policy attached to it (the findings are in
[LIVING-NPCS.md](LIVING-NPCS.md) §6). Three of the four are in the code and stay
there:

- **The AI notice** is drawn above the text box whenever it is on screen.
- **The turn cap** is `MAX_TURNS` = 8, at the top of `ConverseService`. It is
  not a tuning knob:
  an unlimited conversation is what Roblox calls "extended AI interaction", and
  it would push this experience to a **Restricted** maturity rating. Do not
  raise it without re-reading the policy.
- **Mental-health routing** runs *before* the model, by string match, so it
  still works when the backend is down or this whole section was never done.

The fourth is yours and cannot be automated: **disclose generative AI in the
Content Maturity questionnaire** when publishing (step 7). Until you do, the
experience is mislabelled.

### What gets recorded

One row per turn in `public.conversations`: who was spoken to, what was said,
what came back, how long it took, and what it cost in tokens. Both halves of the
conversation, deliberately — the jailbreak attempts are the fun part *and* the
safety review, and those are the same reading session. A turn we declined to
send has a null `replied` and a `refused` reason, so an outage never looks like
a quiet one.

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
