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
| **J** | Journal (what you have already done) |
| **K** | Skill tree |
| **G** | Galaxy map (travel) |
| **Esc** | Close the open panel |
| **Shift** | Sprint (server-authoritative — see 9, step 4) |
| **Mouse 1** | Fire / swing. Hold for automatics, click per shot for semi-autos |
| **Mouse 2** (hold) | Aim. Over-the-shoulder camera, mouse locked to a reticle, character faces where you are looking |
| **E** (prompt) | Talk to an NPC |
| **1**–**9** | Pick a dialogue reply |
| **1**–**6** | Use an ability — but only when no panel and no conversation is open |
| **V** | Call in / put away the selected vehicle |
| **H** | Board / leave your ship's cabin — starships only, and only near your own hull |
| **W/S**, **A/D** (seated) | Throttle, steer |
| **Space** / **LeftCtrl** (seated) | Climb, dive — starships only; releases both levels you off |

**The game now says all of this itself**, in a legend across the top-left corner
that is built from `Panels.ALL` rather than typed out. This table is for the
person running the tests; the legend is for the player who has never read it.
Reported from play, 2026-08-17 — someone who had finished a mission still did
not know the skill tree existed. If a key here and the legend ever disagree, the
bug is in this file: `Panels.luau` is the one place either of them comes from.

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
5. **B**, **M**, **J**, **K**, **G** each open a panel; **Esc** closes it;
   opening one closes the others.
6. With a panel open, clicking does **not** fire your weapon.
   *(This is `Panels.anyOpen()`. If it regresses you will empty a magazine
   into a shopkeeper while browsing his stock.)*
7. Walking out of town names the district you enter and gives its level range.

---

## 1b. What the game tells a new player — **new, never played**

Needs a **fresh character** — Studio's DataStores are memory-only, so stopping
and restarting Play is enough. Everything here is text on a screen; none of it
can be checked by reading the code, because the question is whether a boy who
has never played this reads it and knows what to do.

1. The creation modal appears with no key pressed, and refuses to close until
   you pick an origin.
2. Pick one. The card names your mentor, then reads: *"Press M for work that
   needs doing, and J for who you are and what you have learned so far. 1 skill
   point is already waiting under K."*
   - **The letters must match the ones the legend shows.** They are read from
     `Panels.toggleKey`, not typed, so a mismatch means the registry and the
     legend disagree — a real bug, not a typo.
3. Dismiss the card. The legend across the top now starts **LMB ATTACK** ·
   **SHIFT SPRINT** · **1-6 POWERS**, then V, H, and the five panel letters.
   - **"SHIFT" fits inside its box**, not clipped or overflowing. The box has
     three widths and this is the only row that needs the widest.
4. Press **K**. The subtitle reads **"Level 1 · 1 skill point"** in the accent
   colour, and at least one rank is affordable. Spend it; the subtitle goes to
   "0 skill points" and dims.
   *(Before this change nothing in the game ever mentioned that point. The
   level-up toast only fires on a level gained, and this one arrives at
   creation.)*
5. Hold **shift** and run. You visibly speed up. (Also smoke test §1.3 — it is
   here as well because now something on screen claims it.)
6. Click the left mouse button with an enemy in front of you. You attack.
7. Reach level 2. The toast still announces the point *that* level granted; the
   creation card's sentence has not doubled it up or replaced it.

**The point of this section is that nothing here is new machinery.** Both fixes
are extra lines in surfaces that already worked, so the failure mode to watch
for is not a crash but a lie: a legend row naming a key that no longer does
that, or a card promising a point that is not in the panel.

---

## 2. Bag cap, selling and discarding — **new, never played**

This shipped in `94ce9d4` and has not been in front of a person yet. It is the
highest-value section in this document.

### 2.0 Finding your own things in it — **new, 2026-08-17**

Reported from play: *"I should have an inventory screen where I can see and equip
my items."* There was one, and equipping worked. At a vendor it drew four things
you owned mixed into a whole shop's catalogue, sorted by nothing.

1. Open **B** away from any vendor. Every row is yours, there are **no
   headers**, and the panel opens with one of your items already selected. A
   `CARRIED` label over a list where everything is carried is noise.
2. Carrying nothing of that kind, the list says so in words —
   *"You are carrying no weapons. Find a trader to buy some."* — instead of
   being blank.
3. Walk up to a vendor and open **B**. Now there are two headers: **CARRIED**
   first with your things under it, then **<VENDOR> SELLS** with the shop's
   stock. The vendor is **named**; the point of the split is whose is whose.
4. **The panel still opens on something you own**, not on the first thing the
   shopkeeper happens to stock.
5. Equip an outfit and a weapon from the top group and watch them apply. This is
   the thing the report said was missing, and it was only ever hard to find.

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

### 5.5 Buildings have detail — **new, never played**

The other half of "blocky": the buildings were correct boxes with nothing on
them. **The failure mode to hunt for is trim floating away from its building,
or trim you can stand on.**

1. **Tatooine.** Walk up to any adobe drum. There is a wider packed-earth
   **footing** where the wall meets the sand — no unbroken right angle — and a
   pipe with a ball on top rising off the dome.
2. Run at a footing and try to stand on it. **You cannot** — every piece of trim
   in the game is `CanCollide = false`. Same test on Dromund Kaas's string
   courses and Nar Shaddaa's roof tanks. *(If you can stand on one, the boys
   will be on a roof within a minute.)*
3. **Korriban.** Each tier of a ziggurat has a visible capping course, so you
   can count the tiers from a distance. Before, four boxes of one colour read
   as a single tapering box.
4. **Coruscant.** The most important one, and the biggest view in the game.
   From a skylane, the towers are **not all the same shape**: rectangular rather
   than square in plan, each with a narrower crown block on top, and roughly
   half carrying a thin mast. The skyline is no longer one flat row.
5. Still on Coruscant, fly along a row of towers and look at the **landing
   platforms**. Every pad is clear of its neighbours — no pad is buried in the
   next tower along. *(Pads are the spawn anchors, so a buried pad means NPCs
   inside a wall. The tower grid is deliberately unjittered for this reason;
   if this fails, tower depth is escaping its clamp.)*
6. **Ord Mantell.** The stilt huts have a porch deck with four posts and a rail
   in front of the door. It hangs at the hut's floor line and you cannot stand
   on it.
7. **Hoth.** Crates and a drum are stacked outside the bunker mouth, on the
   snow. These *are* solid, like boulders — that is intended. Check none of
   them is floating or sunk.
8. **Tython.** The stone halls stand on two stepped courses, so the colonnade
   is raised. **Nar Shaddaa**: tanks and ducting on the roofs, pipes running
   down the backs. **Taris**: pipes hanging on the ruins, stopping short of the
   shear.
9. Walk a full lap of any town looking only at rooflines. Nothing should be
   hovering off its building or poking through a wall from the inside.
10. Watch the frame rate standing in the middle of a town, which is the densest
    part count in the game. This pass added roughly four to eight parts per
    building on about seventy buildings.

### 5.6 Anchorhead is drawn, not rolled — **new, never played**

Tatooine's town is now built from an authored grid in `Planets.luau`
(`PlanetDef.layout`) instead of the radial generator. **Every other planet
still uses the generator and must be unchanged** — that is half of this test.

Have the grid open on a second screen. It reads as a map: north is the top,
west is the left. If something is in the wrong place, it is either the grid or
the cell maths, and comparing the two is how you tell.

1. **Tatooine.** Stand on the plaza. There is a **wall** around the town with a
   **gate** on each of the four sides, and two wide avenues crossing where you
   are standing. Not a round town fading into desert.
2. Walk out through the east gate and back through the north gate. You can
   **walk under both** — the lintel is clear of your head, and an NPC can path
   through. *(A gate you catch on is a wall with a picture of a door on it.)*
3. Walk the wall from the outside. It is **continuous** — no gaps between
   segments and no seams where two stretches meet. Crenellations along the top.
4. **The market is east of the plaza and the cantina quarter is south-west, and
   they are there every time you rebuild.** Re-launch and check again. This is
   the entire point of the feature; a district that has moved means `cells` is
   not being read.
5. Count buildings against the grid in one block. Cells that touch and share a
   glyph are **one building** — `hh` over two rows is a house with an upstairs,
   not four huts. Two buildings never share a wall; there is always an alley.
6. The corner towers (grid rows 5 and 25) are visibly **taller than the houses**
   but still adobe drums — not Coruscant spires dropped on Tatooine.
7. **The spaceport is outside the wall**, with a road running to it from the
   town edge. That is deliberate: it is 116 studs across and too big for a block.
8. **The townspeople are in the town, not out at the spaceport.** Twenty-two
   civilians and ten troopers ringed on the plaza. *(This is the specific
   regression the authored-centre rule exists to prevent: before, a district's
   crowd followed its landmark wherever the landmark ended up.)*
9. Walk to the market. Traders are **inside the market rectangle**, not spilling
   into the houses behind it — the ring is the size the grid says, not the size
   the population says.
10. Die and respawn a few times. Spawn points are on the plaza or in yards,
    never inside a building or on the roadway.
11. **Now fly to Korriban and Nar Shaddaa.** Both are exactly as they were:
    round towns, radial street grid, jittered blocks. Nothing about this change
    touches a planet without a `layout`.
12. Check the output window at boot for `[WorldService] planet config:` lines.
    A ragged row, an undeclared glyph or a district rectangle off the edge of
    the grid all report there and nowhere else.

### 5.7 The shops open — **new, never played**

Anchorhead's **five shops (`s`) and two halls (`H`)** are rooms you can walk
into, and there is somebody in each of them. Everything else on the grid is
still solid.

1. Find a shop — a lit sign over the door is the tell, and the only building
   type with one. Walk in. You do not get stuck in the doorway.
2. **The door is on a side that faces open ground.** Walk right round the
   outside of three different shops: none of them has its door against a
   neighbour's back wall. *(This is the whole of `doorFacing`. One wrong door is
   a bug, not bad luck — the grid is fixed, so the answer is the same every
   run.)*
3. Inside: a **counter** with an overhanging top, a **shelf behind it with lit
   stock on it**, and a ceiling lamp. In the bigger shops, two crates in the
   corners by the door. You can walk round behind the counter.
4. Do that in the smallest shop (the one-cell-deep one on the market's south
   edge) *and* in the three-by-three one at its north-west corner. **The
   furniture is the same size in both** — that is deliberate; only the room
   scales.
5. **The halls** (grid rows 10–12, west side and far east) have a long table,
   benches and two lamps. The east one is turned a quarter circle: its door
   faces **south**. Check the table runs door-to-back-wall, not across it.
6. Look at a shop from outside. It is **sandstone**, like its neighbours — not
   grey concrete. *(If it is grey, `Style.wallMaterial` is not being read.)*
7. Nothing pokes through: no goods through the counter, no crate in the doorway,
   no bench through a side wall.
8. **NPCs in town are standing on streets, not inside houses.** Watch the
   civilians patrol for a minute. *(Before this change they were snapped onto
   the radial generator's block lines, which Anchorhead does not have. If
   someone is standing in a wall, `ontoPaving` is the place to look.)*
9. **Every one of the five shops has a trader in it**, standing on the
   customer's side of his counter and facing the door. Walk into all five and
   count. *(This is the part that is a lottery if `leastUsed` is not working:
   the failure mode is two traders in one shop and an empty one next door, not
   an error. The Market has nine places and nine merchants, so one each with
   three left over on the street — see step 11.)*
10. Walk up to a trader indoors. The **`Trade` prompt appears and B opens his
    stock** — the prompt reaches 12 studs and the room is not wider than that
    from the marker to the counter.
11. Three merchants are still **outside** on the market street. That is correct:
    nine merchants, six of the district's nine places are shop counters.
12. Kill a trader in his shop, wait for the respawn, and go back. **He is in the
    same shop**, not somewhere else in the district. *(A place is given back on
    death; without that the whole district shuffles one along every time
    anybody dies.)*
13. The two halls also have somebody in them — the west one is in Town, the east
    one in Market.
14. Boot output: no `[WorldService] planet config:` line saying a building **is
    in no district, so nobody will ever be inside it**. Adding an `s` outside
    every `ZoneDef.cells` rectangle is how you make that line appear.
15. **Coruscant is now the only control left** — it is the one walkable-ground
    exception, has no `layout` and never will, so it should have no shop
    interiors at all. Every other planet is drawn. (Hoth is a second, narrower
    control: it *is* drawn, and still has no shop interiors, because it has no
    Merchants to put behind a counter.)

---

### 5.8 Korriban is a corridor, not a town — **new, never played**

The second authored map, and the one that decides whether §5.6 was a system or
a one-off. Everything below is fixed by the grid, so **anything wrong here is
wrong every run** — there is no "try again and see".

1. Travel to Korriban. You wake up **inside the Academy walls**, in the top
   third of the map: a stepped ziggurat in front of you, a lecture hall at each
   shoulder, practice yards to the left and right. *(There is not one spawnable
   cell south of the Academy wall. If you ever open your eyes in the valley or
   in Dreshdae, the anchor rule has broken — see step 6.)*
2. Walk south. There is **one gate** in the Academy's wall and it is in the
   middle. Go through it.
3. **The valley is empty on purpose.** Eleven rows of road with cliffs down both
   sides, four tomb facades cut into them, and nothing else — no lamps, no
   yards, no plaza. It should feel exposed. *(If it feels furnished, something
   is drawing scatter inside the grid.)*
4. **Nobody from the Academy is out here and nobody from Dreshdae is either.**
   Stand in the middle of the valley and look both ways. The honour guards and
   war droids are in the valley; the acolytes are behind the wall; the
   civilians are past the far gate. *(This is `rectExtents`. Before it, the
   valley's patrol ring was a circle wide enough to reach both ends of a
   17-cell corridor, which put its level 19–30 guards eight cells deep into the
   level 1–12 Academy. If you are being chased by an honour guard while
   standing among acolytes, that is the bug.)*
5. Keep going south through the second gate into **Dreshdae**: houses and two
   halls on the west, **two shopfronts on the east**, a small plaza between
   them. Walk into both shops. **There is a merchant behind each counter.**
   *(Six merchants, five places — the two counters and three points on the
   avenue. An empty counter here means `leastUsed` is not working.)*
6. Die somewhere, or reset. You respawn **in the Academy or in Dreshdae, never
   in the valley.** Do it a few times. *(Player spawns are unclaimed anchor
   cells, and the valley deliberately has none.)*
7. Check the level banding matches the walk: acolytes in the Academy are around
   your level at the start, valley guards are far above it, and Dreshdae is in
   between. **The bands did not change** when the map was drawn — if the
   Academy is suddenly banding at 20, `distance` has been edited by mistake.
8. The **Academy**, **Dreshdae** and **Valley of the Dark Lords** all appear on
   the signpost and on the map, and following an arm takes you to the drawn
   thing itself. **There is no second, separate Academy building standing out in
   the desert.** *(That is `PointOfInterest.drawn`. A `Base` is 92 studs wide,
   too big for a city block, so without it the generator pushes the building six
   hundred studs clear of the district its students are standing in.)*
9. **The Tomb of Tulak Hord and the Wastes are still out past the walls**, with
   a road running to each. Those two are not drawn on the grid and should not
   be.
10. Boot output: no `is in no district` line, and no `is marked drawn but…`
    line. *(The second is new: it fires if a `drawn` point of interest is on a
    planet with no layout, names no zone, or names a zone with no `cells` — all
    three of which leave a named place with no building anywhere.)*

### 5.9 Taris and Ord Mantell — the last two openings — **new, never played**

With these two drawn, **all four origins now start on an authored map**. So the
first thing to check on each is the first thing a new character sees.

**Taris — the fence**

1. Start or travel as a **Scrapper**. You wake in the **Resettlement Camp**:
   twelve identical two-cell shacks in four ranks, a field hall on the west, a
   small plaza. The sameness is deliberate — one contract, one building.
2. There is **one gate** in the fence, south of the plaza. Before going through
   it, walk east along the top of the map to the **Depot**: two shopfronts, and
   **a merchant behind each counter**. Five merchants for five places, so an
   empty counter means `leastUsed` is not working.
3. Through the gate is **the Dig**, and it is the only authored district in the
   game that should look *unplanned*: survey towers at no particular spacing,
   two field halls, yards where the spoil goes. *(If it looks like a street
   grid, the wrong glyphs got used.)*
4. Both field halls have a door onto open ground and somebody inside.
5. Boot output: Taris spells `Wall` as `#`, not `W`. **No `undeclared glyph`
   line.** *(Legends are per-planet; this is the map that proves it. A shared
   legend would fail here and nowhere else.)*

**Ord Mantell — the diagram and the war**

6. Start or travel as a **Conscript**. You wake in **Fort Garnik**, and it is
   perfectly symmetrical: four barracks around a muster square, a watchtower on
   each front corner, rampart all the way round, **one gate**. The symmetry is
   the joke — see step 8.
7. Four halls, four doors, somebody inside each. Twenty-nine soldiers for nine
   places, so nothing in the fort should be empty.
8. South through the gate are the **Savrip Fields**: four **trench lines** with
   the gaps in different places, one observation tower, **and nothing else** —
   no huts, no lamps, no yards. It should read as the fort's tidy rampart taken
   outside and used for real.
9. **Die out here several times. You never respawn in the Fields.** You come
   back in the fort, in Drelliad, or in the market. *(There is not one anchor
   cell east of column 13, and this planet does not declare `Yard` at all. The
   Fields band above the fort and hold fourteen militia who shoot.)*
10. West of the Fields is **Drelliad**: eight shacks and a hall, **no wall** —
    then further south the market row, with a merchant behind its counter.
11. **Fort Garnik, Drelliad and the Savrip Fields all appear on the signpost**,
    and following an arm reaches the drawn thing. **No second fort, no second
    village, and no lone outpost hut standing off in the swamp.** *(All three
    are `drawn = true`.)*
12. Both planets: **the bands are unchanged.** Fort Garnik 1–3, Drelliad 2–4,
    Fields 3–5, Wilds 4–6; Camp and Dig at the bottom of Taris. The new `Depot`
    and `Market` districts sit at the **same `distance`** as the district they
    were split from, so a moved band means a `distance` was edited by mistake.
13. Boot output on both: no `is in no district`, no `is marked drawn but…`, no
    `layout row N is M characters`, and no `legend declares "x", which never
    appears`.

### 5.10 Nar Shaddaa is a city, not a settlement — **new, never played**

The fifth grid and the first drawn as a *city*, so the thing to judge is a
feeling: it should be **cramped**. Every road on the moon is one cell wide with
a building pressed against both sides. If it feels airy, the map is wrong.

1. Travel to Nar Shaddaa (level 12+, so use `greedisgood`/`strengthandhonor`
   rather than trying it fresh). You arrive on the **Promenade**: habitation
   stacks, two neon towers on the corner, two cantinas, two small landings.
2. **No two stalls are the same width.** Walk east into the **Market** — six
   shopfronts of three different sizes at three different offsets. This is the
   deliberate opposite of Fort Garnik. If it looks like a car park, say so.
3. **Walk into all six. There is a merchant behind every counter, and no
   protocol droids in the market at all.** *(The droids were moved to the
   Promenade for exactly this reason: ten merchants, nine places.)*
4. Find the **bulkhead across the middle of the map** and its **two gates**.
   That line is the whole social geography of the moon: shopping to the north,
   the docks and the refugee sector to the south.
5. Go south. Both districts are dangerous — Imperial troopers and bounty
   hunters that shoot on sight. **Die down there several times. You never
   respawn south of the bulkhead.** *(Thirty-eight aggressive NPCs between them
   and not one anchor cell in either.)*
6. **Docking Bay 41 is where the freighters are**, not six hundred studs away
   across open ground. *(A `Spaceport` is 116 studs wide, far too big for a
   city block, so this only works because it is `drawn`.)* Same for the
   Promenade and the Refugee Sector.
7. The bands are unchanged: Promenade at the bottom, Refuge at the top.
8. Boot output: no `is in no district`, no `is marked drawn but…`.

### 5.11 The last three worlds — **new, never played**

Tython, Hoth and Dromund Kaas finish the set. Each was drawn around one sentence
the planet already said about itself, so **the test is whether you can read that
sentence back off the map without being told it.** Ask the boys what each place
is like before showing them this list.

**Tython** (level 30+; use `greedisgood`/`strengthandhonor` to get there)

1. Walk the whole planet. **There is no wall and no gate anywhere on it** — you
   can leave the settlement in any direction without passing through anything.
   It is the only world in the game like that, and it is the point.
2. The **Temple precinct is the only part of the map that lines up**: two towers,
   three halls in a rank, one long plaza. **Kalikori Village does not** — houses
   in twos and threes, no through road that goes anywhere in particular. If the
   village looks as tidy as the temple, the map has lost its argument.
3. Walk east from the village into the **Stalls**. Three shopfronts; **there is a
   merchant behind each counter and no Jedi and no civilians among them.**
4. The Gnarls and Forge Ridge are **off the map** — you walk out of the drawn
   ground into open country to reach them, and that is where the shooting starts.
5. Die in the Gnarls a few times. **You respawn in the temple or the village,
   never out in the trees.**

**Hoth** (level 38+)

6. You land inside the wire. **Find the gate. There is exactly one.**
7. **No shops anywhere on the planet.** This is correct — Hoth has no merchants.
   If a counter exists and a trooper is standing behind it, something regressed.
8. Go through the gate into the **Graveyard**. The hulls are **solid and
   climbable, and the gaps between them do not line up** — getting to the far
   side should be a route you have to find, not a straight walk. If you can see
   clean through to the far edge from the gate, the stagger is broken.
9. **Die out there repeatedly. You always respawn inside the wire.** *(Twenty
   aggressive NPCs in the Graveyard and not one anchor cell.)*
10. **North Ravine is out past the last hull**, on open ice, not sitting inside
    the wreck field. *(It is the one Hoth landmark deliberately left undrawn.)*

**Dromund Kaas** (level 46+)

11. Kaas City should read as **issued rather than grown**: sixteen identical
    blocks, four to a rank, every street the same width. Compare it directly with
    Anchorhead, which is crooked everywhere. If Kaas City looks organic, the
    lattice is not surviving the build.
12. **Two spires flank the gate on the inside.** Stand between them.
13. Go east into the **Exchange** — three shopfronts, a merchant behind each.
14. Take the gate south onto the **Nexus Road**. It is four cells wide with a
    wall down each side and **no way off it**. Ten Honour Guard live in that
    corridor; expect to be attacked in it.
15. **Die on the road. You never respawn on it** — always back in the city.
16. It opens into the **Dark Temple grounds**: the same black stone, in
    fragments, paving only where the road comes in, and one hall you have to
    enter while being shot at.
17. Boot output for all three: no `is in no district`, no `is marked drawn
    but…`, no band-overlap or XP-budget warnings.

### 5.12 Named places — **new, never played**

Seven landmarks that used to be generic buildings now have their own geometry.
These are all *outside* the town grids, out in the far districts, so getting to
each one is a walk — bring a speeder (§6.3).

**The one-line summary of what this fixed: the Tomb of Tulak Hord was a crashed
starship.** If any of these still looks like a wreck or a shed, the `landmark`
field is not reaching the builder.

1. **Korriban → the Tombs.** The **Tomb of Tulak Hord** is a **facade cut into a
   cliff face**: two battered jambs under a heavy lintel, a stepped dais coming
   down toward you, and two lit braziers. **The doorway is filled in** — there
   is no way in and there is not meant to be. It is not a nose-down freighter.
2. Compare it with the **Valley of the Dark Lords** in the same trip. Both are
   tombs and they are *different* tombs — the Valley is four facades in the
   drawn grid, this is one standing alone.
3. **Coruscant → the Temple Ruin.** A raised terrace with a colonnade where
   **most of the columns are down**: some standing with capitals, some snapped
   to stumps, some with their drums lying beside them in a row. A spire lies
   across the terrace at an angle. **One corner of the top step is missing.**
   *(Before this it was Tython's intact ziggurat, and only the sign said ruin.)*
4. **Coruscant → any of the three skylanes** (Alpha, Beta, Gamma). A control
   deck with a rail on **three** sides — the fourth side is the lane, and it is
   open. Then **two rows of pylons receding away into the fog**, each with a lit
   marker on top: one row white, one row blue. All three lanes use the same
   builder, so all three look alike; that is intended.
5. Stand on a skylane deck and look along the pylons. They should read as *the
   lane itself*, going somewhere, not as fourteen posts in a field.
6. **Tatooine → the Farmstead.** The **Vantel Moisture Farm** is a **sunken
   courtyard** inside a low kerb, with **one gap in the kerb** and a ramp down
   through it, two domed huts and a cistern beside it — and then **two rings of
   vaporators** standing out in the sand around the lot.
   Count them: sixteen, seven in the inner ring and nine in the outer. The
   config says forty; sixteen is what fits, and the point is that it reads as a
   *field* of them rather than as one machine.
7. **Tatooine → the Boneyard.** A hauler **broken in two** with its back arched
   up and ribs across the gap, a row of **snapped** vaporator masts, three
   speeder chassis up on blocks and a stack of panels. Everything stripped.
   Compare with the **Dune Sea Wreck** on the same planet, which is still a
   generic `Ruin` — they should look nothing alike.
8. **Taris → the Sinking Sector.** Four towers, all leaning about the same
   angle, with **catwalks between their feet** and rubble banked where each one
   went into the ground. Sight along them: they lean at **twenty degrees**, the
   number the config gives. Their window bands lean with them — no band should
   be sitting level on a tilted wall.
9. Try to walk between the towers. The rubble and the catwalks are there to be
   climbed on; that is fine. Nothing should be floating clear of the ground.
10. **Tython → Forge Ridge.** A **ring of standing stones with one gap** in it
    (the way in), an anvil at the centre and **live coals** casting orange
    light. This is where the lightsaber chain ends and it used to be a crashed
    freighter.
11. **All seven:** the nameplate is over the middle of the thing, not floating
    off to one side, and the door/entrance faces the road you arrive on.
12. **Nothing else changed.** Anchorhead's spaceport, Dune Cantina, Nagurra's
    Estate, the Sandcrawler Wreck, the Jagged Wilds, the Works, the Gnarls and
    Czerka Lot 9 are all exactly as they were. *(Only nine POIs got a
    `landmark`; everything else still draws from its `kind`.)*
13. Boot output: no `names unknown landmark` lines. *(That check is new — it is
    what stops a misspelt `landmark` silently going back to being a shed.)*

---

### 5.13 A shop looks like the world it is on — **new, never played**

Landed 2026-08-18 (ROADMAP 3.2, the last item under that heading). Every
building you can walk *into* — 356 cells across the eight towns, and on Hoth four
of them for every house — was the same box in the planet's paint, because a room
has to be built as a shell and the shell was shared. Each architecture now
dresses its own. **Half the checks below are really one check: that no dressing
ended up standing in a doorway.**

1. **Tatooine → Anchorhead.** Walk the high street. Every shop and hall has a
   **rounded roof** — a barrel vault lying front-to-back, so the curve is what
   faces you as you approach — and **rounded corners**. No flat roof edges
   anywhere; that is the Anchorhead rule and it now applies to the shops too.
2. **Look up.** A condenser ball on a short mast over each. Water on the skyline.
3. **Hoth → the outpost.** The strongest one and the reason for the work.
   Buildings are **buried**: snow banked up the back and both sides and drifted
   over the roof. **The steel tunnel mouth is the only thing standing out of the
   white**, and it is how you find a door at all.
4. **Walk into one.** The tunnel mouth is a **frame, not a plug** — two jambs and
   a roof slab — and you walk straight through it into the shop. *(It was a solid
   block first; it sealed all 36 buildings on the planet.)*
5. **Korriban → the Academy.** Rooms are stepped like little tombs, with **two
   black obelisks flanking the entrance, braziers lit on top**, casting real
   light after dark. The obelisks stand **outside the side walls** — check the
   narrowest building you can find and confirm you can still walk in.
6. **Taris → the Dig.** Rooms look **sheared**: the trim line stops before the
   front corner, a stump of the floor above sits on the back half, four rusted
   columns carry on past it to nothing, and a slab off next door leans on the
   back wall. Nothing here should look intact.
7. **Nar Shaddaa.** A second storey **shoved sideways off the front**,
   overhanging the street; a purple neon strip up the door corner and a lit board
   over it; pipework down the back and tanks on what roof is left.
8. **Ord Mantell → the Vale.** A **pitched corrugated roof** with eaves and a
   stovepipe, and a **porch** across the front. Stand on it. Its four posts are
   at the two ends, **not in front of the door**, and the crates are dumped to
   one side rather than in your way.
9. **Tython.** A **colonnade** of pillars standing proud of both long walls, two
   steps of stylobate underneath, an overhanging lid and a lantern. This should
   read as the oldest thing in the game.
10. **Dromund Kaas → Kaas City.** Corner buttresses leaning in with **pinnacles**
    on each, two trim lines, and a **pointed crown** — nothing on this world ends
    flat. Compare it directly with Anchorhead: this was the pair named in the
    complaint, and they should now be unmistakable.
11. **The general test, on every world:** stand in the street and confirm you can
    tell what planet you are on from the shops alone, with the sky hidden.
12. **The general hazard, on every world:** find the *smallest* building with a
    door — a single square cell — and walk in. Doorways are a fixed 16 studs no
    matter how small the shell, so small buildings are where a dressing intrudes.
13. **Vendors still trade.** Walk up to any shopkeeper and open the shop. Nothing
    in a dressing should have moved the counter or blocked the approach.
14. **Coruscant is unaffected** — it has no ground layout, so it has no rooms.
    Its towers should look exactly as they did.

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
4. Pick **Sith Acolyte**. You respawn on **Korriban**, and the screen does *not*
   go away: the question is replaced by a card that names the origin, the world,
   the faction, the mentor (**Overseer Vashk**), the origin's blurb, and the two
   keys — **M** and **J**. It waits for **GO**. This replaced a four-second
   toast, so the test is that you can read it without hurrying: leave it up,
   click where an enemy is, and **nothing fires through it**.
4a. Rejoin. **The card does not come back.** It fires on the choice being made,
   not on having one, and a briefing replayed at every login is the bug.
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

### 6.1b The first ten levels, on all four worlds — **new, 2026-08-17**

The bug this replaces was reported from play: an Acolyte finished *The Empty
Bunk* and the next thing it asked for was in Dreshdae, which is the far end of
the Valley of the Dark Lords — level 19-30 and twenty-two aggressive things. The
client met a level 1 character with **TURN BACK**. Underneath it were two worse
facts: the Academy had no NPC that could be *spoken to* at all, which is why the
mission had to send you out; and act 2 was six missions on Tatooine and Ord
Mantell, so the Acolyte and the Scrapper had nothing at all between level 2 and
their signature chain at 12.

Run this four times, once per origin. `iamacolyte` and friends will not do — the
point is the board, and the board is read from where you are standing.

1. Finish the prologue **without leaving the district you woke up in.** On
   Korriban that is the Academy, on Taris the Dig. If a tracker line points at a
   district whose banner is more than a few levels above you, that is the bug
   coming back.
2. On Korriban, the Academy now has **Czerka clerks** — four `Researcher`s, the
   only people there you can press **E** on. If they are missing, objective 2 of
   *The Empty Bunk* is unfinishable and nothing warns you.
3. **The board is never empty.** As each mission closes, **M** and check the next
   one is already posted: Korriban runs *The Empty Bunk* → *The Duelling Pits* →
   *The Requisition Number*, Taris *The Sealed Crate* → *What the Crates Were* →
   *The Other Name*. Ord Mantell and Tatooine keep their existing chains.
4. *The Duelling Pits* asks for four duels with **Sith Acolytes**, in the Academy,
   at level 3. Those were declared 22-38 against a district banded 1-12 and were
   therefore unkillable *and* unavoidable; they are 2-14 now. Killing one costs
   25 Empire reputation, not 150 — six sparring matches used to turn the Academy
   hostile to its own student, so spar six times and check the guards still let
   you walk.
5. The last mission of each chain **tells you to leave the planet**, by name:
   *The Requisition Number* and *The Other Name* both end by pointing at the star
   map. That debrief is the only place in the game that has ever said travel is
   possible. If it does not appear, read the debriefing text — it is the whole
   point of the mission.
6. `Missions.validate` now refuses a first mission that leads nowhere, and one
   whose objectives sit in a district more than six levels above it. It only
   applies to `minLevel <= 1` missions with an `origin`: sending a player
   somewhere dangerous is a normal move everywhere else, and twenty missions do
   it deliberately.

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

### 6.3 Speeders — **new, 2026-08-17**

The other half of travel: **G** moves you between worlds, this moves you across
one. Anchorhead is about a minute across on foot and the map is several; the
cheapest speeder is more than twice running speed.

Everything below needs credits — `showmethemoney` — and, for the fast ones, a
level: `greedisgood` for XP.

1. Look at the **top-left legend** before doing anything else. It reads
   `V VEHICLE` next to `1-6 POWERS`. *(A summon key nobody is told about is a
   speeder nobody rides; that failure has already happened once, with the six
   panel letters.)*
2. Press **V** with nothing owned. One toast: **"You have no vehicle selected"**.
   Nothing spawns.
3. Find a trader, **B**, and there is a third tab: **OUTFITS / WEAPONS /
   VEHICLES**. Open it. The general goods trader lists seven — four speeders and
   three starships; the Jawa lists three, and **the Jawa's list is different** —
   he has the Swoop Racer, no Flare-S and no starship at all. That is
   deliberate: a Jawa sells what fell off something.
4. Buy the **Ubrikkian Hover-Sled** (900 cr, level 1). Credits drop, and the row
   moves out of the vendor's stock and up under **your** heading. *(It is not in
   your bag — a speeder is not an item and must never take a slot or be
   sellable. Check the WEAPONS tab's carry count did not change.)*
5. The button on it now reads **SELECTED — PRESS V**. Buying the first one
   selects it for you; buying a second does not steal the selection.
6. **V**. It appears a few studs ahead of you, hovering, facing the way you are.
   Walk into the seat. **V** again while parked puts it away.
7. Drive. W/S throttle, A/D steer, and it **leans into the turn**. It follows
   the ground up and down a dune without either sinking into it or climbing
   stairs off it. Take it off a ledge: it falls, and catches itself at hover
   height on the way down.
8. Reverse is deliberately slow — about a third of forward. Bumping a wall
   should not launch you.
9. Stand up. The speeder **stops where it is and hovers** rather than drifting
   off or dropping. Get back on: it does not snap round to face you.
10. **The important one, and the reason to do this with both boys in the room:**
    one of you buys a two-seater (Hover-Sled or Flare-S), drives, and the other
    sits in the passenger position. The passenger should ride along smoothly and
    **must not be able to steer**. Then the driver stands up mid-motion — the
    speeder stops, with the passenger still on it and not thrown.
11. Press **V** while riding. It puts itself away and stands you both up on the
    ground, not in the air.
12. Die on one (`iseedeadpeople` off a cliff, or find something that shoots
    back). The speeder **despawns** rather than sitting abandoned in the world.
    Same when you travel with **G** — arrive on the new world and there is no
    orphan speeder behind you, and none in front of you either.
13. Buy a second, more expensive one. Select it from the panel: the old one's
    button goes back to **SELECT** and the new one reads **SELECTED**.
    **Selecting does not summon** — no speeder should appear on the shopkeeper.
14. Try to buy the **Nubian Swoop Racer** (level 20) underlevelled. The row is
    greyed and states the level, exactly as an outfit does.
15. Rejoin. Both speeders are still owned and the selected one is still
    selected. *(`unlockedShips` is filtered through `Ships.exists` on load, so
    an id that stops existing is dropped quietly rather than producing a key
    that does nothing.)*
16. Boot output: no `[VehicleService]` warnings about a speeder reaching below
    its own hover height.

**Expected and not a bug:** the driver's own machine simulates the speeder, so
the other brother sees it a fraction behind where its driver does. Also, there
is no vehicle combat — you cannot shoot from the saddle, and nothing shoots the
speeder itself.

### 6.4 Starships — **new, 2026-08-17**

A starship is the same speeder loop with a second angle, so §6.3 is the
prerequisite: if steering or hovering is wrong there it will be wrong here too.
Needs `showmethemoney` (30,000 cr minimum) and `greedisgood` to level 16.

**Buying and launching**

1. **B**, VEHICLES tab. Below the four speeders are three more:
   **Corellian Skipjack** (30,000 / L16), **Rendili Longhaul** (85,000 / L26),
   **Czerka Dagger** (175,000 / L36). Buy the Skipjack and select it.
2. Press **V** *away from a spaceport* — in the middle of Anchorhead, say. One
   toast: **"Starships launch from a landing pad. Find a spaceport."** Nothing
   spawns. *(Select a speeder again and **V** still works normally — the rule is
   per class, not global.)*
3. Walk to the **Anchorhead spaceport** and stand on or near a landing disc.
   **V**. The Skipjack appears **on the pad**, sitting on its landing gear —
   not floating a body-length above it, and not sunk into it. Check all three
   hulls for this if you can afford them; each has different leg lengths.
4. Two of you, one pad. The second brother's ship must land on a **different**
   disc, not inside the first. If there is only one free disc within range, the
   second player gets the "find a spaceport" refusal rather than a ship in a
   ship.

**Flying**

5. Sit in the pilot's seat. W throttles up. It **does not hover-follow the
   ground** the way a speeder does — it just leaves.
6. **Space** climbs, **LeftControl** dives. Let go of both: the nose **returns
   to level on its own** over a second or two. *(A held angle in a place with no
   horizon is how you get lost.)*
7. Fly low over a dune. The ship refuses to go through the ground — there is a
   floor at its own gear height — but a deliberate climb is never fought.
8. Climb straight up. Somewhere around 900 studs the **star map opens by
   itself**, once. Come back down and go up again: it opens again. Stay up
   there: it does **not** re-open every frame.
9. The Longhaul is a four-seater with an **open-topped hold** — put a passenger
   in it and you should be able to see them from outside.

**The price of a jump — the actual point of the feature**

10. With the map open *while seated at the controls*, the header names **your
    ship**, not your origin's patron, and says jumps cost fuel. Every fare in
    the list is **much** smaller than it was on foot — tens of credits, not
    thousands — and each row's note reads *"Your Corellian Skipjack. Fuel
    only."*
11. There is **no berth cooldown** while you are in the cockpit. Jump, land,
    take off, jump again: no "no berth for 2 min" at any point.
12. Take the jump. The arrival toast says **"— N cr of fuel"**. You arrive on
    foot: the ship is put away by the same rule that dismisses a speeder when
    you travel.
13. Now the trap worth checking: stand *up* out of the seat, then open **G**.
    The prices go straight back to your origin's fares and the cooldown line
    comes back. Opening the map in the cockpit and then getting out before
    pressing the button must charge you the **fare**, not the fuel.
14. Buy a rank or two of **Navigator** (Piloting, **K**) and re-open the map in
    the cockpit. Every fuel price drops by 10% per rank. *(This is the whole
    reason the tree exists — before this commit every Piloting node said
    "unimplemented".)*
15. Same panel: **Throttle** and **Manoeuvring** ranks. Buy one of each, then
    get **out and back in** — the stats are read when you sit down, so a rank
    bought mid-flight applies to the next ride, not this one. Then check they
    also apply to a **speeder**, which is deliberate.
16. Fly to **Korriban** (no spaceport). You cannot call your ship back down
    there — expected. You are not stranded: **G** still sells you an ordinary
    fare off the planet.

**Expected and not a bug:** nothing shoots at a ship and nothing damages one, so
`Shield Harmonics` and `Field Repair` still say so on the skill panel. There is
no space *scene* — above the ceiling you are still over the planet, and the star
map is the way off it.

---

### 6.5 The inside of your ship — **new, 2026-08-18**

§6.4 is the prerequisite: you cannot board a ship you cannot call down. Needs
`showmethemoney` and `greedisgood` to level 16.

**Getting in**

1. Standing in Anchorhead with **no** ship out, press **H**. One toast:
   **"Call down a starship first."** Nothing else happens.
2. Select a *speeder* and **V** it out, then **H**. Same refusal — a speeder has
   no inside, and the check is on the class, not on having a vehicle.
3. Go to the spaceport, **V** out the Skipjack, then walk 60 studs away and press
   **H**. **"Stand by your Corellian Skipjack to board it."**
4. Walk back to the hull and **H**. The screen changes to a small lit room —
   the **Courier Berth**. You are standing on a deck, not falling.

**The room itself**

5. Walk the whole floor. It is **sealed**: four walls, a ceiling, no gap you can
   fall through and no way out on foot. You do not slide, and nothing kills you.
6. It is **lit** — two lamps in the ceiling. It should not be pitch black, and
   it should not be lit by the desert sun either.
7. Look at the **forward** wall. There is a window, and **stars** beyond it. Walk
   side to side: they stay outside the glass.
8. Press **H** again. You are back **exactly where you were standing**, next to
   your ship, still on Tatooine. Not at the spawn point, not falling.
9. Board, then press **H** and immediately board again a few times. No second
   room accumulates, and you never end up inside two cabins at once.

**Furnishing it**

10. **B** → the fourth tab, **CABIN**. Twelve pieces across four fittings
    (Berth, Table, Console, Trophy). The cheap ones (**Spacer's Bunk** 600 cr,
    **Crate Table**) are level 1; the **Nal Hutta Silk Berth** and the
    **Dejarik Table** are gated higher.
11. Buy the Spacer's Bunk at a **General Goods** vendor. It appears under
    "yours", and — because the Berth slot was empty — it is **already fitted**.
12. **H** in. There is a bunk against the **port** wall, standing on the deck,
    **inside** the room — not half-buried in the wall, not sticking through it.
    Walk all the way around everything you fit; nothing may overhang a wall.
13. Buy a second berth. **B** → CABIN → FIT TO CABIN. Go and look: the new one
    **replaced** the old one. There are never two berths.
14. Select the fitted one again. Its button reads **REMOVE**. Press it, then look:
    the slot is empty and the piece is still in your list.
15. Fill all four slots and look at the room. Nothing overlaps anything else and
    you can still walk between them.

**The bigger hulls**

16. Buy the **Rendili Longhaul** (85,000 / L26), **V** it out at a pad, **H** in.
    The room is visibly **bigger**, and the same four pieces are **further
    apart** — against the new walls, not clustered in the middle. Same again for
    the **Czerka Dagger**.

**Two players, one room**

17. Both brothers aboard at once. Each is in **their own** cabin and cannot see
    the other. Neither one's furniture appears in the other's room.
18. One boards; the other, standing outside, sees them **disappear**, and sees
    them reappear in the same spot on **H**.

**Persistence**

19. Fit something, leave the game, come back. It is still fitted. *(§10 covers
    the general case; this is the field worth checking by name — `cabin` is new
    in `PROFILE_VERSION`.)*

**Expected and not a bug:** the room is purely cosmetic. Nothing in it heals you,
buffs you, saves the game or advances a mission, and no NPC ever appears in it.
You cannot fly while aboard — the cabin and the cockpit are different places.

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

**Known open — do not file these:** the Escort / Survive / Destroy objective
kinds have no server reader. *(`Slice` gained one on 2026-08-17 —
`TerminalService`. See 9.6.)*

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

### 7.2 The journal — **new, never played**

**J** opens it. The board (**M**) is what you can do now; this is what you have
already done. It reads the profile you already have, so a fresh character is
*supposed* to look almost empty — that is the test, not a failure.

0. **J** on a brand-new character. The row at the top of the left rail is **Who
   you are**, not an act, and it is what the journal opens on until you have
   finished something. It names your origin, your level and alignment band, your
   mentor, your standing with your faction, your home world and where you
   currently are — then **What is going on**, which on a new character honestly
   says *nothing yet*. This is the answer to "I still don't know who I am", so
   the test is that you can get all of it back at any time from one key.
0a. Play far enough to hear one of the four hints about The Quiet, then re-open.
   **What is going on** has a paragraph now. Name it outright (the
   `NamedTheQuiet` flag) and the paragraph gets longer. A character who has not
   met it must never see either — that is the spoiler.
1. Five acts down the left below that row, all of them **Not begun** and greyed,
   and the page says nothing more than the act's name. **No
   act should show its one-line subtitle before you have finished something in
   it** — those lines say what the act is about and are a spoiler until then.
2. Finish your prologue. Re-open. **Beginnings** is now lit, shows its subtitle,
   and the mission you finished has its **debriefing** underneath — the text you
   got on turn-in, readable again.
3. Take a second mission and leave it open. It appears on the page marked **in
   hand** with its summary. Nothing you have not reached is listed by name:
   the rest are one grey line saying how many are left.
4. Make a choice that pays alignment (the first fork is at level 12, on
   Coruscant). A **What you chose** block appears at the bottom of that act's
   page, in plain English. Your brother, having chosen the other way, must see
   a *different* line there — same act, same page.
5. **What You Carry** is your own chain. Everything on that page is yours: none
   of the other three origins' missions should appear at all, not even greyed.
   Check this on two characters of different origins.
6. Open **J** while another panel is up. The other one closes. Open **M** while
   the journal is up; the journal closes. **Escape** shuts it.
7. Turn a mission in while the journal is open — a kill can land the last
   objective. The entry writes itself in front of you without reopening.

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

### 8.4 The six secrets — **new, never played**

Landed 2026-08-18 (ROADMAP 4.2). Each of the six cast members is hiding one
thing, and there is now one reply in each tree that asks about it. **The whole
point of this section is the difference between a refusal and a payout**, and
they are deliberately hard to tell apart from the outside — an unqualified
player gets a real in-character non-answer, not a greyed-out line. So the test
is always: ask *before* you qualify, then ask again *after*.

This is also the dress rehearsal for 5.1. When a language model eventually
writes these characters' lines, this reward path is the one it will not be
allowed to touch — so anything wrong here is wrong in a system that is supposed
to be the trustworthy half.

1. **The boot log is silent.** `Secrets.validate` runs from `DialogueService` at
   startup. A `[DialogueService] secrets config:` line means a secret names a
   speaker, node, flag, item or affix that does not exist — *or*, and this is the
   one worth reading twice, that a topic is asked in a tree nothing answers, or
   answered in a tree nothing asks. Both directions are checked because
   **finished but unreachable is not finished**.
2. **The refusal comes first.** Before qualifying for any of them, talk to each
   of the six and take the reply below. Every one must give you a **short
   deflection and return you to the conversation**. No toast, no XP, nothing in
   the log. If a deflection *does* pay, that is the exploit — one of the boys
   will be standing behind the other while it happens.
   - **Vashk** (Korriban, Academy) — *Thirty years of forms. Where do they go?*
   - **Tolen Marr** (Ord Mantell, Garrison) — *The commendation you did not
     want. What was it for?*
   - **Vess Kadar** (Nar Shaddaa, Promenade) — *You do not set your own prices.
     Who does?*
   - **Ordo-9** (Taris, Camp) — *\*Open the maintenance log yourself.\**
   - **Ryn Solaa** (Tython, Temple) — *You said four of you wrote it down. Who
     were the other three?*
   - **Aneth Corr** (Taris, Lot 9) — *You have never met the client. You have
     seen the account.*
3. **Each one opens for its own reason.** Qualify and ask again. A **Reward**
   toast fires, and the conversation goes to a node that is a *paragraph*, not a
   line. What each wants:
   - **Vashk** — `NamedTheQuiet` (Solaa's level-20 *Say what it is. Out loud.*)
     and **level 24**. Pays 1600 XP, 2400 credits.
   - **Tolen Marr** — `HasTheManifest` (finish *CorPaperTrail*) and **alignment
     0 or better**. Pays 1400 XP, 1200 credits and a **Republic Veteran outfit
     with two rolled defensive affixes** — check `B`: the name is decorated, not
     plain.
   - **Vess Kadar** — `DebtSettled` (either debt mission) and **`PriceMult` at
     0.92 or lower**, which means real Bargaining ranks or a Haggling roll. This
     is the only secret in the game earned by *building* rather than
     *finishing*, so it is the one most likely to be mis-gated. Pays a **rolled
     DL-44**.
   - **Ordo-9** — `HeardNineRemember` (*TarTheSealedCrate*) and **SliceTier 2**.
     Nobody talks him into this; you open the log yourself. It is also the only
     reader of `SliceTier` outside a terminal, so if this refuses at rank 2 the
     bug is in the stat, not the secret.
   - **Ryn Solaa** — `NamedTheQuiet` and **alignment +250**. A character playing
     the Empire straight must **not** be able to hear this; check that with
     `iamacolyte` and a negative figure.
   - **Aneth Corr** — `SawLot9` (*TarWhatTheyKept*) and **level 30**. No
     alignment gate at all, on purpose. Pays the most: 2000 XP, 3000 credits.
4. **It pays once and answers forever.** Ask the same character the same thing a
   third time. They **tell you again** — the paragraph is still there, they are
   people — and **nothing is awarded**: no toast, no credits, no second copy of
   the outfit. Check `showmethemoney`-free credits before and after. Two players
   in one room will try exactly this.
5. **A full bag does not eat the outfit.** Fill the inventory to the cap
   (§2 covers how), then qualify for **Marr** or **Kadar** and ask. You get an
   **Error** toast reading *No room — come back with an empty hand*, and the
   conversation does **not** open the answer node. Drop something and ask again:
   it must pay in full. A unique item that silently vanished into a full bag is
   the one failure here a player cannot diagnose.
6. **Bargaining does not inflate the money.** Compare a secret's credit payout
   on a character with heavy Bargaining against one with none. **The numbers are
   identical.** Prices scale with that stat; what somebody tells you does not,
   and if it did this would be the only farmable value in the file.
7. **The journal noticed.** Open **J** after each secret. A new line appears
   under *Paper Trail* (Marr, Kadar) or *What They Kept* (the other four),
   written as something you now know rather than something you did. This came
   for free because the record is a `Flags` entry and not a private list, and it
   is the check that proves it.

### 8.5 Day, night, and who is out — **new, never played**

Landed 2026-08-18 (ROADMAP 5.0). Days are short on purpose — Tatooine's is
fifteen real minutes, Dromund Kaas's thirty-six — so **every check here is a
matter of waiting a few minutes, not a session**. The HUD now reads e.g. `Tatooine 14:23`
under the health bar; that clock is the instrument for all of this.

**The half of this worth testing with two people is the first item.** It is the
only bug in the feature that a single player literally cannot see.

1. **Both of you are in the same afternoon.** Two clients, same planet, joined
   several minutes apart. **The HUD clock reads the same on both screens**, and
   the sky matches. This is what the whole `WorldClock` module exists for: the
   old code gave each client a private clock starting at 09:00 on arrival, so
   two brothers in one room were hours apart and the sky was the only thing that
   knew. If the numbers differ, nothing else in this section means anything.
2. **The clock actually moves, and it wraps.** Watch the HUD for a minute — a
   planet minute is well under a real second. Let it roll past `23:59` to
   `00:0x` without going negative or sticking.
3. **Landing does not reset it.** Note the time on Tatooine, travel to Ord
   Mantell and back. The Tatooine clock must have **advanced by roughly the time
   you were away**, not restarted at 09:00.
4. **Every world keeps its own time.** Check the clock on three planets in quick
   succession. They must read **different hours** — the offset is a hash of the
   planet id, so nine worlds do not share one sunset. Travelling to Korriban and
   finding it is 02:00 is correct and is the point.
5. **The street empties after dark.** Stand in a town square (Mos Eisley is the
   clearest) and watch it cross `20:00`. **Civilians and moisture farmers walk
   back to where they spawned and stop** — they walk, over the dusk window; they
   do not teleport or freeze mid-stride. Then wait for `07:00` and watch them
   start milling again.
6. **Somebody else is out instead.** In the same window, **smugglers** do the
   opposite: still by day, wandering by night. A night town that is simply
   emptier than a day town is only half the feature working.
7. **A closed market is still a market.** With the crowd stood down at 22:00,
   walk up to a civilian and press **E**. **The Talk prompt is still there and
   the conversation still works.** Nobody is ever despawned by the clock, and a
   vendor is never put on a shift at all — check a **Merchant** and a **Jawa**
   trade fine at 03:00. A shop you cannot use at night would be this feature
   causing exactly the class of bug it was written to avoid.
8. **Nothing hostile takes the night off.** The one that matters, because it is
   the exploit. Find the **aggressive smugglers** in the Tatooine Wastes or the
   Nar Shaddaa Fields/Wilds — a Smuggler's archetype keeps a night shift, but
   those spawn rules promote them to `Aggressive`. **At high noon they must
   still hunt you exactly as they do at midnight.** Free XP on a timer is the
   first thing that would be found and the last thing that would be reported.
9. **Combat outranks the hour.** Get into a fight just before `20:00` and let it
   run through. The NPC must not wander home mid-exchange; the shift pass skips
   anything in Combat or Flee and only takes effect once the fight is over.
10. **The boot log is silent.** `NPCArchetypes.validate` now also refuses a
    shift on an Aggressive archetype and on a vendor. An `[NPCService] archetype
    config:` line naming a shift means one of those two rules was broken in
    config, and items 7 and 8 are what it would have cost.

### 8.6 Being watched — **new, never played**

Landed 2026-08-18 (ROADMAP 5.0b). To reach any of this you need reputation
below **-100** with a faction you are not enlisted in. Killing does it —
`repOnKill` is negative on every archetype — so **two Imperial soldiers on
Korriban** is enough, or use `strengthandhonor` on a planet whose controller you
want to like you and go and annoy somebody else. Standing is readable per
destination on the galaxy map (**G**).

1. **Patrols are not a queue.** Before anything else, stand in a district with
   several patrolling soldiers (Coruscant and Nar Shaddaa are the busiest) and
   just watch for a minute. **They must be spread around the circuit, some
   walking it the other way.** Until now they all converged on one corner and
   followed each other nose-to-tail forever, which is the thing being fixed and
   is obvious once you know to look.
2. **The warning arrives in words.** With Empire rep under -100, walk into sight
   of an Imperial patrol. A single toast: *"Sith Empire patrols are watching
   you."* **Once**, not once per soldier — a district holds a dozen and twelve
   identical toasts is not information. Walk away and back within 90 seconds and
   it must stay quiet.
3. **You are followed, not attacked.** The soldier breaks off its route, closes
   to about 16 studs and keeps facing you. **It must never fire.** Being watched
   costs nothing mechanically; what it costs is moving through their ground
   unnoticed.
4. **You can still talk to them.** Walk up to your shadow and press **E** if the
   archetype is interactable. A hostile-looking behaviour that silently removes
   an interaction is the failure this project keeps re-shipping.
5. **Guards on a door stay on the door.** A **Sith Honour Guard** (Dark Temple,
   Nexus Road) or an **Imperial Commando** declares `holdsGround`: it must turn
   and track you across the plaza **without stepping off its post**. A **bounty
   hunter** in the Tatooine cantina declares no such thing and *should* get up
   and follow. Both behaviours are correct; seeing only one means the flag is
   not being read.
6. **Nobody follows you out of the district.** Lead a watcher away. Past roughly
   80 studs from where it started it must stop, hold, and keep looking at you —
   then return to its beat when you leave. A garrison that trails one player
   across the map leaves the place it was guarding empty, which is a far worse
   bug than the one being fixed.
7. **The shop does not walk away.** The one that matters. **Merchants, Jawas and
   quest-givers must never do any of this**, whatever your standing. Get your
   Hutt reputation under -100, then go and trade with a Nar Shaddaa vendor and
   take a mission from a Hutt quest-giver. If a vendor is shadowing you around a
   market instead of standing behind the counter, `ShopService`'s 30-stud
   proximity check has a moving target and the shop is effectively gone.
8. **Crossing -500 still means gunfire.** Keep killing until Empire rep passes
   `HOSTILE_BELOW`. The posture must give way to an actual attack — suspicion is
   the band *before* hostility, not a replacement for it.
9. **Your own flag still protects you.** An **Acolyte** starts on Korriban with
   zero Empire reputation; their own Academy must never watch them, at any
   standing, because enlistment beats reputation here exactly as it does in
   `isEnemy`.
10. **Combat wins.** Shoot a watcher, or shoot its squadmate in earshot. It must
    drop straight into a fight. Likewise the 5-second shift pass must not pull a
    suspicious NPC back to its post mid-follow.

### 8.7 The crowd you never meet — **new, never played**

Landed 2026-08-18 (ROADMAP 5.0c). `CrowdController` draws a second crowd on the
client only, behind the real NPCs: two extra bodies per real everyday one, no
Humanoid, no brain, no prompt, no collision. **They live under
`Workspace.CurrentCamera`, which is what makes the whole thing safe** — nothing
that walks Workspace can see them. Almost every check below is a check that
they stayed scenery.

1. **The difference is visible.** Stand in Coruscant's **Senate Plaza** (65 real
   NPCs) and then in Ord Mantell's **Market** (4). The Plaza should read as a
   city and the Market as a back street. The density is derived from the real
   spawn rules, so a district that looks the same as it did is a district where
   the controller did not run at all — check the console for `[CrowdController]`.
2. **You can never reach one.** Pick a distant figure and walk at it. It must
   **fade out over the last fifty studs and be gone before you arrive** — you
   should never be able to stand next to one, bump one, or walk through one.
   Anything you *can* reach is a real NPC and should have a name and a prompt.
3. **They are not targets.** Shoot into the crowd. No damage numbers, no health
   bar, no reaction, no corpse — and **no XP**, which is the exploit worth
   checking with two people in the room.
4. **Both of you see the same street.** Two clients side by side on one planet:
   the ambient figures should be **in the same places walking the same way**.
   Position is a function of `GetServerTimeNow()` and a seed of planet + zone,
   with nothing replicated; if the two screens disagree the seed is wrong.
5. **The street thins after dark and never empties.** Watch a square cross
   `20:00` with the HUD clock. Some of the ambient crowd should fade out over
   the evening, bottoming around 01:00 at roughly a third — **not to zero**. An
   empty street reads as a bug; a quiet one reads as night.
6. **The real crowd is untouched by any of it.** In the same square at 02:00,
   walk up to a **civilian**, a **moisture farmer** and a **protocol droid**:
   prompts present, dialogue works, missions still offered. This is the whole
   reason the ambient crowd exists instead of the real one being thinned —
   several missions have those three as givers or as `TalkTo` targets.
7. **Vendors are unaffected.** Trade with a **Merchant** and a **Jawa** in a
   busy district. `ShopService` sweeps Workspace within 30 studs and cannot see
   a camera-parented model, so a crowded market must open a shop exactly as an
   empty one does.
8. **Nobody is buried or floating.** Look along the pavement. Feet on the
   ground, no figure shin-deep in it and none standing on air. Each route point
   is resolved by a downward raycast at build time; a wrong one shows as a
   single figure permanently on a pedestal.
9. **They look like the locals.** A Tatooine crowd should be dusty civilians and
   Jawas, a Coruscant one taller and mixed. **No ambient stormtroopers, no
   ambient Sith** — armed and Aggressive archetypes are excluded on purpose,
   because a distant trooper is something the boys will go and shoot at.
10. **Death and travel do not lose them.** Die and respawn: the crowd must come
    back, because respawning replaces the camera the folder hangs from. Then
    travel to another planet and confirm the old planet's crowd is gone and the
    new one appears within a few seconds — the build retries while the server's
    zones are still replicating.

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

### 9.0 Knowing any of this exists — **new, 2026-08-17**

Reported from play: *"I'm unsure how to use powers, where we see the skills tree,
etc."* — from a player who had already finished a mission. Six systems were
finished and reachable only by pressing a letter nobody had been told about, and
a keyboard has twenty-six. Do this on a **fresh character**, and read nothing
first.

1. **The top-left corner names every key**, from the moment the HUD appears:
   `1-6 POWERS`, then `B GEAR`, `M MISSIONS`, `J JOURNAL`, `K SKILLS`,
   `G STAR MAP`. It never hides, including in a fight.
2. **Press each one and check it opens what it claims.** The legend is built from
   `Panels.ALL` and the controllers read their key from the same field, so a
   disagreement means the registry lost an entry rather than that the letter is
   wrong — but the whole reason it is one table is that this used to be six.
3. `1-6 POWERS` is the only hand-written entry, and it is deliberately first: the
   ability bar is invisible until the tree unlocks something, so on a level 1
   character that line is the only thing on screen saying powers exist.
4. **Buy an ability in K.** A toast says *"Force Push unlocked — press 1"*, once.
   Buying a second rank of the same node must not say it again.
5. **Rejoin.** A character who already owns four abilities gets **no toasts** on
   spawn. The first profile only seeds the set; announcing four things you bought
   yesterday is noise, and it is what the naive version does.

### 9.0a Aiming a blaster — **new, 2026-08-17**

Reported from play: *"I'm not a huge fan of the blaster physics and options. I'd
think we'd have the ability to have a reticle or other / better way to fire."*
Shots have always left the character's front; nothing on screen said so, and the
character faced wherever it last walked.

1. Equip a blaster. There is **no permanent dot** in the middle of the screen
   any more. The old one was a claim the game could not keep.
2. **Hold right mouse.** The camera pulls over the right shoulder, the mouse
   locks to the centre, the character turns to face the camera and **stays**
   facing it while you strafe, and a **reticle appears**. Release: free look
   returns, the mouse comes back, the reticle goes.
3. **The reticle's size is the weapon's spread.** Swap a DL-44 for an E-11 while
   aiming and watch the gap between the four ticks change. Fire a burst at a
   wall from twenty studs — the scatter should sit inside the reticle. If it
   does not, the reticle is lying and that is worse than not having one.
4. **Open any panel while aiming.** Aim releases on its own. A mouse locked to
   the centre of an inventory you cannot click is the bug.
5. **Die while aiming.** You respawn in free look with your mouse back. Hold the
   button down through a respawn too: the new character should aim, not be
   stuck half-turned.

### 9.0b Swinging a lightsaber — **new, 2026-08-17**

Reported from play: *"I have this ridiculously long lightsaber but I have no way
to actually swing it."* The swing always dealt damage — `EffectsController` threw
away every melee `WeaponEffect` it was sent, so nothing about it was visible.

1. Equip a lightsaber and stand still. **The blade is about two thirds of the
   character's height**, not longer than the character. A shoto is visibly
   shorter than a standard blade.
2. Click. **The arm moves** — wind up, strike, return — and a **glowing arc**
   follows the blade and fades behind it. Hold the button: swings **alternate
   direction**, so it reads as a combo rather than a twitch.
2a. **Do all of step 2 again with a vibroblade, a gaderffii and an
   electrostaff.** Every melee weapon leaves an arc, not just the lit ones — a
   steel edge draws a pale, shorter streak. The trail hangs off the *longest*
   part, which is the blade on a vibroblade and the **shaft** on the two staves.
   If the arm does not move at all on any weapon, check the output window: the
   swing warns once about a missing `RightUpperArm`, which means an R6 avatar
   (Game Settings → Avatar → Avatar Type → R15) and not a bug in the swing.
3. **Hit something.** Sparks in the blade's colour appear *at the point the
   server says the hit landed*. Swing at empty air: arc, no sparks. A spark with
   no damage would mean the client is guessing.
4. **Reach matches the blade.** Back away until things stop dying and check the
   tip is roughly where the damage stops. Shortening the blade without
   shortening `range` would have moved this lie rather than fixed it.
5. **Your brother's swings animate on your screen**, not just your own — the
   character model is on the wire for exactly this. And your own arm moves the
   instant you click, without waiting for the server.
6. Swing, then die mid-swing. The arm must not be left stuck out on respawn.

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

### 9.4 Abilities — **new, never played**

Seven verbs on a 1–6 bar. Nothing here existed before; **Force Push had claimed
to exist since the tree was written and never has.** Fastest route in is
`iamacolyte` then `thereisnocow` for the levels and points.

1. **The bar is empty at level 1** and the Force meter above it is not drawn.
   That is correct — you have bought nothing.
2. Buy **Force Sensitive** then **Force Push** in **K**. Before spending,
   the detail pane says *"Unlocks Force Push on the ability bar."* On the
   second purchase **a slot appears on the bar with no reload and no respawn.**
3. Walk up to anything hostile and press **1**. It is thrown backwards *and
   upwards* — not scraped along the floor — and takes a little damage. The Force
   meter drops by 25 and the slot darkens and refills over 8 seconds.
4. **Press 1 again immediately.** Nothing happens and nothing is said; the local
   cooldown swallowed it. Now press it repeatedly while it is down — no `[Net]
   rejected` line, no Force drain.
5. **Empty the meter** (four pushes in a row once the cooldown allows). The
   fifth press toasts **"Not enough Force"** and the slot **goes bright again
   immediately** rather than sitting dark on a cooldown that never started.
6. **Open any panel and press 1–4.** Nothing fires. Then talk to an NPC and
   answer with **1** — you get the reply, *not* a Force Push into the person
   you are talking to. This is the one collision worth being sure about.
7. **The fork.** At level 16 the Force tree offers **Force Lightning** and
   **Force Mend**. With a neutral character **both refuse**, saying *"You have
   not been the kind of person this answers to."* Push alignment dark (the
   Cartel choices in 8.1) and Lightning becomes buyable while Mend does not.
   **A character can never hold both.**
8. **Force Mend / Field Stim reach your brother.** Both stand in one place, hurt
   both, then one presses the heal. **Both health bars rise.** Nothing hostile
   standing in the same radius is healed or hurt.
9. **Frag Grenade** (Combat tree, `Grenadier`, level 6) is the shape to watch.
   Aim at a wall — **it lands on the wall, not through it** — and the flash
   happens about a second and a half *after* the throw, not on the throw. Walk
   out of the ring in that time and take nothing.
10. **Kill something with an ability rather than a blaster.** XP, credits and
    any loot drop exactly as if you had shot it, and a mission that wanted that
    kill counts it. *(All ability damage goes through the same door; if this
    fails, something is writing health directly.)*
11. **Field Stim** (Engineering, level 8) costs no Force — a Scoundrel or
    Scrapper should have a working ability and **no meter above the bar at
    all.**
12. Die with an ability on cooldown and respawn. The Force meter is **full**,
    and the bar still has your slots on it.
13. **The bar holds six.** A Force character can now unlock Push, Barrier, one
    half of the fork, Mark Target and Field Stim — five. Buy them all and
    **count the slots**: five buttons, keys 1 to 5, none missing. *(It was four
    slots until the co-op pair arrived, and four was exactly what a character
    could hold, so nothing had ever been hidden.)*

### 9.4b Two players — **new, never played, and the only section that needs both boys**

ROADMAP 4.3's fourth target: **two players should be worth more than twice one.**
Everything before this made *you* better, so a second player was worth exactly a
second player. Run this with both of them in the same world.

1. **Spotter** (Combat, level 10, behind Marksmanship) unlocks **Mark Target**.
   It is in the Combat tree on purpose — every origin can reach it.
2. Aim at a hostile a long way off and press it. **It is a line, not a spray**:
   at 110 studs and eight degrees, what you were pointing at lights up with a
   yellow outline and the man next to him does not. The outline lasts about
   fourteen seconds.
3. **The outline does not show through walls.** Mark someone, step behind cover,
   and he is gone from view. *(A mark you can see through terrain is a wallhack,
   and they will find it.)*
4. **Alone it is a bad button.** Mark something, shoot it, and the damage numbers
   go up by under a third for one cooldown. That is correct and it is the point.
5. **Together it doubles.** One marks, *both* shoot. The damage numbers over
   **the brother who did not press anything** are the ones that go up. If his
   numbers are unchanged, the mark is being read as a buff on the caster rather
   than a debuff on the target, which is the whole feature inverted.
6. Mark something already marked. The clock restarts; the bonus **does not add**.
   Try it with both players marking the same enemy — still one bonus.
7. **Force Barrier** (Force, level 13, behind Force Sensitive) is the other half.
   Note what it is *not* gated on: **a dark character and a light one can both
   buy it**, which is deliberate — see the node comment.
8. Cast it standing next to each other. **Both get a toast reading `Barrier: N`
   and a blue outline.** Then let something shoot the brother who did not cast
   it: **his health does not move** until the pool is gone, at which point he
   gets **"Barrier broken"** and the outline vanishes.
9. **No damage numbers while it holds.** A hit the barrier eats whole shows
   nothing over the target — like a deflect. A floating "0" means the absorb is
   running after the health write instead of before it.
10. **It does not shield enemies.** Cast it in a crowd of hostiles; only players
    in the radius get an outline. Same rule as the heals.
11. **The two together.** One marks, one barriers, both shoot. That fight should
    be visibly easier than the same fight run twice solo — and if it is not,
    say so, because that is the target failing rather than a bug.

### 9.5 Forks and capstones — **new, never played**

The first branch points in the tree. **These are permanent and there is no
respec**, so the thing being tested is mostly whether the panel tells you that
*before* you click. `thereisnocow` for the levels and points.

1. Open **K** and select **Deadeye** (Combat, level 12). The button reads
   **SPEND 1 POINT** and below it, in amber rather than red, *"Taking this
   closes off Overcharge for good."* **The warning is there while the node is
   still buyable** — if it only appears after you cannot buy it, it is useless.
2. Buy it. Now look at **Overcharge**: the row says **CLOSED OFF** and is
   greyed, and clicking it gives *"Closed off by Deadeye"* with a dead button.
   You should not have to click to find that out.
3. **Buy Deadeye a second time.** It still works. The exclusion refuses the
   first rank of the *other* node, not the rest of this one.
4. Same check on the Force tree: **Deflection** and **Juyo Focus** (both level
   11, both behind Lightsaber Form). Take Focus, confirm a saber does visibly
   more damage per swing, and confirm Deflection is closed.
5. **The drift hole.** Buy **Force Lightning** as a dark character, then push
   alignment light past +100 and go back to **Force Mend**. It must say
   **CLOSED OFF**, not offer itself. *(Before this pass the alignment bound was
   the only lock, and it is only read at the moment of purchase.)*
6. **Executioner** (Combat, level 24). Its body text says *"Costs 18 points in
   Combat first — you have spent N"* **even when you have no skill points at
   all** — the refusal alone would have said "No skill points available" and
   made an 18-point capstone look like it cost one.
7. With fewer than 18 in Combat it refuses with the count. At 18 it buys, and a
   critical hit visibly does far more than double — roughly 3.5x. Crits are
   the thing to watch, not the average.
8. **Kit Discipline** (Engineering, 12 points, level 24) is the cross-tree one:
   buy it on a **Force** character and confirm the **cooldown sweep on the
   Force powers is visibly shorter**, and that pressing the key at the new
   shorter time actually fires rather than being silently swallowed. *(The bar
   predicts the cooldown locally; if it did not know about this capstone the
   client would refuse a press the server would have allowed.)*
9. **Attunement** (Force, 18 points, level 24): the Force meter drops by
   noticeably less per cast — about 15 for a Push instead of 25.
10. **Try to buy all three capstones on one character at level 50.** You cannot:
    18 + 18 + 12 plus the three ranks is 51 against 49 points. **Two is the
    most, and that is the point of them.**
11. Check the output window at boot for `Progression` warnings. A one-way
    exclusion, a self-exclusion, a capstone priced above what its tree holds,
    or a tree cheap enough to buy whole all report here.

### 9.6 Slicing — the first skill that opens something — **new, 2026-08-17**

The test of ROADMAP 4.3 target 5. Everything else in the tree makes a fight
shorter; this decides what is in front of you. `iamscrapper` and
`thereisnocow` set up the skill side.

1. Walk to a **spaceport, base, outpost, ruin or temple** on any walkable world.
   Just outside the building there is a lit lectern with a cyan screen, tagged
   **`<name>  --  TIER n`** from about 140 studs. **A cantina and a market have
   none** — five kinds of place are secured and those two are not.
2. **Walk to it with no Slicer at all and press the prompt.** The refusal names
   the rank: *"Tier 1 lock. Slicer rank 1 would open this; you have 0."* This is
   the whole point of the feature — it is how a player who has never opened
   **K** learns the tree decides what the world lets them do. A generic "you
   cannot do that" here is a bug.
3. Buy **Slicer** (Engineering, level 6) and slice it. The screen and the tag go
   **red and read CRACKED**, the prompt stops appearing, you get a credits toast
   and XP, and sometimes an item on the same odds a kill has.
4. **Find a tier the rank cannot reach.** Terminals are tiered by their
   district's level band against the galaxy's ceiling, so a far district's
   console will refuse rank 1 and name rank 3 or 4. Buying the ranks is the only
   thing that changes that.
5. **Two players.** One brother slices; the other must see the same console go
   **CRACKED**, and must not be able to slice it again. Then wait out
   `Terminals.COOLDOWN` (10 minutes) and confirm it goes cyan again **for both**.
   Spent state belongs to the world, not to a profile.
6. **Same spot every time.** Rejoin, or travel away and back: the console is
   where it was. The angle is derived from the place's id, never rolled — so
   *"the one round the back of the depot"* has to stay true between two people
   in the same room.
7. **The optional objective.** Take `TarWhoBuysCrates` on Taris (Scrapper chain,
   level 7). It has a step *"Slice the dig's site console for the shipping log"*
   marked optional. Slice the console at **The Dig** and the step ticks;
   **finish the mission without it** and it still turns in. Every Slice
   objective in the game must be skippable — there is no respec, and a required
   one would wall three quarters of characters permanently. `Missions.validate`
   fails the build if one is not optional, so this is really a check that the
   rule is still there.
8. **Stat-gated dialogue.** With **Slicer rank 1**, talk to any **merchant**:
   there is a line about his ledger pad being unlocked that a character without
   the skill never sees. Take **two ranks of Haggler** (-6% each, so
   `PriceMult` 0.88) and a second new line appears — one rank is 0.94 and is
   deliberately not enough. At **Slicer rank 3**, a **smuggler**
   offers a line about Czerka cargo seals. Compare against a fresh character:
   those lines must be **absent**, not greyed.
9. Check the output at boot for `[TerminalService]` warnings — a Slicer rank
   count that no longer matches the tier ceiling, a galaxy with no terminals, or
   a hardest lock nobody could ever reach all report there.

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
