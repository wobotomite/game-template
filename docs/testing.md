# Testing

```bash
lune run tests/run           # everything
lune run tests/run wire      # only specs whose name contains "wire"
scripts/analyze.sh           # typecheck
scripts/analyze.sh --counts  # per-file diagnostic counts, for diffing
```

There is no test framework. A spec is a Lune script that prints a line per
assertion and exits non-zero if any failed; `tests/run.luau` runs each in its
own process so one that throws or hangs cannot take the suite with it.

Everything below is a rule that exists because breaking it produced a **green
run over broken code**. That is the failure mode this whole directory is shaped
against — not "the test failed when it should have passed", which announces
itself, but "the test passed while checking nothing", which never does.

## The three kinds of spec

**Pure-logic specs.** Load a module through `tests/roblox-env` and call it.
Works for anything that does not touch a Roblox API at require time.

```luau
local env = require "./roblox-env"
local heuristics = env.load "ServerScriptService.Server.anticheat.heuristics"
```

This is worth designing *for*: keep arithmetic — timing, curves, scoring,
geometry — in a module that touches no engine API, and it becomes directly
testable. `anticheat/heuristics.luau` exists as a separate file for exactly this
reason.

**Source-scanning specs.** Assert a property over the text of the tree: every
require resolves, every wire field is read, nothing dereferences a variable
inside the branch that established it is nil. These catch a whole class the
type-checker cannot see, and they are also where every trap below lives.

**Load specs.** `loads.spec.luau` requires every module and fails if any throws.
Catches record keys renamed out from under a module-scope read, and
`local function` called above its own declaration.

`package-api.spec.luau` is the sharper version of the last one: it requires each
third-party package through `roblox-env` and reads its **real export table**, so
`vide.for_values` — a function that does not exist — fails instead of shipping.
No list to keep in sync, and a package that changes its API in an update fails
on the next run.

`project.spec.luau` checks `default.project.json` against the tree in both
directions: no mount pointing at nothing (Rojo builds anyway, so the symptom is
a subsystem that is simply absent), and no file under `src/` outside every mount
(it typechecks, passes every scan, and is not in the game).

`docs.spec.luau` checks that every path the docs and code comments point at
exists.

`sequence.spec.luau` is the model for testing lifetime machinery: every case
INTERRUPTS a sequence, because a run that completes proves almost nothing about
a module whose whole job is what happens when something stops early.

`harness.spec.luau` tests the harness itself — the stripper, the brace matcher,
the key reader, the require extractor, the walker. It counts and prints for
itself rather than using `h.check`, because a spec that tested the assertion
mechanism THROUGH the assertion mechanism would report clean if that mechanism
were broken to always pass. What `check` is covered by instead is better than a
test: every spec here has been mutation-tested and each went red, which a
`check` that could not fail would have prevented. Prose goes stale silently, and the way it goes stale is a MOVE: rename a
folder and eleven references keep naming the old one. Nothing errors; the reader
follows a precise-looking pointer, finds nothing, and stops trusting the parts
that are still true.

## Prove the scan found something

**A scan that silently matches nothing reports a pass.** This is the single
highest-yield rule here, and it has caught more real problems than the
assertions it guards.

Use `h.saw(what, count, min)`, and set `min` near the number you actually
expect — not at 1:

```luau
h.saw("resolvable requires", checked, 100)
```

Two real examples from this repo:

- `requires.spec` reported `68 checked, 87 skipped, all fine`. The 87 were not
  skipped for a reason — the harness's `strip()` blanks string bodies, and every
  hyphenated module is required as `tables["extend-object"]`, so the name lives
  *inside* a string. Blanked, it became `tables[""]`, which resolved to the
  directory and reported OK. The real number was **155**. A floor of "at least
  one" would have passed that version happily.
- The anticheat spec restated its thresholds under a comment saying "same config
  as anticheat.luau". It proved the numbers it made up were consistent with
  themselves. **Read config out of the source**, and guard the parse.

Also: split "could not check it" from "it is broken". `requires.spec`
distinguishes a *computed* require (`require(child)` in a loader — honestly
uncheckable) from a *static path matching no mount*, which is not unknown at all
— it is exactly what a require copied in from another codebase looks like.
Lumping them together is what let five dead modules ship at once.

## Strip comments AND strings

A source-scanning spec that reads raw text **forbids its own documentation**.
The clearest way to explain a rule is to quote the code it forbids — so the more
precisely someone documents an invariant, the more certainly they trip the check
that enforces it. The same sentence inside a `warn()` does the same thing, which
is why `h.strip()` blanks string bodies by default.

Pass `keep_strings` only when the scan genuinely needs string contents, and say
why (see `requires.spec`, which needs the bracket-form module names).

## Mutation-test, and verify the mutation LANDED

A spec you have not tried to break is a spec you are guessing about. Break the
thing, confirm the spec fails, restore, confirm it passes.

**Verify the mutation actually landed before believing the result.** Twice in
this repo a mutation test reported "not caught" when the truth was "not tried":

```python
anchor = b"const SYNC_AFTER = 6"
assert anchor in backup, "ANCHOR MISSING -- mutation would silently do nothing"
target.write_bytes(backup.replace(anchor, mutated))
assert target.read_bytes() != backup, "MUTATION DID NOT LAND"
```

The first time, the anchor said `local SYNC_AFTER` where the file says `const` —
so nothing changed, both mutations "passed through", and it looked like the spec
was blind. BSD `sed` has no `\b`, which produces the same silence.

**Restore from a byte-exact backup, never `git checkout --`.** Checkout reverts
to HEAD and eats every uncommitted change in that file, which in a working tree
like this one is most of the work.

And mutate one thing at a time, in both directions where the check has two: for
a scan that must ignore prose, inject the prose form (must pass) *and* the real
form (must fail). Checking only that the real bug is caught leaves the
false-positive half invisible.

## Typechecking

`scripts/analyze.sh` wraps luau-lsp with the flags that make its output mean
anything. Three ways to get a fake clean run:

- **luau-lsp writes diagnostics to STDERR.** A pipeline ending in
  `2>/dev/null | grep TypeError` greps an empty stream and reports every file
  clean. This mistake was made *while writing the script*, in a repo whose docs
  warn about the class. The script now also asserts the analyzer printed its
  startup line, so "no output" fails loudly instead of reading as "no problems".
- **Do not filter by line FORMAT.** luau-lsp prints two shapes —
  `/abs/path.luau [game/Path](403,40): TypeError: ...` and
  `src/rel/path.luau(98,10): LintName: ...`. A `grep -E "\.luau\("` matches only
  the second and silently drops every TypeError, including
  `Unknown global 'X'`, which is what a stranded reference looks like after a
  deletion. Filter by diagnostic NAME instead.
- **Zero diagnostics in a file is ambiguous** between "clean" and "never
  parsed". If it matters, copy the file to a scratch dir, inject
  `local probe: number = "x"`, analyze the copy, and grep for the copy's path.

### The per-file count delta

Run `--counts`, keep the file, diff it after a change. This is the highest-yield
check available and it belongs at the *start* of a pass, not the end.

A raw dump of several hundred lines hides one new diagnostic completely. The
delta does not — a file going 0 → 1 is instant, and that is what a deletion
taking a live consumer with it looks like. Total count alone is useless: a util
diagnostic is re-reported once per requiring path, so an unrelated new `require`
moves it. **Per file is what is stable.**

Two real catches, both invisible in the dump and obvious in the delta: a
constant deleted out from under a live consumer (undefined globals read as nil
in Luau, so the next arithmetic on it threw every tick), and five record keys
referenced but absent after a half-landed rename.

**The delta cannot see the baseline.** "Delta clean" means "no NEW diagnostics",
never "no defects". Audit the baseline once, separately.

### The stranded-reference test

`Unknown global 'X'` is noisy in this dialect, because module functions are
declared as bare globals and a call to one defined lower in the same file is
flagged. One mechanical test separates noise from a real bug:

> is the identifier defined **anywhere in its own file**, and *how*?

- later as a bare `function name()` → forward reference, **benign** (bare
  functions are per-script globals, so a later definition still resolves)
- later as a **`local function name()`** → **STRANDED**. A `local` is not in
  scope above its own declaration, so the earlier use compiles as a global read
  and is nil at runtime
- not defined in the file → **stranded**

That distinction is not academic: `util/debug/gizmos.drawCube` was recorded as a
benign forward reference for weeks — it *is* defined in its own file — but as a
`local function` below its caller, so `drawPath` threw for any `dotsSize > 0`.

`GlobalUsedAsLocal` and `LocalShadow` reported for the **same identifier** is the
matching tell from the other side: one says a global was used, the other says a
local later shadows it. Either alone is often noise; together they mean a use
above a `local` declaration.

## The baseline, audited

luau-lsp 1.68 cannot evaluate user-defined type functions, and this codebase
leans on them. That is most of the baseline and it will not shrink. The rest was
run to ground once, file by file; this table is that audit, so nobody redoes it.

| File(s) | Class |
| --- | --- |
| `src/util/tables/const-record`, `src/util/ui/ui-types`, `src/shared/item-util/parse-reward`, `src/effects/effect-types` | `This syntax is not supported` — user-defined type functions |
| `src/util/tables/extend-object`, `src/util/events/pseudo-signal`, `src/util/cached-fns/cache-function` | `Unknown type 'setmetatable'` |
| `src/util/numbers/weighted-random`, `src/util/extra-features/status-effect-handler`, `src/util/analytics/__analytics_funnels` | `keyof` / `index` / generic variance |
| `src/server/data/datastore/init`, `src/server/data/data-lifecycle.server` | members of `services/player-data` read as optional — that module picks its export table at runtime (client vs server), so the analyzer unions both |
| `src/shared/services/appearance` | type-parameter count on `pseudo_signal.new`, which is an error-type here for the reason two rows up |
| `src/util/numbers/bezier`, `src/util/colors/color-gradient`, `src/util/strings/generate-id`, `src/util/constructors/shared-ctor` | narrowing and generic-variance noise (`number?` not narrowed by `x = x or 16`) |
| `src/util/iterators/map-table`, `src/util/iterators/filter-table` | `Expected to return 2 values` — `return nil` is the standard generic-for stop signal |
| `src/util/tween/init`, `src/util/extra-features/cutscene-player/init` | `Unknown global` for bare `function`s defined lower in the file — **verified benign by the test below, not assumed** |
| `src/util/ui/hooks/use-motion` | `Unknown type 'Ripple.*'` — the package's types do not resolve through its link file |
| `src/util/observers/observe-character`, `src/util/colors/lerp-cieluv`, `src/util/ui/hooks/px` | a downcast, a deliberate shadow, and a commented-out constant |

**The count moves without anything changing.** A util diagnostic is re-reported
once per requiring path, so adding an unrelated `require` shifts the total. Per
file is what is stable; that is why `--counts` sorts by path.

### Auditing the baseline is not optional, and it is not the delta

The delta catches regressions. It cannot, by construction, see a defect that was
already there — that diagnostic is in every baseline, so every diff is empty and
every report says "delta clean". Saying "delta clean" and meaning "no defects"
is wrong.

The audit that produced the table above found **two real bugs** among the noise:

- `util/ui/hooks/use-tween` called `Ripple.createTween`, which does not exist in
  ripple 0.6 — the whole module was written against a different version's API.
  It was a byte-for-byte duplicate of `use-motion` with one call changed, so it
  read as obviously fine, and it had no callers, so it never ran. luau-lsp said
  `Key 'createTween' not found in table`, once, in a baseline of hundreds.
- `util/extra-features/change-lighting` kept a weak-keyed table of Instances —
  the class that froze corpses upright in `util/ragdolls`. Nothing reads it yet,
  which is the only reason it had not bitten.

Do not skip reading the util *code* because its diagnostics are noise. An
earlier audit of the same directory found two different real bugs
(`synced-time` returning process uptime for six seconds, `tween` repainting the
outgoing tween's start value) while every one of its diagnostics was noise.
