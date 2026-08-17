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
4. Walk a level 1 Scrapper into Taris's **Dig**. The band still reads 4–13,
   but there is **no red and no TURN BACK** — the only things spawned there
   are Jawas, researchers and a droid. *(Fixed 2026-08-16 off a playtest: the
   band is derived from distance out of town, which is right for danger and
   wrong for errands, so the alarm is now gated on the district actually
   holding something aggressive. The Scrapper prologue sends you here.)*

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
   `... is outside the planet's ...`. Neither should appear. Since 2026-08-16
   three more lines can show up there, and each is a real finding: `"X" is level
   a-b but "Zone" bands c-d` (an archetype that cannot reach its own district),
   `nothing on this planet is Aggressive`, and `level N costs X XP but only Y is
   reachable`. See §9.2 and §9.3.

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

### 5.4 The ground is terrain — **new, never played**

The answer to "why is everything still so blocky". Every walkable world's land
is now voxel terrain instead of one grey plate, with hills beyond the play
area. **The failure mode to hunt for is things buried in it.**

1. Stand in the middle of town on **Tatooine**. The ground is textured sand you
   cannot see the edge of, not a flat slab, and there is **no seam or step**
   where the plaza paving meets it.
2. Look at the horizon in every direction. Mesas, in the same colour family as
   the ground, with a skirt at their bases rather than a hard corner meeting
   the plain.
3. Walk out past the last houses toward the **Dune Sea** (the outermost
   district, 832 studs out). The ground stays **dead level** the whole way to
   it. Dunes only begin past that.
4. **The important one.** Fast-travel to **Korriban** and walk to the *Wastes*
   (its outermost district, 1,352 studs — the furthest of any world). Its
   landmark sits on flat ground with its base visible, and its NPCs are
   standing **on** the ground. Nobody is waist-deep, sunk to the neck, or
   invisible. Repeat on **Taris**' Undercity and **Tython**'s Forge Ridge.
   *(This is the whole reason the flat radius is computed per planet. If people
   are buried, `flatRadiusFor`'s margin is too small — a downward raycast that
   starts inside terrain returns nothing at all.)*
5. Drop a quest item near the edge of town and walk to it. It is on the
   surface, not inside a swell.
6. Shoot at the ground. Bolts stop at it. Walk up a swell — you can climb it,
   it is not a wall.
7. **Travel twice and look back.** Go Tatooine → Korriban → Tatooine. Tatooine's
   sand is still Tatooine's colour. *(Both are desert worlds and
   `Terrain:SetMaterialColor` is global, so they deliberately use different
   materials. If the dunes come back grey-red, two planets are sharing one
   material and `Planets.validate` should have said so at boot — check the
   output window.)*
8. **Hoth**: the terrain is snow and the hills are `Glacier`, but its fog is a
   900-stud whiteout by design, so you will barely see them. That is correct.
9. **Coruscant** has no walkable ground at all — it should be unchanged, a
   vertical city with no terrain anywhere.
10. Watch the frame rate on arrival at a big world (Korriban, Taris). A short
    hitch as the planet builds is expected and happens once per world per
    session; a sustained drop afterwards is not.

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

### 6.1a Prologues and origin-only lines — **new, never played**

The payoff for 6.1: the origin has to change the first hour, not a line of stat
text. Do this on the character you just made.

1. **M** on your home world. Exactly one prologue is on the board and it is
   yours — *The Empty Bunk* on Korriban, *The Other Copy* on Ord Mantell, *The
   Manifest* on Tatooine, *The Sealed Crate* on Taris.
2. **The other three are not listed at all**, not greyed out. Check the two
   worlds that carry somebody else's prologue: an Acolyte on Tatooine must not
   see *The Manifest* anywhere on the board. A locked entry you can never unlock
   is worse than no entry — that is why this one refusal hides.
3. Take it and finish it. Three objectives, no combat, and the tracker names the
   points of interest. On Ord Mantell and Tatooine it hands off to that world's
   existing level-1 chain (*Pay and Rations*, *Dust and Droids*).
4. Talk to any **Civilian**, on any planet. One line in the menu is written for
   your origin and only yours — "You are afraid of me." for the Acolyte, "Who do
   you owe?" for the Scoundrel. Check a second character sees a different one and
   never both.
5. If a prologue or a line names an origin that does not exist, `Missions.validate`
   and `Dialogue.validate` say so at boot. Nothing else would: the mission would
   simply be absent from every board and the line from every menu.

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

### 7.0a Finding the thing you were sent for — **changed 2026-08-16**

The playtest report was "I'm seeing no way to salvage… I went to the way point
but doesn't instruct me what I should be doing". Three things changed.

1. Accept a mission with a **Collect** step. Follow the waypoint. It now names
   the **nearest crate**, not the landmark — walk it all the way down and you
   end up standing on an item, not in an empty courtyard.
2. Each crate carries a **floating name tag** readable through walls from about
   140 studs. From the landmark you should be able to see where the pile is
   without hunting. **If you can reach 0 studs on the beacon and still not see
   a tag, that is the bug.**
3. The **E** prompt now reaches 18 studs rather than 12. You should not have to
   nudge about to find the exact spot that lights it up, even under an overhang.
4. Take one. The counter moves, and after 45 seconds another appears — the pile
   is shared and refills, so both of you can work the same one.

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

### 8.1 Choices that stick — **new, never played**

Alignment and flags landed 2026-08-16. Before this the game could not remember
anything you *decided*, only what you had finished, so all of this is unplayed.
`thereisnocow` reaches level 12, which is where the fork opens.

1. **The number exists and has a name.** Open **K**. Top right of the header
   reads a band and a signed figure — `Unaligned  (+0)` on a fresh character.
   It is on the skills panel and deliberately not on the HUD.
2. **A conversation can move it.** Find a **Cartel Enforcer** on the Nar Shaddaa
   Promenade collecting a debt. Two of the replies cost or earn alignment;
   pick one. A toast reports the change, and **K** shows the new figure.
3. **It happens once.** Talk to the *same* enforcer again. Both paying replies
   are gone — the free `Not my business.` exit stays. Then talk to a
   **different** enforcer (there are eighteen on that Promenade). The paying
   replies must be gone there too. **If any enforcer still offers them, that is
   the exploit this whole system was built to make impossible** — the boys will
   find it in about four minutes.
4. **Crossing a band says so.** Keep taking the same kind of choice until the
   figure crosses ±100. A second toast reads `You are becoming Decent.` (or
   `Callous.`). Only band changes announce themselves, not every point.
5. **The fork.** At level 12 on Coruscant the board offers **both** *Loyalty
   Check* (an officer wants the underlevels cleared) and *The Warning* (a
   smuggler wants them emptied first). Take one and finish it. **The other must
   disappear from the board**, and the reason on it, if it shows one, is the
   deliberately vague *"Not the road you took"*.
6. **The world knows.** After that mission, talk to an **Imperial Officer** and
   a **Civilian** on Coruscant. Each has a line that only exists because of
   which one you took. Two characters who took opposite paths should hear
   different sentences from the same NPC.
7. **The prologues are remembered.** Finish your origin's prologue, then find a
   **Researcher**. They should say something about the specific thing you saw —
   the intake form, the second copy of the paperwork, the fourteen crates. One
   line only; they must not stack.

*(A missing line here is almost always a **flag id typo**, and that class of
bug is supposed to be impossible now: `Config/Flags.luau` declares every flag
and both `Missions.validate` and `Dialogue.validate` check them at boot. So
check the server log at startup **first** — if it is silent, the flag is fine
and the condition is what is wrong.)*

### 8.2 The recurring cast — **new, never played**

Six named characters landed 2026-08-16. Until then they existed only as names in
briefing text. `iam{acolyte,conscript,scoundrel,scrapper}` switches origin and
`thereisnocow` levels, which is how you see the other three-quarters of each
tree without four playthroughs.

1. **They are where they say they are.** Six characters, one visit each:
   **Overseer Vashk** (Korriban, Academy), **Sergeant Tolen Marr** (Ord Mantell,
   Garrison), **Vess Kadar** (Nar Shaddaa, Promenade), **Ordo-9** (Taris, Camp),
   **Master Ryn Solaa** (Tython, Temple), **Doctor Aneth Corr** (Taris, Lot 9).
   Each has their own name over their head, not a rolled one, and a **Talk**
   prompt.
2. **The ceiling did not eat them.** `MAX_NPCS` is a real limit and the cast are
   spawned *before* the crowd so they win it. Check all six on a full server,
   not an empty one — a missing character with a silent boot log is this.
3. **Their body is borrowed and their behaviour is not.** Vashk wears Sith Lord
   armour and Ordo-9 is an armed war droid. **Neither may attack you**, on any
   origin, at any reputation. This is the single most likely thing to be wrong.
4. **Killing one does not un-name them.** Shoot a cast member (they are levels
   26–45, so this needs cheats or patience), wait out the respawn, and talk to
   whoever comes back. It must still be **Overseer Vashk** with his own
   conversation — not an anonymous hostile Sith Lord.
5. **They know which origin you are.** Talk to Vashk as an Acolyte, then
   `iamscoundrel` and talk to him again. The opening reply is different: one is
   the man who raised you, the other is a stranger in his Academy. Same test for
   Tolen Marr (Conscript), Kadar (Scoundrel) and Ordo-9 (Scrapper).
6. **They remember your prologue.** With the matching origin's prologue
   finished, the mentor has an extra reply about the specific thing you saw.
   Without it, that reply is absent — not greyed, absent.
7. **Naming the Quiet.** At level 20+, Master Ryn Solaa offers *Say what it is.
   Out loud.* Take it. Then talk to **Vashk**, **Tolen Marr** and **Aneth Corr**:
   each has a line that only exists once someone has said the word. Go back to
   Solaa — the choice must be **gone**, not repeatable.
8. **The boot log is silent.** `Cast.validate` runs from `DialogueService` at
   startup. Any `[DialogueService] cast config:` line means a cast member points
   at a planet, zone, archetype or dialogue tree that does not exist, and that
   character will be missing or mute in-game.

### 8.3 The signature chains — **new, never played**

25 missions landed 2026-08-16, four chains, levels 12–34. This is the longest
piece of content in the game and the one with the most ways to be silently
broken, because **a mission whose objective can never be reported looks exactly
like a hard one**. `iam{acolyte,…}` picks the chain, `thereisnocow` gets you to
the level gate, `showmethemoney` covers the Scoundrel's debt.

1. **The boot log is silent.** `Missions.validate` checks every item, POI,
   archetype, flag and faction id in all 25. One `[MissionService] mission
   config:` line and something in a chain cannot be finished. Read them all —
   they are sorted, so a chain with three problems shows as three lines.
2. **Each chain opens at 12 and only for its own origin.** As an Acolyte at 12
   the board shows *The Hilt*; `iamconscript` and it is **gone, not greyed** —
   `boardFor` hides an origin refusal because it can never stop being true.
   *Sponsorship*, *Bought and Paid For* / *Worked Off*, and *The Chassis* are
   the other three openers.
3. **Every objective can actually be completed.** The real test and the slow
   one: play one chain end to end without cheating past an objective. Watch for
   a **Collect whose crates never appear** (the `at` POI is on the wrong planet)
   and a **Reach that never fires** (the POI exists but nothing put a marker
   there). The HUD tracks all active missions, so an objective that will not
   tick is visible without opening the board.
4. **The forge is a fork, not a menu.** At level 30 with the crystal, an Acolyte
   at **-100 or below** sees only *The Bleeding*; between **-99 and +99** only
   *Neither Hand*; at **+100 or above** only *What It Already Was*. Check all
   three with `iamacolyte` and alignment moved by the level-12 Coruscant fork
   plus whatever else. **There must be no alignment at which none of the three
   is offered** — that is a character who can never finish their own chain.
5. **The second saber.** Take *Neither Hand* (purple, pays no alignment), then
   run light-side content until you are at +100, and go back to Forge Ridge.
   *What It Already Was* must **not** be on offer. This is the exploit the boys
   will find first and the reason all three forbid `SaberBuilt`.
6. **The blade is the right colour.** The reward equips and lights: red from the
   tomb, violet from the ridge, blue from the ridge. Not a shop item — check
   `B` and confirm no vendor anywhere sells a lightsaber.
7. **The other three forks close too.** Beskar in vengeance-colour then try for
   duty-colour; clear the debt by paying then try to clear it by working;
   restore Ordo-9 then try to leave him as he is. Each must refuse with **"Not
   the road you took"** and never name the branch you did take.
8. **The components stay in the bag.** The chains close on a `Reach`, not a
   `Deliver`, so the hilt, lens, crystal, writ, ingot, hull plate and drive core
   are all still in `B` at the end. The two deliberate exceptions are the debt
   payments and Ordo-9's memory core, which are *supposed* to leave.
9. **Ordo-9 talks like a droid throughout.** Statement:/Query:/Observation:. If
   he sounds like a person, a line came from the wrong tree.
10. **Somebody notices.** The point of the whole chain. After finishing one, go
    back to its cast member and check the new reply exists **and is the right
    one**:
    - **Vashk** and **Ryn Solaa** both react to the saber, and *differently* —
      red, violet and blue each get a line from each of them, so six lines and
      you can only ever see two per character.
    - **Tolen Marr** reacts to the beskar, then asks what colour it was struck
      in; the follow-up is one of two.
    - **Vess Kadar** reacts to *how* the debt was answered, and once the ship
      flies that replaces it — the debt line must be **gone**, not stacked
      underneath.
    - **Ordo-9** reacts to himself. Restored, he is an HK unit declining to be
      one; left as he is, he knows you told him so.
    A reply that never appears is a `Condition` reading a flag the mission never
    set, and there is nothing on screen to distinguish it from a line nobody
    wrote — which is why the flags are declared in `Flags.luau` in the first
    place. Cross-check against the boot log being silent (item 1).

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

### 9.2 There is something to fight — **changed 2026-08-16**

The playtest report was *"I'm not exactly seeing enemies or anything so I'm not
sure why my level would be too low"*, and it was literally true: 812 NPCs
existed in the galaxy and **43** of them would ever attack you. Six of the nine
worlds contained nothing hostile at all. That is now **271 across all nine**, so
these steps are the ones most likely to find something wrong.

1. **Every planet has a fight on it.** Walk out of town on each world in turn.
   Somewhere past the middle district something should shoot at you without
   being provoked. If a planet is still peaceful all the way to its edge, that
   is a bug — and `Planets.validate` should have said so in the output log at
   server start, so check there first.
2. **Town is still safe.** Anchorhead, Kaas City, Fort Garnik's garrison, the
   Dreshdae spaceport, Aurek Base and the Tython temple should all be places you
   can stand still in. **A hostile inside a hub is a bug.**
3. **The Sith Academy on Korriban is safe.** This one matters most: it is where
   the Acolyte origin opens its eyes, and eighteen aggressive level 22 Sith used
   to be standing on that exact spot. They will still duel you if you swing
   first. They must not open with it.
4. **The Taris Dig is safe** — see §4.2. The Scrapper prologue goes there.
5. **Levels rise as you walk out and the enemies match.** Check a nameplate in
   each district of one planet. Korriban runs Academy 1–12, Dreshdae 9–20,
   Valley 19–30, Tombs 27–38, Wastes 35–46. *(An enemy pinned to exactly the
   same level everywhere in a district means its archetype cannot reach that
   band — the old war droids capped at 12 while standing in a 35–46 zone.)*

### 9.3 The levelling curve — **changed 2026-08-16**

Reaching level 50 used to cost **1,040,647 XP** while the entire galaxy was
worth 21,480 a sweep. It now costs about **380,000**, and the galaxy pays about
100,000 a sweep plus 33,000 in authored missions.

1. `thereisnocow` no longer needs to exist to see the mid game. Play a fresh
   character and just do the story. **Levels 1–10 should arrive quickly** — the
   first is 100 XP and the tenth about 1,900.
2. **No stretch should feel like a wall.** The old thin spot was 10–16, where
   the reachable content was about a third of what level 17 could reach. It is
   filled now (Tatooine's Wastes and the Taris Sinking Sector both got hostile
   scavengers). If levelling stalls hard somewhere, **write down the level** —
   that number is the whole bug report.
3. At the cap end, expect a grind: 43 is the tightest level in the game at about
   1.2 sweeps of everything in range. That is intended; it is the Diablo part.
4. `Planets.validate` checks the curve against the world **at every level** on
   boot. A `level N costs X XP but only Y is reachable` line in the log means
   the content moved out from under the curve — that is a real finding.

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
7. **Alignment and flags survive.** The figure in **K** is what it was, and the
   choice from §8.1 is still closed — the enforcer does not offer to be paid a
   second time after a rejoin.
8. **A save from before 2026-08-16 loads.** It has neither field; it should come
   back at `Unaligned  (+0)` with no flags rather than erroring.

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
