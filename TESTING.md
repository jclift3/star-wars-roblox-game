# Testing

There is no way to execute Luau outside Roblox, so nothing in this project has
an automated test. `./check.sh` proves the code parses, lints and type-checks;
it cannot prove the game works. **Everything below has to be done by hand, in
Studio, by a person watching the screen.**

That makes this document the test suite. It is written so somebody who did not
write the feature can run it: each check says what to do, what should happen,
and — where it is not obvious — what a failure would mean.

---

## 0. Setting up a session

```bash
export PATH="$HOME/.rokit/bin:$PATH"
./check.sh        # must end "all clean" before you bother playing
rojo serve
```

In Studio: open an empty baseplate, connect the Rojo plugin, press **Play**.
The world builds itself on the first server frame.

**Keep the Output window open the whole time.** Most of what this project can
get wrong announces itself there rather than on screen:

| What you see | What it means |
| --- | --- |
| A red `ServiceLoader` banner listing services | One failed to start. Nothing after it in the priority order ran. Stop and read it. |
| `[ShopService] Shops: "X" stocks unknown outfit "Y"` | A config names an id that does not exist. Boot-time `validate()` caught it. Fix the config, not the service. |
| `[Net] rejected malformed "X" from <player>` | A remote got arguments it did not expect. If you were playing normally, that is a real bug. |
| Silence | Also meaningful. Several checks below are "and nothing is printed". |

### Controls

| Input | Does |
| --- | --- |
| **B** | Inventory / shop |
| **M** | Mission board |
| **K** | Skill tree |
| **G** | Galaxy map (travel) |
| **Esc** | Close the open panel |
| **Shift** | Sprint (server-authoritative — see 9.4) |
| **Mouse 1** | Fire / swing. Hold for automatics, click per shot for semi-autos |
| **E** (prompt) | Talk to an NPC |
| **1**–**9** | Pick a dialogue reply |

### Cheat codes

Typed into normal chat. **Studio or the place owner only** — they are silently
ignored for anyone else, so do not be surprised when nothing happens in a
published place under another account.

| Code | Does |
| --- | --- |
| `thereisnocow` | 10,000 credits and level 12 |
| `greedisgood` | One drop of each rarity, Common through Legendary |
| `iseedeadpeople` | Samples 5,000 drops and prints a histogram. Output window, not a toast |
| `showmethemoney` | Prints every radiant mission on every planet and which are posted today. Output window |
| `strengthandhonor` | +2,000 reputation with whoever runs the planet you are standing on, and the matching drop with their enemies |
| `iamacolyte` / `iamconscript` / `iamscoundrel` / `iamscrapper` | Sets your origin and its faction. The creation screen asks once and never again, so this is the only way to see all four travel profiles on one character |

The three printing codes are the closest thing to a test this project can run:
`greedisgood` reaches states normal play needs a thousand kills to see,
`iseedeadpeople` checks the drop maths without playing at all, and
`showmethemoney` shows what the mission generator actually composed — none of
which can be checked by reading the tables they came from.

---

## 1. Smoke test — five minutes, run it every session

If any of these fail, stop. Nothing further is worth testing.

1. The place loads with no red banner in Output.
2. You spawn on Tatooine, standing on ground, not falling.
3. WASD moves you. Shift sprints and you visibly speed up.
4. There are NPCs in sight and they are not shooting you on sight.
   *(Civilians attacking on spawn was a real bug — `Behavior.Aggressive` means
   near-universal hostility, not "tough". If it comes back, look at the
   archetype's behaviour, not at the combat code.)*
5. **B**, **M**, **K**, **G** each open a panel; **Esc** closes it; opening one
   closes the others.
6. With a panel open, clicking does **not** fire your weapon.
   *(This is `Panels.anyOpen()`. If it regresses you will empty a magazine
   into a shopkeeper while browsing his stock.)*
7. Walking out of town names the district you enter and gives its level range.

---

## 2. Bag cap, selling and discarding — **new, never played**

This shipped in `94ce9d4` and has not been in front of a person yet. It is the
highest-value section in this document.

### 2.1 The counter

1. Open **B**. The title reads `INVENTORY 0/30` (or whatever you are carrying).
2. `greedisgood`. The count goes up by the number of items it toasted.
3. Only **rolled** items count. Buy a plain blaster from a vendor — the count
   must not move. *(Plain stacks merge by catalogue id, so the catalogue itself
   is their ceiling; only rolls are unbounded, so only rolls are capped.)*

### 2.2 Filling it

1. Run `greedisgood` repeatedly until the bag is full.
2. At 30 the title turns **red**.
3. Run it again: you get `Bag full at 30. Sell something.` and no item.
4. Go and kill something. When it would have dropped, you get
   `Bag full -- left <item> behind` instead of a rarity toast.
   *(The drop really is gone — there is no ground to leave it on. The message
   is the whole compensation, so check the wording actually appears.)*

### 2.3 Selling

1. Stand next to a vendor. The vendor line at the top of **B** names the shop
   and shows its greeting.
2. Select something you are carrying. The second button reads
   `SELL — <n> CR`.
3. Press it. You get a "Sold X for n cr" toast, the credits at the top go up by
   exactly that, and the row disappears.
4. **The panel reselects something sensible** — it must not sit on
   "Nothing selected" after a sale.
5. Buy an item and immediately sell it back. **You must lose money, clearly.**
   *(If buying and selling is break-even the vendor is a bank, and the economy
   is over. `Shops.SELL_FRACTION` is 0.3 for this reason.)*
6. Sell the same item at the Jawa and at General Goods. **The Jawa pays more**
   — it is cheaper to buy from and better to sell to, because everything it
   has fell off something.
7. A Legendary sells for more than a Common of the same base item, but nothing
   like 170× more, which is how much rarer it is. Selling should never beat
   playing.

### 2.4 Discarding

1. Walk away from every vendor. Open **B**. The second button now reads
   `DISCARD`.
2. Press it once. It changes to `DISCARD — PRESS AGAIN`. **Nothing is gone.**
3. Click a different row, then come back. The button is back to `DISCARD` —
   the confirm did not survive the selection moving.
4. Press twice in a row. The item is gone and you are told so.

### 2.5 The guards — try to break it

| Try | Should happen |
| --- | --- |
| Select the item you are **wearing** | Button reads `UNEQUIP TO SELL OR DISCARD` and does nothing |
| Select the item you are **wielding** | Same |
| Select the starting outfit, or fists | **No second button at all** — they are usable without being carried, so there is nothing to remove |
| Select shop stock you do not own | No second button |
| Sell, then walk out of range mid-click | Refused: "No vendor nearby" |

The equipped guard is the important one. `profile.equipped` names a stack uid;
if a sale removed the stack it names, the uid would point at nothing and your
next respawn would hand you an empty pair of hands.

---

## 3. Rolled loot — shipped, still unverified

Carried over from `accb151` / `3ab7e9a`. The data model changed underneath
this, so the checks are mostly about *identity*: does the game still know
which of two identical-looking blasters you meant?

1. `greedisgood`, then open **B**. Rolled items are coloured by rarity, named
   with their affixes, and show roll lines **below** the base stats.
2. Equip a rolled weapon. Your damage changes. Now **die**, and respawn:
   **you are still holding it.** *(`characterReady` re-equips from
   `profile.equipped`, which names a uid.)*
3. Equip a rolled outfit, then **travel to another planet** (**G**). You are
   still wearing it.
4. Own a rolled DH-17, then buy a **plain** DH-17 from a vendor. The purchase
   must be allowed. *(The duplicate check is against the plain stack
   specifically — owning a rolled one is no reason to be refused an ordinary
   one off the shelf.)*
5. Get two rolls of the same item. They are **two rows**, and equipping one
   marks only that one EQUIPPED.
6. Run `rollreport`. Check the drop rate is about 1 in 7 kills, that Legendary
   is rare but not impossible, and that no affix rolls an absurd number at the
   top of the level range.

---

## 4. Level bands — **new, never played**

Districts now carry a level range derived from `ZoneDef.distance`, NPCs spawn
inside it, and crossing into a new district says so. **Tatooine is the clearest
test** — seven districts across levels 1–20, so every step outward is visible.

### 4.1 The banner

1. Land on Tatooine at level 1. A banner names the district you are in and
   gives its level range.
2. Walk out of town. Each district you cross into announces itself **once**.
3. Stand on the line between two districts and shuffle about. The banner does
   **not** flicker between them. *(There are no borders — "which district" is
   nearest-centre, with 80 studs of hysteresis for the one you are already in.)*
4. Open a full-screen panel while a banner is up. It hides.
5. Travel to another planet (**G**). The banner fires on arrival, even if the
   district there happens to share a name with the one you left.

### 4.2 The warning

1. At level 1, walk to Tatooine's **Dune Sea** (the furthest district). The
   banner is **red** and says TURN BACK.
2. Levels 1–3 above you get no warning; four or more does. *(`UNDERLEVELLED_BY`
   is 3 — two is a fight you might win, four is one you have already lost.)*
3. The number on the banner matches what you actually meet. Kill something in
   that district and check its level against the range you were shown. **If
   those disagree, that is the bug** — both come from `Planets.bandFor`, so
   they cannot disagree unless something is reading the wrong zone.

### 4.3 Levels rise as you walk out

1. Walk Tatooine outward and check nameplate levels district by district. They
   go up. Roughly: Town 1–6, Market 4–9, Cantina 5–10, Farmstead 8–13,
   Wastes 10–15, Palace 12–17, Dune Sea 15–20.
2. Bands **overlap** on purpose, so the far edge of one district and the near
   edge of the next are similar. A cliff between districts would be the bug.
3. Jawas in the deep desert are **not** level 18. *(The band narrows the
   archetype's own range instead of replacing it — a Jawa sits at the top of
   what a Jawa can be.)*
4. Check a short-range planet: **Tython** is only 30–36, **Dromund Kaas** 46–50.
   Their bands should still step outward rather than collapsing to one number.
   *(`BAND_MIN_WIDTH` is 2.)*
5. Watch the Output window at boot for `zone "..." has an inverted band` or
   `... is outside the planet's ...`. Neither should appear.

---

## 5. World layout — **new, never played**

Both fixes landed in `1c265f2` off screenshots. **Nar Shaddaa is the worst
case for both** — test it first and Tatooine second.

### 5.1 Doors face the way you arrive

1. Walk the road into an out-of-town landmark. **The road arrives at the front
   door**, not at a blank wall with the entrance round the side.
2. Walk from the plaza to an in-town landmark. Same: the door faces you.
3. Go inside a building that has an interior. The standing room is **inside**,
   not buried in a wall. *(The interior offset is written in the builder's own
   frame and has to be rotated with the building. If someone is standing in a
   wall, that rotation is what to look at.)*

### 5.2 Crowds are spread out

**This is the one that failed on 2026-08-16** — the Promenade market was an
empty street. Landmarks were being pushed *past* their district's patrol ring,
and the ring widens with population, so the busiest districts threw their own
landmark furthest from the crowd. Landmarks now go down first and the ring is
drawn around them. Steps 1 and 5 are the fix.

1. Land on **Nar Shaddaa** and walk to the market (the billboard reads *The
   Promenade*). It should be **busy** — 44 people ringed around you at 88–187
   studs, not an empty street with everyone behind you.
2. Nobody is standing inside a house or half-sunk in one. *(Patrol points are
   snapped onto the street grid, which is the only part of town guaranteed
   clear. Someone inside a building means the snap missed.)*
3. Follow one NPC for a while. Their patrol is a **walk around the district**,
   not a zigzag across it. *(Points are sorted by name to build the route and
   are zero-padded for exactly this reason — `Point10` sorts between `Point1`
   and `Point2`.)*
4. Compare a busy district with a quiet one. The busy one is visibly *wider*,
   because the ring grows with the population rather than being fixed.
5. Every district's landmark has its people **around** it, and nobody is
   standing *in* the building. Check a wide one too — the Docks spaceport is
   radius 116, so its ring has to open up to 146+ rather than the building
   moving. *(A few NPCs inside a market or cantina is fine and rather the
   point; a Jedi standing in the middle of the Tython temple wall is not.)*
6. Check a district with **no** landmark at all — Nar Shaddaa's *Market* zone
   is one (the merchants and protocol droids; the market *building* is in the
   Promenade, confusingly). Its crowd still rings the district centre rather
   than collapsing to a point.

### 5.3 "A landmark looks missing"

It is always distance or fog, never terrain. Before filing it: fly to the
coordinates, check the nameplate is visible at range, and check `Lighting`'s
fog end. Everything is built on the first server frame; nothing is streamed in
late.

---

## 6. Travel and origins

1. **G** opens the galaxy map and lists all 9 planets: Tatooine, Korriban,
   Taris, Nar Shaddaa, Coruscant, Ord Mantell, Tython, Hoth, Dromund Kaas.
2. Travel to each one in turn. **Every one loads and you land on ground.**
3. Gravity differs by planet and it is noticeable when you jump.
4. Tatooine has **two suns**. The companion sun is a Neon ball parented to the
   camera, so it must hold its offset as you turn — if it drifts, that is the
   bug.
5. Try each origin (`iamacolyte` and friends) and travel. Each has a different
   *mechanism* and cost.
6. Travel while wearing and wielding rolled gear. You keep both (this overlaps
   3.3, and it is worth doing twice).

### 6.1 Character creation — **new, never played**

Four origins, four home worlds and four factions were authored and every
character was `Origins.DEFAULT`, because nothing ever wrote the field. **Needs a
profile that has never chosen** — in Studio every session is fresh, so this
fires on its own; against a live save, wipe the profile or use a new account.

1. Join. Before anything else, **WHO WERE YOU** fills the screen: four origins
   on the left, the selected one described on the right with its home world,
   faction and skill tree.
2. **It cannot be dismissed.** Escape does nothing. Press **B**, **M**, **K**,
   **G** — the creation screen stays on top and in front. That is the test; a
   panel that could be closed would never come back this session and the
   character would be a Scoundrel forever.
3. Each origin's right-hand pane states its *travel trade-off before you pick*
   (the Acolyte flies Imperial space free and pays double everywhere else).
   A permanent choice that hides its cost is the bug.
4. Pick **Sith Acolyte**. You respawn on **Korriban**, and the toast names it.
5. **Nobody at the Academy shoots you.** This is the real test of the whole
   change: your Empire reputation is 0, every Aggressive archetype treats
   "not Friendly" as a target, and only `profile.faction` stops it. Pick
   Conscript on another character and check Ord Mantell the same way.
6. **G** — the standing line now reads `Sith Empire: Recruit`, and the two
   Imperial worlds quote **no fare**.
7. Rejoin. **You are not asked again**, and you are still an Acolyte.
8. Scoundrel starts on **Tatooine**, not Nar Shaddaa. Nar Shaddaa is a level 12
   world; if a future origin's home world is above level 1, `Origins.validate`
   says so in the output window at boot.

### 6.2 Faction standing — **new, never played**

Reputation already decided who shoots you, which missions exist and how NPCs
greet you, and the player could see none of it; every rank also carried a
`creditStipend` that nothing had ever paid. Both were live systems the player
had no evidence of.

1. **G**, and pick any world. Under the description is a **standing line**:
   `Sith Empire: Recruit  ·  0/250`. On a fresh character every world reads as
   the bottom rank of whoever runs it, in plain white.
2. The line above it now reads `{region}  ·  Levels {min}-{max}` — the level
   band moved up to make room. Check the faction is named in **words** ("Sith
   Empire"), not as an id ("Empire"), which is what it used to print.
3. Type `strengthandhonor`. It grants 2,000 rep, which on the Empire ladder
   clears Trooper (250), Corporal (750) and Sergeant (1,800) in one go. Expect
   **one promotion toast naming the top rank reached, with the credits in the
   same message** — and the total should be **all three stipends summed**
   (100 + 250 + 500 = 850 cr), not just the last one. Watch the credit counter
   actually move by that amount.
4. Reopen **G**. The standing line for that world has climbed, and **at least
   one other world has gone red and reads HOSTILE** — that is spillover, and it
   is the half of reputation nothing else shows you.
5. Type `strengthandhonor` **three or four more times**. Each new rank pays
   exactly once and the amounts climb with the ladder. If a rank you already
   hold ever pays a second time, that is the bug this was built to prevent.
6. Travel to the world that went red. **The locals should open fire on sight** —
   the same NPCs who ignored you before. This is the point of the whole system.
7. Rejoin the game and check **G** again. Standing survives; and crucially, the
   promotions you were already paid for **do not pay again on login**.

Also worth one look: the row list. A hostile or friendly world says so in its
subtitle; a neutral one says nothing, on purpose — printing "NEUTRAL" on eight
worlds out of nine buries the one that matters.

---

## 7. Missions

1. **M** opens the board. Missions are listed per planet with their rewards.
2. Accept one. It appears in the HUD. *(All active missions render there —
   there is no "track" button, deliberately.)*
3. Complete a **Kill** objective. The counter goes up per kill and the mission
   completes at the target.
4. Complete a **Collect** and a **Deliver** objective.
5. Complete a **TalkTo** objective. The report fires once per NPC, not once
   per line of dialogue.
6. Abandon a mission and re-accept it. Progress resets cleanly.
7. **Credits and XP arrive exactly once.** *(`Inventory.remove` returns what it
   actually took, and the payout is against that return, not the request. A
   double payment here means somebody paid against the request again.)*

**Known open — do not file these:** the Escort / Survive / Slice / Destroy
objective kinds have no server reader.

### 7.1 Radiant missions — **new, never played**

Generated from the spawn tables and points of interest, so every planet has some
— including the four that shipped with none. Their names are **Thinning the
&lt;district&gt;**, **Salvage from &lt;place&gt;** and **Survey: &lt;place&gt;**.

1. Run `showmethemoney` first and read the output window. Every planet should
   list some. Look for anything silly — a Survey of somewhere you can see from
   the giver, a district with nothing in it, a giver who makes no sense for the
   job. **That output is the actual test**; the rest of this section is
   confirming the world matches it.
2. **M** on Tatooine. Three generated missions sit alongside the authored ones.
   Take a **Thinning the …** one and check the enemy it names really does spawn
   in that district.
3. Take a **Salvage from …** one. The items are on the ground at the place it
   names, and the delivery point is in town.
4. Take a **Survey: …** one. It is somewhere out past the edge of town, not
   next door.
5. Finish one and re-open the board. It says **Available again in N min**
   rather than vanishing — they are repeatable on an hour's cooldown.
6. Talk to the giver the printout named. The same missions are offered in
   conversation, not only on the board.

**Same postings for both players.** Rotation is per day, not per player, on
purpose: if you and your brother stand at the same board you must see the same
three. Different lists is a bug, and a bad one.

---

## 8. Dialogue and NPCs

1. Walk up to an interactable NPC. A proximity prompt appears; **E** starts the
   conversation.
2. The dialogue box is at the bottom and **you can still see the world**. It is
   not full-screen on purpose.
3. Number keys 1–9 pick replies. Check a tree with more than three.
4. A mission-giver offers their missions inside the conversation. These are
   *derived* from the board filtered by giver — if one is missing, the mission
   is the problem, not the tree.
5. **Esc** ends the conversation and returns control.
6. Shoot a shopkeeper dead, then try to trade with the corpse. Refused.

---

## 9. Combat and progression

1. Blasters: an E-11 fires while held, a DL-44 needs a click per shot.
2. A lightsaber swings and blocks.
3. NPCs notice you at a believable distance and not across the map.
   *(Line-of-sight aggro already existed; the bug was `sightRange` at 120–300
   studs, which is most of a settlement.)*
4. **Sprint is server-authoritative.** In the client console, try to set your
   own WalkSpeed. The server should put it back. *(The original prototype set
   sprint speed client-side with no check at all, which is the single reason
   `Net` is written the way it is.)*
5. Kill things until you level up. XP, credits, level and skill points all move.
6. **K** spends a skill point. The button explains *why* when it refuses.
7. Wear armour and take a hit. You take less damage.
   *(`DamageReduction` is applied in `CombatService.applyDamage`.)*

### 9.1 Deflection — **new, never played**

`DeflectChance` was a dead stat until 2026-08-16 and is now a real mechanic.
`thereisnocow` gets you to level 12; `iamacolyte` is not required.

1. **K** → Force tree. Buy **Force Sensitive** — it costs **one** point now, is
   marked `Unlocks this tree`, and shows no percentage. Then Lightsaber Form,
   then **Deflection** (level 11). Take a rank or two.
2. Equip a lightsaber. Get shot at by something with a blaster — Imperial
   Troopers on the Nar Shaddaa Docks will do.
3. Some bolts show a **"Deflected!"** toast and deal **zero**. Not reduced —
   zero.
4. **Holster the sabre** (equip a blaster) and get shot again. No deflections
   at all. *(This is the trade that makes it a build rather than a buff.)*
5. Get hit by something **melee** — a Tusken Raider on Tatooine. Never
   deflected, however many ranks you have.
6. Five ranks is 45%, so roughly two bolts in five. If it feels like *every*
   bolt, the cap or the roll is wrong.

**Known open — do not file:** 6 of 19 skills still have no reader, the whole
Piloting tree included. They now show **COMING SOON** and refuse the point
rather than taking it — that refusal *is* the correct behaviour.

---

## 10. Persistence — needs two sessions

The only checks that cannot be done in one sitting.

1. Play, earn credits, buy gear, equip a **rolled** item, accept a mission.
2. Leave. Rejoin.
3. Credits, level, skill points, inventory, equipped gear and mission progress
   all survive.
4. Equipped gear survives *specifically as the same roll* — not the plain
   version of the same item.
5. **Load a save made before the inventory rewrite.** `PROFILE_VERSION` is 2
   and `Inventory.load` still reads the old `{ [id]: count }` shape.
   `equipped.weapon = "DH17"` must still resolve, because a plain item's uid is
   its catalogue id.
6. A bag that is **over** the cap comes back **whole**, not truncated, and
   simply refuses the next drop. *(Deliberate: `load` never applies the cap.)*

---

## 11. Known open — expected, not bugs

Do not spend time filing these. They are on the roadmap.

- An origin is asked once and never again — there is no respec and no way to
  change it in-game. The cheat codes are the workaround.
- The origin does **not** seed a skill point into its tree, because every
  Piloting node is `unimplemented` until ships exist and the Scoundrel would be
  paid in nothing.
- Faction reputation is spent on hostility, mission access, dialogue and the
  rank stipend, and **nowhere else** — no vendor prices you differently, no door
  opens because you are a Captain, and there is no jail (ROADMAP N2).
- The skill trees are almost all flat passives. Deflection is the first one
  that changes how you play; nothing else rewards specialising yet.
- Radiant missions have no authored dialogue of their own — the giver offers
  them, but the briefing text is generated and the same shape every time.
- `MONETIZATION_STRATEGY.md` is stale legacy and describes a game that no
  longer exists.

---

## Reporting a finding

Worth writing down, in this order:

1. **Planet and where** — most world bugs are one planet's data, not the
   builder.
2. **Exactly what you did**, including which panel was open.
3. **The Output window**, copied. A warning printed thirty seconds before the
   symptom is usually the actual bug.
4. A screenshot, for anything about layout or placement. The two world fixes in
   §5 both came from screenshots and neither would have been found in words.
