#!/usr/bin/env bash
#
# Formats, lints and type-checks the whole codebase.
#
# There is no way to run Luau code outside Roblox, so this is as close to a test
# suite as the project gets. It is worth running before every Studio session:
# a type error found here costs seconds, the same error found in Studio costs a
# reload and a replay.
#
# Requires the rokit-managed tools; run `rokit install` once first.

set -euo pipefail

cd "$(dirname "$0")"
export PATH="$HOME/.rokit/bin:$PATH"

# luau-lsp needs to be told what Roblox's own API looks like. The file is
# generated from the live API dump, so it is fetched rather than committed and
# lives outside the repo to keep it out of git.
GLOBAL_TYPES="${TMPDIR:-/tmp}/roblox-globalTypes.d.luau"
if [ ! -f "$GLOBAL_TYPES" ]; then
	echo "==> fetching Roblox API definitions"
	curl -fsSL -o "$GLOBAL_TYPES" \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

echo "==> stylua"
stylua src/

echo "==> selene"
selene src/

# luau-lsp resolves `require(Shared.Config.Planets)` by consulting the same
# Rojo mapping Studio uses, so the sourcemap has to be regenerated whenever
# files move.
echo "==> sourcemap"
SOURCEMAP="${TMPDIR:-/tmp}/starwars-sourcemap.json"
rojo sourcemap default.project.json --output "$SOURCEMAP" >/dev/null

echo "==> luau-lsp analyze"
luau-lsp analyze \
	--definitions="$GLOBAL_TYPES" \
	--sourcemap="$SOURCEMAP" \
	src/

# The authored ASCII maps type-check trivially -- they are strings -- so nothing
# above can see a ragged row, a room with no door, or a district holding fewer
# NPCs than it has places to put them. `Planets.validate` catches some of it, but
# only at boot, which is a Studio session away.
echo "==> layouts"
python3 tools/gridcheck.py

echo "all clean"
