"""Checks the authored ASCII maps in Planets.luau, without Roblox.

A layout is a table of strings, so `luau-lsp` will happily accept a grid with a
ragged row, a building with no door, or a district holding fewer NPCs than it
has places to stand them. `Planets.validate` catches some of that -- at boot,
which is a Studio session away.

This **parses `Planets.luau` itself** rather than taking a pasted copy of the
grid, because transcribing the map into the thing that checks the map is the
exact mistake it exists to catch. It re-implements PlanetBuilder's `layoutRects`,
`walkable`, `doorFacing` and `cellOffset`, plus `Planets.rectExtents`.

    python3 tools/gridcheck.py            # quiet unless something is wrong
    python3 tools/gridcheck.py -v         # every room, anchor and district
    python3 tools/gridcheck.py -v Taris   # one planet

Keep the constants below in step with PlanetBuilder; there is no way to import
them.
"""

import math
import os
import re
import sys

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "src/shared/Config/Planets.luau")

PREFABS = {
    "House": {},
    "Hall": {"room": True},
    "Shop": {"room": True},
    "Tower": {},
    "Wall": {},
    "Gate": {"paved": True},
    "Road": {"paved": True},
    "Plaza": {"paved": True, "anchor": True},
    "Yard": {"anchor": True},
    "Lamp": {"anchor": True, "build": True},
}

ZONE_POINT_LOAD = 6
ZONE_POINTS_MAX = 12
SCATTER_START = 610  # SETTLEMENT_RADIUS + 90


def blocks(text):
    parts = text.split("\ndef({")
    for p in parts[1:]:
        m = re.search(r'id = "(\w+)"', p)
        if m:
            yield m.group(1), p


def parse_layout(block):
    m = re.search(r"\n\tlayout = \{(.*?)\n\t\},\n", block, re.S)
    if not m:
        return None
    body = m.group(1)
    cell = int(re.search(r"cell = (\d+)", body).group(1))
    legend = {}
    lm = re.search(r"legend = \{(.*?)\n\t\t\},", body, re.S)
    for k, v in re.findall(r'\["(.)"\] = "(\w+)"', lm.group(1)):
        legend[k] = v
    for k, v in re.findall(r"(?<![\[\"])\b(\w) = \"(\w+)\"", lm.group(1)):
        legend[k] = v
    gm = re.search(r"grid = \{(.*?)\n\t\t\},", body, re.S)
    grid = re.findall(r'"([^"]*)"', gm.group(1))
    return cell, legend, grid


def parse_zones(block):
    """District id, distance and (if drawn) cell rectangle.

    Split on the entry separator, not matched as a whole line: StyLua wraps a
    zone that carries `cells` over four lines as soon as the id is long enough,
    and a one-line pattern then drops exactly the districts that have a
    rectangle -- which is to say, the ones this file exists to check. Same
    mistake as `parse_spawns` below, found the same way.
    """
    m = re.search(r"\n\tzones = \{(.*?)\n\t\},\n", block, re.S)
    zones = []
    for entry in braced(m.group(1)):
        i = re.search(r'id = "(\w+)"', entry)
        d = re.search(r"distance = ([\d.]+)", entry)
        if not (i and d):
            continue
        pts = re.findall(r"Vector2\.new\((\d+), (\d+)\)", entry)
        rect = None
        if len(pts) == 2:
            (x1, y1), (x2, y2) = pts
            rect = ((int(x1), int(y1)), (int(x2), int(y2)))
        zones.append((i.group(1), float(d.group(1)), rect))
    return zones


def braced(body):
    """Every top-level `{...}` in a Luau array-of-tables, as raw text."""
    depth, start = 0, None
    for i, ch in enumerate(body):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                yield body[start : i + 1]


def parse_spawns(block):
    """Population per district.

    Split on the entry separator rather than matching a whole entry, because
    an entry that carries a `behavior` is wrapped across four lines by StyLua
    and a one-line pattern silently skips it -- which is every aggressive
    spawn on the planet, i.e. exactly the districts this most needs to count.
    """
    m = re.search(r"\n\tspawns = \{(.*?)\n\t\},\n", block, re.S)
    pop = {}
    for entry in braced(m.group(1)):
        c = re.search(r"count = (\d+)", entry)
        z = re.search(r'zone = "(\w+)"', entry)
        if c and z:
            pop[z.group(1)] = pop.get(z.group(1), 0) + int(c.group(1))
    return pop


def check(planet, cell, legend, grid, zones, pop, verbose):
    cols = max(len(r) for r in grid)
    rows = len(grid)
    ok = True

    # Held rather than printed. A clean map should say nothing, so that running
    # this from check.sh does not bury the one line that matters under four
    # correct ones.
    report = []
    emit = report.append

    emit(f"=== {planet}: {cols}x{rows} cells, {cell} studs ===")

    ragged = [(i + 1, len(r)) for i, r in enumerate(grid) if len(r) != cols]
    if ragged:
        ok = False
        emit(f"  RAGGED ROWS: {ragged}")

    def glyph(c, r):
        if r < 1 or r > rows:
            return " "
        line = grid[r - 1]
        return " " if c < 1 or c > len(line) else line[c - 1]

    for r in range(1, rows + 1):
        for c in range(1, cols + 1):
            g = glyph(c, r)
            if g != " " and g not in legend:
                ok = False
                emit(f'  UNDECLARED GLYPH "{g}" at row {r} col {c}')
    for g in legend:
        if not any(g in line for line in grid):
            ok = False
            emit(f'  LEGEND "{g}" never appears')

    def walkable(c, r):
        p = PREFABS.get(legend.get(glyph(c, r)))
        return True if p is None else bool(p.get("paved") or p.get("anchor"))

    def offset(c, r):
        return ((c - (cols + 1) / 2) * cell, (r - (rows + 1) / 2) * cell)

    taken = [[False] * cols for _ in range(rows)]
    rects = []
    for r in range(1, rows + 1):
        for c in range(1, cols + 1):
            g = glyph(c, r)
            if g == " " or taken[r - 1][c - 1]:
                continue
            right = c
            while right < cols and glyph(right + 1, r) == g and not taken[r - 1][right]:
                right += 1
            bottom = r
            while bottom < rows and all(
                glyph(cc, bottom + 1) == g and not taken[bottom][cc - 1]
                for cc in range(c, right + 1)
            ):
                bottom += 1
            for rr in range(r, bottom + 1):
                for cc in range(c, right + 1):
                    taken[rr - 1][cc - 1] = True
            rects.append((g, (c, r), (right, bottom)))

    def zone_of(c, r):
        for zid, _d, rect in zones:
            if rect and rect[0][0] <= c <= rect[1][0] and rect[0][1] <= r <= rect[1][1]:
                return zid
        return None

    emit("  -- rooms --")
    counts = {}
    for g, (c1, r1), (c2, r2) in rects:
        if not PREFABS.get(legend.get(g), {}).get("room"):
            continue
        mid = ((c1 + c2) // 2, (r1 + r2) // 2)
        zm, zc = zone_of(*mid), zone_of(c1, r1)
        sides = {
            "+X": sum(walkable(c2 + 1, r) for r in range(r1, r2 + 1)) / (r2 - r1 + 1),
            "-X": sum(walkable(c1 - 1, r) for r in range(r1, r2 + 1)) / (r2 - r1 + 1),
            "+Z": sum(walkable(c, r2 + 1) for c in range(c1, c2 + 1)) / (c2 - c1 + 1),
            "-Z": sum(walkable(c, r1 - 1) for c in range(c1, c2 + 1)) / (c2 - c1 + 1),
        }
        best = max(sides.values())
        door = [k for k, v in sides.items() if v == best][0]
        bad = not (zm and zm == zc and best > 0)
        ok = ok and not bad
        counts[zm] = counts.get(zm, 0) + 1
        emit(
            f"    {legend[g]:5s} rows {r1}-{r2} cols {c1}-{c2} mid={mid} "
            f"zone={zm}/{zc} door={door} open={best:.2f}"
            + ("   <<< PROBLEM" if bad else "")
        )

    anchors = {}
    for g, (c1, r1), (c2, r2) in rects:
        if not PREFABS.get(legend.get(g), {}).get("anchor"):
            continue
        for c in range(c1, c2 + 1):
            for r in range(r1, r2 + 1):
                z = zone_of(c, r)
                anchors[z] = anchors.get(z, 0) + 1
    emit(f"  anchors per district: {anchors}")

    emit("  -- districts --")
    for zid, _d, rect in zones:
        if not rect:
            continue
        (x1, y1), (x2, y2) = rect
        if x2 > cols or y2 > rows or x1 < 1 or y1 < 1:
            ok = False
            emit(f"    {zid}: cells OUT OF BOUNDS")
        ax, az = offset(x1, y1)
        bx, bz = offset(x2, y2)
        hx, hz = (abs(bx - ax) + cell) / 2, (abs(bz - az) + cell) / 2
        n = pop.get(zid, 0)
        pts = min(max(math.ceil(n / ZONE_POINT_LOAD), 3), ZONE_POINTS_MAX)
        parts = pts + counts.get(zid, 0)
        short = n < parts
        ok = ok and not short
        emit(
            f"    {zid:9s} centre=({(ax + bx) / 2:7.1f},{(az + bz) / 2:7.1f}) "
            f"half=({hx:.0f},{hz:.0f}) ring={pts} parts={parts} pop={n}"
            + ("   <<< PROBLEM: fewer NPCs than parts" if short else "")
        )

    corner = math.hypot(cols * cell / 2, rows * cell / 2)
    over = corner >= SCATTER_START
    ok = ok and not over
    emit(
        f"  footprint corner {corner:.0f} (must be < {SCATTER_START})"
        + ("   <<< PROBLEM" if over else "")
    )
    if verbose or not ok:
        print("\n".join(report), "\n")
    return ok


def main():
    args = sys.argv[1:]
    verbose = "-v" in args
    wanted = [a for a in args if a != "-v"]

    text = open(SRC).read()
    drawn, good = 0, True
    for planet, block in blocks(text):
        if wanted and planet not in wanted:
            continue
        layout = parse_layout(block)
        if not layout:
            continue
        drawn += 1
        cell, legend, grid = layout
        zones, pop = parse_zones(block), parse_spawns(block)
        good = check(planet, cell, legend, grid, zones, pop, verbose) and good

    if not good:
        sys.exit(1)
    print(f"{drawn} authored layouts, all clean")


main()
