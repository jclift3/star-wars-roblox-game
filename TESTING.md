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
| **Shift** | Sprint (server-authoritative — see 8.4) |
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
| `rollreport` | Samples 5,000 drops and prints a histogram. Output window, not a toast |
| `iamacolyte` / `iamconscript` / `iamscoundrel` / `iamscrapper` | Sets your origin, which is the only way to see the four travel profiles until a character-creation screen exists |

`greedisgood` and `rollreport` exist because they are the closest thing to a
test this project can run: one reaches states normal play needs a thousand
kills to see, the other checks the drop maths without playing at all.

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

## 4. World layout — **new, never played**

Both fixes landed in `1c265f2` off screenshots. **Nar Shaddaa is the worst
case for both** — test it first and Tatooine second.

### 4.1 Doors face the way you arrive

1. Walk the road into an out-of-town landmark. **The road arrives at the front
   door**, not at a blank wall with the entrance round the side.
2. Walk from the plaza to an in-town landmark. Same: the door faces you.
3. Go inside a building that has an interior. The standing room is **inside**,
   not buried in a wall. *(The interior offset is written in the builder's own
   frame and has to be rotated with the building. If someone is standing in a
   wall, that rotation is what to look at.)*

### 4.2 Crowds are spread out

1. Land on **Nar Shaddaa**. The Promenade is 44 NPCs. They should read as
   *people along streets*, not a knot on the landing plaza.
2. Nobody is standing inside a house or half-sunk in one. *(Patrol points are
   snapped onto the street grid, which is the only part of town guaranteed
   clear. Someone inside a building means the snap missed.)*
3. Follow one NPC for a while. Their patrol is a **walk around the district**,
   not a zigzag across it. *(Points are sorted by name to build the route and
   are zero-padded for exactly this reason — `Point10` sorts between `Point1`
   and `Point2`.)*
4. Compare a busy district with a quiet one. The busy one is visibly *wider*,
   because the ring grows with the population rather than being fixed.
5. Landmarks sit **outside** the patrol ring — no NPC is standing on top of a
   building's front step.

### 4.3 "A landmark looks missing"

It is always distance or fog, never terrain. Before filing it: fly to the
coordinates, check the nameplate is visible at range, and check `Lighting`'s
fog end. Everything is built on the first server frame; nothing is streamed in
late.

---

## 5. Travel and origins

1. **G** opens the galaxy map and lists all 9 planets: Tatooine, Korriban,
   Taris, Nar Shaddaa, Coruscant, Ord Mantell, Tython, Hoth, Dromund Kaas.
2. Travel to each one in turn. **Every one loads and you land on ground.**
3. Gravity differs by planet and it is noticeable when you jump.
4. Tatooine has **two suns**. The companion sun is a Neon ball parented to the
   camera, so it must hold its offset as you turn — if it drifts, that is the
   bug.
5. Try each origin (`iamacolyte` and friends) and travel. Each has a different
   *mechanism* and cost. Everyone is a Scoundrel by default until there is a
   creation screen.
6. Travel while wearing and wielding rolled gear. You keep both (this overlaps
   3.3, and it is worth doing twice).

---

## 6. Missions

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

**Known open — do not file these:** Dromund Kaas has no missions at all, and
the Escort / Survive / Slice / Destroy objective kinds have no server reader.

---

## 7. Dialogue and NPCs

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

## 8. Combat and progression

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

**Known open — do not file:** 6 of 19 skills have no reader at all, the whole
Piloting tree included. They will visibly do nothing.

---

## 9. Persistence — needs two sessions

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

## 10. Known open — expected, not bugs

Do not spend time filing these. They are on the roadmap.

- No character-creation screen, so every profile is `Origins.DEFAULT`
  ("Scoundrel"). The cheat codes are the workaround.
- Faction reputation is awarded and never read back by anything.
- No level bands on zones, so no "you are underlevelled" warning on entry.
  Walking outward does not reliably mean walking into harder things yet.
- The skill trees are all passives. Nothing rewards specialising.
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
   §4 both came from screenshots and neither would have been found in words.
