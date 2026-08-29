#!/usr/bin/env bash
# Typecheck the tree.
#
#   scripts/analyze.sh                 # analyze src/, print diagnostics
#   scripts/analyze.sh --counts        # per-file diagnostic COUNTS, for diffing
#
# Why this is a script and not a command you remember: luau-lsp needs a fresh
# sourcemap, a definitions file that is not in the repo, and two --ignore flags,
# and getting any of them wrong produces output that looks like a clean run.
# Specifically:
#
#   * without --defs, every Roblox type is unknown and the output is noise;
#   * without --sourcemap, no require resolves;
#   * without the --ignore flags, the package tree drowns the real diagnostics.
#
# THE COUNTS MODE IS THE HIGH-YIELD ONE. Run it, keep the file, and diff it
# after a change:
#
#   scripts/analyze.sh --counts > /tmp/before.counts
#   ...edit...
#   scripts/analyze.sh --counts > /tmp/after.counts
#   diff /tmp/before.counts /tmp/after.counts
#
# A raw dump of several hundred lines hides a new diagnostic completely. The
# per-file DELTA does not: a file going 0 -> 1 is visible instantly, and that is
# what a deletion taking a live consumer with it looks like. Total count alone
# is useless — it drifts either way, because a util diagnostic is re-reported
# once per requiring path, so an unrelated new `require` moves it. Per FILE is
# what is stable.
#
# And note what the delta CANNOT see: anything already present in the baseline.
# "Delta clean" means "no NEW diagnostics", never "no defects". Audit the
# baseline once, separately.

set -euo pipefail
cd "$(dirname "$0")/.."

DEFS="${TMPDIR:-/tmp}/luau-globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	echo "fetching globalTypes.d.luau..." >&2
	curl -sSfL \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau \
		-o "$DEFS"
fi

rojo sourcemap default.project.json -o sourcemap.json

# 2>&1 IS LOAD-BEARING. luau-lsp writes its diagnostics to STDERR, not stdout.
# A pipeline that discards stderr -- `... 2>/dev/null | grep TypeError` -- greps
# an empty stream and reports every file clean, forever. That mistake was made
# while writing this script, in a repo whose own docs warn about exactly this
# class, which is how much it does not announce itself.
set +e
OUT=$(luau-lsp analyze \
	--sourcemap=sourcemap.json \
	--defs="$DEFS" \
	--ignore='**/_Index/**' \
	--ignore='**/.pesde/**' \
	src 2>&1)
set -e

# Proof the analyzer actually ran. Zero diagnostics is ambiguous between "clean"
# and "never parsed", and this is the cheap disambiguation: the loader line is
# printed on every real run.
if ! grep -q "Loading definitions file" <<<"$OUT"; then
	echo "analyze.sh: luau-lsp produced no startup output -- it did not run" >&2
	exit 2
fi

if [ "${1:-}" = "--counts" ]; then
	# Sorted by PATH, not by count, so `diff` lines up file for file.
	echo "$OUT" | grep -oE '(/|^)src/[^ ]*\.luau' | sed 's|^.*/src/|src/|' | sort | uniq -c | sort -k2
else
	echo "$OUT"
fi
