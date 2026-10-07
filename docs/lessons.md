# Lessons

The durable half of `docs/friction-log.md`, organised by when you would need it
rather than by when it was found. The log stays as the chronological record and
carries the full evidence for every claim here.

One sentence covers most of it: **the failures that cost real time are the ones
that look like success.** Not the crash — the crash announces itself. The check
that examined nothing, the module nobody ran, the flag that replicated, the
teleport that returned cleanly and arrived nowhere.

---

## 1. Writing a check

**A scan that matches nothing reports clean.** Indistinguishable from passing.
Every scan needs an assertion that it *found* something — `h.saw(what, count,
min)` — with `min` near the number you can estimate independently, never at 1.
The first working version of `requires.spec` said `68 checked, 87 skipped, all
fine`; the real number was 155, and a floor of "at least one" would have passed
it happily.

**A scan can also match everything.** The first effects matcher found 35 call
sites, 22 of which were `Instance.new "Part"`. Louder, no more useful, and more
dangerous in one way: the fix that suggests itself is adding exclusions until
the noise stops, which is how a matcher quietly stops matching the real thing.

**Split "could not check it" from "it is broken".** Three different answers, not
two: *checked*, *honestly uncheckable* (a computed require, a package that needs
the engine), and *broken*. Lumping the last two together is what let five dead
modules ship at once. Anything genuinely uncheckable gets named in a list with a
reason — the `use-tween` bug was findable precisely because the not-covered list
was written down.

**Print what you checked, and what you skipped.** A count on screen is
auditable; the same heuristic silent is just a hole.

**Verify the mutation LANDED before believing a mutation test.** Twice here a
mutation test reported "not caught" when the truth was "not tried" — an anchor
saying `local SYNC_AFTER` where the file says `const`. BSD `sed` has no `\b`,
which produces the same silence.

```python
assert anchor in backup,        "ANCHOR MISSING"
assert mutated != backup,       "MUTATION DID NOT LAND"
```

**Restore from a byte-exact backup, never `git checkout --`.** Checkout reverts
to HEAD and eats every uncommitted change in that file.

**Mutate in both directions where a check has two.** For a scan that must ignore
prose, inject the prose form (must pass) *and* the real form (must fail).
Checking only that the real bug is caught leaves the false-positive half
invisible.

**A hang is not a failure.** An assertion that the code did not hang cannot fire
when it hangs — the case never reaches it. Properties about termination need
something outside the process, and a mutation harness needs its own timeout AND
a restore that survives its own death.

**A mutation that survives is usually a too-kind fixture, not an unimportant
property.** Twice in two passes: a waypoint placed exactly under the agent so
the skip could not be observed, and a wait long enough that the unguarded
version had not finished. Ask what the fixture is avoiding.

**A timing test can pass because the mutation had not happened yet.** The same
case, first written with a 5s wait, a cancel at 0.15s and a check at 0.45s,
passed against the very mutation it was written to catch — the unguarded wait
was still waiting. Make the window outlast the thing you are disproving.

**Read the config, do not restate it.** A spec that copies `max_cv = 0.02` under
a comment saying "same as the source" proves the numbers it made up are
consistent with themselves. Parse it out, and guard the parse.

**Open the hits before believing the list.** Three "missing package members"
were exported *types*. Three of five "stale doc paths" were house shorthand. In
both cases the list was right about what it saw and wrong about what it meant.

**A red test is a disagreement, not a bug.** The first question is which side is
confused. One spec here asserted that a listener still ran after another threw,
and the dispatcher of the day ran listeners bare by design, so it never did. The
sequel is the same lesson from the other end: when that dispatcher was later
removed in favour of a thread per listener, the property inverted and the
assertion had to invert with it. A spec that pins a deliberate trade-off should
be re-pointed when the trade-off changes, not deleted for being inconvenient.

**A spec can pass standalone and fail in the runner, and the exit code is why.**
Lune takes the process exit code from a thread that throws — including one that
throws long after the verdict is printed. A spec that deliberately exercises a
throwing listener prints "all cases passed" and still exits non-zero. Every spec
must exit EXPLICITLY as its last act; `tests/harness.luau` does this, and a
hand-rolled spec that forgets it reports a phantom failure.

---

## 2. What fails silently in Roblox and Luau

**A missing table key is `nil`, not an error.** `vide.for_values` and
`ripple.createTween` both shipped; neither exists. `tests/package-api.spec.luau`
reads a package's real export table for this reason.

**A `local function` used above its own declaration compiles as a global read**
— nil at runtime. A bare `function name()` is a per-script global and resolves
fine. luau-lsp reports both identically; the test that separates them is in
[docs/testing.md](testing.md).

**`FindFirstChild "X" :: BasePart` asserts the nil away without checking.** The
failure lands a page later on whatever indexes the nil, naming the wrong file.
Fail at the lookup instead.

**Attributes replicate.** An `AnticheatSuspect` attribute told the suspect their
strike count. Suspicion belongs in a server-side table.

**Weak tables drop live Instances.** An Instance's Lua-side wrapper is
collectable whenever nothing on the Lua side holds it strongly, whatever the
DataModel thinks. Measured: **0 of 40** entries survived. Found twice in this
tree; one instance froze corpses upright and the symptom pointed nowhere near
the table.

**A character's rig is not fixed at spawn.** The appearance load replaces the
Head a few hundred ms in, destroying the Neck Motor6D and anything built on it.

**There is a blank-default appearance window.** Snapshot a `HumanoidDescription`
too early and every consumer wears the grey default all session;
`GetAppliedDescription` also throws during it.

**Unparented preload probes are a no-op.** Create probe Sounds, `PreloadAsync`,
destroy them, and fresh Sounds on those ids are *still* unloaded 100ms later —
identical to a never-preloaded control. Keep them parented. And the control
group is what makes that measurable at all: reading `IsLoaded` off the probe
only proves the property does not populate.

**A Sound that will never load reports `IsPlaying = true` indefinitely.** What
it cannot fake is `TimeLength`. Divide by `PlaybackSpeed` — `TimeLength` is the
asset's length.

**`TeleportAsync` returning cleanly does not mean anybody arrived.** The failure
lands later, as `TeleportInitFailed`. Retry with the SAME `TeleportOptions`: a
reserved server is addressed by the access code inside them, and fresh options
send that player to a public server, alone, with no error anywhere.

**`BindToClose` is a budget, not a notification** — roughly 30 seconds before
the engine kills the server anyway.

**`Player.ReplicationFocus = nil` does not mean "stream nothing"** — it hands
the choice back to Roblox, which falls back to the player's own character.
That is why clearing it by hand seems fine, and why the path you forget leaves a
spectator's focus parked on a teammate: they revive into a room that streams in
late around their own feet. Route every path through one function. A focus set
while the target is between characters lands on nil and **never retries**, so
re-point watchers when a character spawns; and drop watchers before destroying
what they watch.

**`Players.LocalPlayer` is nil on a server.** `on-shutdown` compared against it
and therefore never fired server-side.

**Step `dt` is accumulated time, not the nominal interval.** A backgrounded
Studio server runs at ~19% duty, so a nominal 0.5s sample arrives as ~2.6s.
Anything comparing a distance against a fixed budget has to scale with it.

**A post-processing effect parented into Lighting by hand gets destroyed.** Any
reconciler that morphs Lighting's children toward a mood counts an unexpected
child as one to fade out and destroy — and the script that made it goes on
writing properties to a destroyed instance. Tag it as ignored FIRST, then
parent: the reconciler yields between children, so a parent-then-tag ordering
leaves a real window.

**Unlocking the mouse is a Modal TextButton**, invisible and full-screen, with
`Active = false` so it sinks no input. Refcount the holders — several UIs want
it at once — and remember `MouseIconEnabled`: under `LockFirstPerson` the cursor
is pinned to the middle of the screen on top of your crosshair, so a UI that
unlocks the mouse and draws no usable cursor is worse than no unlock.

**Roblox's stock character sounds are built by a CoreScript** under every
HumanoidRootPart, a beat after the character arrives. The moment you ship your
own footsteps they are a second system playing out of phase on a recording of a
different floor. Remove them by NAME — a blanket sweep of Sounds under the root
eats your own positional audio.

**A character can spawn before the client's camera scripts are up**, which is
routine when `CharacterAutoLoads` is off and something calls `LoadCharacter` on
a timer. The engine's `CameraSubject` bind is simply missed and the camera is
left floating.

**`GetPropertyChangedSignal` does not fire for attributes.** Use
`GetAttributeChangedSignal`.

**Assigning `FilterDescendantsInstances` rebuilds the whole exclusion set**,
changed or not. Maintain the list on lifecycle, not per ray.

**An LCG's low bits have a period as short as 2.** `state % 4` can emit two of
four values forever. Take the high bits.

**`ReflectionService` reports far more than a class's usable properties.** (All
of this is RUNTIME-only -- see section 3 before building anything on it.) Of
Part's 96 entries, only 39 are things you would ever assign. 14 are read-only
(`Mass`, `ClassName`, `ExtentsSize`), 16 have no script permissions at all
(`NetworkOwnerV3`, `IsInSandbox`), and 27 are deprecated -- including fully
writable lowercase aliases like `archivable` and `brickColor`, which no
permission check filters out. Reflection even hands back typos (`shap`, `siz`)
as real properties. Two fields sort it: `Permits`, where the KEY presence is the
signal and the values are `SecurityCapabilities`; and
`Display.DeprecationMessage`. Filter on both or you are offering to autocomplete
the wrong name.

**`Type.ScriptType` and `Type.EngineType` are different vocabularies, and the
one you want is ScriptType.** EngineType says `bool`, `int`, `float`, `double`;
ScriptType says `boolean` and `number`. A mapping table written from memory got
this backwards in both directions -- inventing `int64` and `Ray`, omitting
`Content` and `SecurityCapabilities` -- and the failure mode is silent, because
an unmapped name just yields an unchecked property. Enumerate the real set off a
live service instead of guessing it. Note also that ScriptType flattens every
enum to `EnumItem`, so reflection alone cannot tell `Enum.Material` from
`Enum.PartType`.

---

## 3. What fails silently in this toolchain

**luau-lsp writes diagnostics to STDERR.** A pipeline ending in
`2>/dev/null | grep TypeError` greps an empty stream and reports every file
clean. Use `scripts/analyze.sh`, which captures stderr *and* asserts the
analyzer printed its startup line.

**Do not filter analyzer output by line FORMAT.** It prints two shapes; a
`grep -E "\.luau\("` matches only one and drops every TypeError.

**The per-file count delta is the highest-yield check, and it is blind to the
baseline.** "Delta clean" means no NEW diagnostics, never no defects. Audit the
baseline once, separately — two such audits here each produced two real bugs
while every diagnostic around them was noise.

**The sendbufs server has no queue.** An event fired at the server before its
handler connects is discarded silently (since 1.1.3 the client holds up to 256
reliable messages per event for its first listener). Connect every handler
before anything that can yield, and make handshakes retry until something proves
the other side heard. The sharpest
version of this: a party gate waiting on a once-fired "I am ready" holds the
WHOLE party for the full timeout when one such event is lost, with no error,
nothing in the console, and no failing test — so pair the ordering rule with a
spec that enforces it. The same
property is the cleanest way to keep a debug wire dead in production — which
makes that a *security property about ordering*, and ordering is what a refactor
breaks while looking like tidying.

**Event ids are declaration order.** Inserting one in the middle renumbers the
rest.

**An `assert` in a remote handler is a client-triggerable server error.** Reject
silently. And check NaN explicitly: `typeof(n) == "number"` is true for it, and
`n > max` and `n < min` are *both* false.

**A tumbling rate-limit window bites in both directions.** Worst case is 2x the
cap; and a sender at exactly the cap *loses* sends to the boundary.

**User-defined type functions are checked by nothing you run on the command
line.** luau-lsp does not implement them: it reports "This syntax is not
supported" and every type they produce becomes an error type, so on the command
line the checking is simply absent. `util/instances/create-new` and
`src/effects/effect-types` each carry that pair of permanently-benign
diagnostics, and `keyof` is unsupported there too. Never read a clean
`scripts/analyze.sh` as evidence that a name checked by one of these is right.

**A type function cannot reach the DataModel, and failing to notice costs a
whole design.** Their sandbox allows assert/error/print, the pcall family,
math/table/string/bit32/utf8/buffer and `types` -- host APIs are not in it, so
`game` is nil and `game:GetService` throws. A version of `create-new` built on
`ReflectionService` would therefore fall through to its permissive fallback on
every call -- inert in the way that looks exactly like working, because a
guarded type function degrades silently by design. Being reachable at RUNTIME
proves nothing: that is where the reflection data was read, successfully, which
is precisely what made the design look sound. (Stated as INFERENCE from the
allowlist. It has not been observed -- the one attempt to check it was run
against a Studio place the module had never synced to.)

**The pattern that does work is a name-to-type table plus `:properties()`.**
`type Creatable = { Part: Part, Frame: Frame, ... }` is something the analyser
already understands; a type function indexes it with `readproperty` and then
walks the class type's own properties. No host access, and `prop.write` sorts
writable from read-only for free -- better than reflection's `Permits`, without
the lookup. Walk the parent chain: `Part` declares few properties, and `Name`,
`Parent` and `Size` live above it.

**Singleton inference is what makes or breaks all of it.** `class: Class &
string` lets the solver widen `"Part"` to `string`; `:value()` then throws on a
non-singleton, and every call quietly gets the permissive table. Constrain to
`Class & keyof<Creatable>` instead -- a union of string singletons is the
position that keeps a literal narrow -- and a bogus class name becomes an error
at the argument rather than a silent downgrade to unchecked.

**Lune rejects `const` and `f<<T>>()`.** `tests/roblox-env` rewrites them. Lune
also takes a process's exit code from a thread that throws long after the
verdict — `harness.done()` exits explicitly for that reason.

---

## 4. Shape

**A module nobody has run is a module nobody has found the bug in.** Four of the
five modules that could not load had no callers. `use-tween` was a byte-for-byte
duplicate of `use-motion` with one call changed, so it *read* as fine.

**Keep arithmetic in a module that touches no engine API.** Timing, curves,
scoring, geometry — it becomes directly testable.
`anticheat/heuristics.luau` exists as a separate file for exactly this.

**Derive, do not restate.** `attempts * delay + grace` cannot drift when
somebody raises `attempts`. The same number typed twice will.

**Records over literals.** A string literal in two files is a contract nothing
checks: server writes `FlickerLight`, client scans for `FlickerLights`, no
error, feature quietly dead.

**Capability probes must probe what you write, not the class name.**
`vide.create "UIShadow" {}` succeeds on a client that rejects the *value* you
were going to pass — and inside a vide tree that throw takes the whole mount
down.

**"Remember to check the return value" is not a safety property.** A cancelled
wait that RETURNS lets the rest of the step run — closing the door on the empty
room — because ignoring a return value is the default. A cancelled wait that
ABORTS cannot be ignored. Found by mutation: removing the cancellation check
from inside a wait broke nothing, which meant nothing relied on it.

**Pin counts exactly; do not bound them.** A `>= 20` check stayed green while
three effects were deleted one at a time. A bound is only a check outside its
own slack.

**Documenting an invariant trips the check that enforces it.** The clearest way
to explain a rule is to quote what it forbids. Strip comments *and* strings; for
paths, write the deliberately-absent one without backticks. This document's own
predecessor failed its own check twice.

**The thing that checks is as capable of being wrong as the thing checked, and
it fails more quietly, because its failure looks like good news.** Of the bugs
found in this exercise, several were in the test infrastructure: a decorative
seed, an RNG with no low-bit entropy, a matcher that saw everything, a matcher
that saw nothing, an assertion that was never true.

**A defensive branch is an assertion about the environment, and it deserves the
same scepticism as any other untested claim.** `create-new` carried a fallback
for months justified by a comment stating that Lune "accepts unknown properties
silently". Measured, Lune raises on that write exactly like Roblox does and
hands back a genuine C setter. The claim was never true, so the branch had never
once been taken -- dead code wearing the costume of a safety net, and it made
the module read as if it were propping up something fragile. If a comment
explains why a branch must exist, the branch is only as good as the measurement
behind the comment.

**Before believing "it does not work", check that the code under test is the
code being run.** A stale Rojo connection produces exactly the same observation
as a broken feature, and the two are indistinguishable from the editor. Here a
type function was redesigned twice on the strength of a report that turned out
to mean the module had never been synced into the place at all. Reading the live
tree costs one call; the redesign cost considerably more.

**`Instance.new "Part"` is already typed, so a property-table builder is a
downgrade for straight-line construction.** Every write after
`Instance.new "Part"` is checked against the real class by luau-lsp -- `part.Sixe`
is "Key 'Sixe' not found in external type 'Part'" on the command line. A builder
whose checking comes from a user-defined type function is checked only in
Studio, so converting hand-written construction to it trades a CI check for an
editor-only one. Property-table builders earn their place where the properties
are DATA -- merged defaults, caller-supplied tables, config -- not as a
general replacement. (The one thing the builder catches that a direct write does
not is assigning a read-only property: `part.Mass = 5` passes luau-lsp silently.)

**"Retry once" is not the same as "cannot happen", and the exact version is
usually the same cost.** A draw that re-rolls on a collision repeats a quarter
of the time on a two-element list, and the comment defending it framed the
choice as avoiding an unbounded loop. Drawing from the n-1 others and stepping
over the excluded slot is exactly uniform, impossible to violate, O(1), and has
no loop to bound. When code settles for "usually", check whether the exact
version actually costs anything before accepting the trade.

**Logic that cannot be reached from a module's exports cannot be specced, and
that is where the almost-right code lives.** The draw above sat among three
module-level variables, reachable only through an export that plays audio. It
was not tested because it was not testable, and the fix was to make it a pure
function taking its RNG as an argument -- not to write a more elaborate test.

**A wrapper around a two-line API earns itself when the API fails silently.**
`debug.profileend()` with nothing open does not error, does not warn and returns
nothing, so a leaked scope produces a plausible wrong flame graph instead of a
complaint. Counting the depth and saying so once is the entire value of
`util/debug/profile`; the rest is pass-through.

**A check must accept every correct shape, not the one you happened to write.**
A spec asserting that observer destructors are not dropped counted only
assignment and `return` as "kept", and duly reported four
`vide.cleanup(observe_character(...))` sites -- the best way to write it -- as
violations. Prefer defining the VIOLATION narrowly (a statement that starts with
the call discards its result) over enumerating the ways of being right.

**A spec mirrored into another tree must not name paths from this one.** Shared
specs are copied verbatim between the template and the game built from it, and
the two layouts differ. A concrete path in a comment here is a broken reference
there, reported by the very check that comment explains.

**A check placed after the early returns is absent from every case that takes
one.** A stuck detector sat at the bottom of a follower, after it had committed
to a waypoint, so it ran only while a route existed -- and the paths that
returned early (no route, route exhausted, target off the navmesh) are exactly
the ones where an agent is grinding against geometry. Put a guard where every
path reaches it, not where the happy path ends.

**A default that works only because of the magnitude of a real clock is a bug
waiting for a fake one.** `last_compute_at = 0` reads as "never" and behaves as
"never" while the clock is `os.clock()`. Hand it any clock starting near zero
and the first action is deferred by a full interval. `-math.huge` is what
"never" actually is.

**A failure status is a hint about which retry to make, not just an error.**
`FailStartNotEmpty` means the START is unroutable, so nudge the start;
`NoPath` to a door means the GOAL is inside geometry, so relax the goal. Reading
the status turns a blanket cross product of retries into one targeted attempt
each.

**A benchmark that returns the same number for easy and hard work is measuring
the scheduler.** `ComputeAsync` timed at 99.98 ms for a long route, a short one
and forty different goals alike. The tell was the control: the call that THREW
instead of yielding took 0.047 ms. What was measured is that the call yields,
not what it costs -- and that is still the useful fact, because a yield per
agent per tick is what a cache removes.

**A cache is a machine for handing out stale answers at scale, so design the
invalidation before the lookup.** For routes that means a short TTL, eviction
when the engine reports the route blocked, and the agent's own dimensions in the
key -- a route for a small agent is not a route for a large one. Anything the
key cannot represent (labelled navmesh costs) must bypass the cache rather than
be silently ignored.

**Forwarding a curated subset of options silently drops the rest.** A follower
passed two of its router's fields through and no others, so half that router's
behaviour was unreachable from the only public entry point -- and an injected
clock stopped at the boundary, leaving two clocks inside one object. Build the
forwarded table in one place and assert in a spec that each field arrives.

**A documented engine signal is not a mechanism until you have watched it
fire.** `Path.Blocked` is exactly what you would build a blocked-route design
around, and an entire pass was. Sealing a computed route produced no callback in
five seconds, in two datamodels. Design the recovery around the thing you can
demonstrate -- here, recomputing on a timer, which visibly routed around the
obstacle -- and keep the signal as a bonus.

**A cache TTL longer than the refresh interval it sits under makes the refresh a
no-op.** A follower re-anchored every second so a stale route would be replaced;
the cache remembered routes for three, so the re-anchor got the stale route
back. Both halves were individually correct and every spec was green. When a
layer caches for another layer that has its own freshness rule, the cache must
be the fresher of the two, and the binding belongs in code rather than in two
defaults that happen to agree.

**Standing on the goal is not being stuck.** A stuck detector measures "not
moving", and an agent that has arrived and is still being driven is not moving
-- so it gets declared stuck forever, once per `stuck_after`, and the default
recovery (a jump) turns success into a visible twitch. No spec caught it because
every spec drove an agent that was going somewhere. Watching one arrive did.

**A redundant guard that no mutation can kill is not defence in depth, it is a
second thing to keep true.** Two mechanisms enforced the same rule; deleting
either left every test green. Keep the one that is load-bearing, and prove which
that is by deleting the other.

**A file whose name makes its folder a Script cannot be filed away.**
`src/client/init.client.luau` is not a module inside `ReplicatedStorage.Client`
-- it is what makes `ReplicatedStorage.Client` a Script. Tidying it into a
subfolder does not move a module, it dissolves the boot script. Same for the
server half.

**After a move, the type checker is the least useful of the checks.** It stayed
at exactly the same diagnostic count through two large reorganisations, because
a require that no longer resolves is not a type error. What actually caught
things: a spec that requires every module, a spec that checks documented paths,
and -- twice -- specs that grep source for a path and therefore have to be moved
along with it.
