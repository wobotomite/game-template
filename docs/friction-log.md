# Friction log

What actually cost time building a game on this template, and what was changed
here so it costs nothing next time. Newest pass at the top.

The rule for anything landing in this file: it has to be a **template-level**
problem — something that would bite *any* game built from this tree, not a
quirk of one game's design.

**Looking for the rules rather than the history?** [lessons.md](lessons.md) is
the durable half of this file, organised by when you would need it. This one is
chronological on purpose: it keeps the evidence, the measurements and the wrong
turns, which is what makes the rules there believable rather than merely
plausible.

---

## Pass 40 — 2026-08-29 · sorting the scripts into folders

`shared` was sorted in an earlier pass; `client` and `server` never were --
15 and 11 loose files. In the game it is the mirror image: its client and server
are already `common` / `lobby` / `run`, and its `shared` had 14 loose files. So
each tree got the half it was missing.

**Template.** client -> `audio` (3), `boot` (2), `character` (4), `debug`,
`input`, `net` (2), `visuals`, plus the existing `ui`. server -> `boot`,
`data` (award, data-lifecycle and the datastore folder together), `net`
(server-network, sync.server, and validate -- it validates remote payloads, so
it belongs with the remotes), `players` (4), plus the existing `anticheat`.

**Game.** shared -> `services` (alert, appearance-service, player-data,
sync-registry), `world` (character-exclusion, model-layout, build-part,
prefabs), `atoms` (run-atoms, lobby-atoms).

### What must not move, and why

`init.client.luau` and `init.server.luau` ARE the container Scripts --
`src/client` maps to `ReplicatedStorage.Client`, which is a Script precisely
because that file is there. Moving either into a subfolder does not relocate a
module, it dissolves the boot script. Both stayed at the root.

`network`, `place-context`, `ghost-types` and `run-over` also stayed loose. The
template keeps its equivalents at the root, and they are cross-cutting
vocabulary rather than members of any group -- a folder per file would be
sorting for its own sake.

### What broke, and what caught it

105 references in the game and about 40 in the template. The interesting part is
which check found which:

- **The analyzer found nothing** -- it stayed at exactly 55 and 98 unique
  diagnostics through both moves. A require that stops resolving is not a type
  error.
- **`requires.spec` and `loads.spec` were the real net** for module paths: both
  stayed green, which is what says every rewritten require still resolves.
- **`docs.spec` caught the prose**, including two doc pages and a spec header.
- **Two source-scanning specs caught themselves.** `elevator-controls` asserts
  that both realms require the atoms module by matching
  `Shared%["lobby%-atoms"%]` in the source; after the move the string is
  `Shared.atoms["lobby-atoms"]` and the pattern failed -- correctly. A spec that
  greps for a path is a spec that has to move with it.
- **Two specs read source files off disk** (`fs.readFile "src/shared/..."`) and
  failed on the filesystem path, not the require path. Worth knowing that those
  are a separate class from everything above.

Verified in Studio afterwards rather than assumed: `ReplicatedStorage.Client`
and `ServerScriptService.Server` are still Scripts, and every rewritten path
(`Client.boot["wait-for-loaded"]`, `Server.data.datastore`, `Server.net.validate`,
`Server.players["party-gate"]`, ...) resolves to a real instance.

---

## Pass 39 — 2026-08-29 · driving a real Humanoid through a door that shuts

The follower had never moved an actual Humanoid. Built a walking rig in a
running Server, drove it across an arena with two doorways, and closed things in
front of it.

### Door shut mid-route: it goes around

Rig walking toward the near doorway; at t=2.1 s, at z=-23, the doorway was
sealed with an anchored colliding part.

    t=2.3  z=-21 x= 0    <- committed to the near door
    t=4.5  z= -7 x=32    <- detouring east
    t=6.7  z= 20 x=26
    t=8.9  z= 48 x= 5
    ARRIVED at 9.0s, max_x=40 (the far doorway)

Status `Success`, zero failures. `Path.Blocked` never fired; the 1 s re-anchor
is what did it, exactly as the previous pass concluded.

### Goal made impossible, then possible again

Sealing BOTH doorways with the agent halfway:

    t= 6.4  z=-2  pathing=false status=NoPath fails=3 stuck=1
    t=10.4  z=-2  pathing=false status=NoPath fails=4 stuck=4
    t=14.5  z=-2  pathing=false status=NoPath fails=5 stuck=6
    t=16.6  *** near doorway reopened ***
    t=18.6  z=29  <- moving again
    t=20.1  ARRIVED

Three things worth having on record. It **reported** the situation
(`NoPath`, `pathing=false`) rather than pretending. The **backoff worked**:
failures went 3→4→5 across eight seconds, so roughly two computes in that
window instead of twenty a second, which is the difference between a readable
console and a buried one. And it **recovered on its own** when the way reopened,
with no external nudge.

(First attempt at this test was invalid: the arena's wall did not span the
floor, so the agent legitimately walked around the west end at x=-53. The wall
spans it now. Worth writing down because the run LOOKED like a pass.)

### Arrival is not being stuck -- found by watching it

An agent parked on its goal and still being driven is, by definition, not
moving. The stuck detector duly fired: **ten `on_stuck` calls in twelve
seconds**, which with the default handler is a hop every 1.5 s, forever. That is
the follower reading success as failure, and no spec would have found it because
every spec drove an agent that was going somewhere.

`arrive_range` (4 studs, flat) now zeroes the slow-window, and `has_arrived()`
exposes it. Re-run live: **0 stuck calls while parked on the goal for four
seconds**, down from ten.

The first version also carried a `not arrived and` guard on the stuck check. A
mutation removing it changed nothing -- the reset above already zeroes the
window, so the guard could never fire. Removed: redundant belt-and-braces that
no test can kill is just a second thing to keep true. The reset itself IS
load-bearing, confirmed by deleting it (3 stuck calls, spec red).

### Known reaction times, since they are now measured rather than guessed

- Door shuts across the route: up to `refresh_seconds` (1 s default).
- Way reopens while the agent is parked: up to `max_recompute_interval` (4 s
  default), because the backoff is still counting. Acceptable, documented, and
  the knob to turn if it is not.

---

## Pass 38 — 2026-08-29 · running it for real, and losing the headline feature

Everything to this point was Lune specs with injected routers -- the real
`compute` had never executed. Ran it against `PathfindingService` on built
geometry, in Edit and in a running Server.

### Confirmed live

| | |
|---|---|
| route through a doorway | `Success`, **3 waypoints** -- `math.huge` spacing giving bends only |
| cache, 3 asks in one cell | **1 compute, 2 hits, 1 entry** |
| cache TTL | 2 immediate asks = 1 compute; past the TTL = 2 |
| target sealed in a box | `NoPath`, nil, no throw |
| NaN target | caught by the input guard, status `NaN` |
| 1e6 studs away | `Threw`, nil returned cleanly -- the pcall earning itself |

### `Path.Blocked` does not fire

Sealing a computed route with an anchored colliding part and waiting five
seconds produced **no callback** -- not in Edit, not in a running Server. Twice.

That is the mechanism the last pass was built around and described as "the only
notification the engine gives". It is not load-bearing, and three modules said
it was. All three are corrected: the subscription stays (one connection per
route, correct if it ever fires) but it is documented as a bonus, not a
mechanism.

**What actually recovers an agent is the re-anchor**, and that IS proven on the
same geometry: before sealing, the route ran through the near doorway
(x = 0,-2,0); after sealing, a recompute returned `Success` with x = 0,40,40,0 --
around by the far doorway. So the worst case for a shut door is
`refresh_seconds`, and that is the number to tune, not the signal.

### Which exposed a real interaction bug

The cache's default TTL was **3 s** and the follower re-anchors every **1 s**.
The re-anchor exists to replace a route computed from where the agent used to
be -- and it would have been handed back that very route from cache, for two
more seconds. The cache would have silently become the staleness of the whole
system, and every spec would have stayed green because each half is correct
alone.

Fixed twice over: the module default is now 1 s, and `follow` passes its own
`refresh_seconds` as the TTL, with a spec asserting the default binding and a
mutation confirming it fails when unbound.

### Still not proven

The candidate retries. The fixture meant to bury an agent's start inside a
pillar did not provoke `FailStartNotEmpty` -- both the retry and no-retry calls
returned `Success`, so nothing failed and the retry had nothing to recover. The
logic is spec'd against a stand-in and was taken from the game's test bot where
it was tuned live, but I have not made it fire on demand and am not claiming I
have.

---

## Pass 37 — 2026-08-29 · a path cache, and a number that was not a cost

### The measurement, and why I am not quoting it as a cost

Benchmarked `ComputeAsync` in Studio: a long route across clutter, a 25-stud
hop, and forty different goals all returned **99.98 ms per call** -- the same
figure to two decimal places. That is not what pathfinding costs, that is a
scheduler tick. The control makes it plain: the unreachable target that THREW
instead of yielding came back in **0.047 ms**, and `CreatePath` + `Destroy` on
its own is **0.004 ms**.

So the honest claim is not "a route costs 100 ms of CPU" -- I never measured CPU
-- it is that **every route costs a yield**, and yields are what turn twelve
NPCs asking for a route in one tick into twelve scheduler round trips. That is
the thing a cache removes.

(This is the perf-notes rule about backgrounded Studio doing its job in a new
place: a suspiciously uniform number is a frame boundary, not work.)

### util/pathfinding/cache

A few seconds of shared memory in front of `compute`, same signature, now the
default router for `follow` (`route = pathfinding.compute` opts out).

A cache is a machine for handing out stale routes at scale, so the interesting
part is what stops it:

- **Blocked evicts.** The cache subscribes to each cached route's `Blocked`
  signal ONCE -- not once per follower -- and drops the entry when it fires,
  notifying every follower currently on that route. The first agent to discover
  a shut door fixes it for everyone still to ask, instead of each of them
  walking into it and finding out alone.
- **The agent is in the key.** A route for a 2-stud radius is not a route for a
  6-stud one; a walking route is not a jumping one.
- **Costs bypass it.** Labelled navmesh costs change the route and cannot be
  compared cheaply, so a call carrying them is not answered from a key that
  ignores them -- unless the caller names the variant with `cache_key`.
- **Failures are remembered briefly** (0.5 s by default, against 3 s for a
  route). Without it every agent in a party pays a yield to learn the same "no"
  in the same tick; for much longer than that and they stand still after the way
  is clear.

The handout addresses the ENTRY, never the Path -- which is what lets one engine
subscription serve every follower, and means evicting an entry cannot pull the
rug from a follower still holding the result (its waypoints are a plain array
and stay valid).

### Wiring it in found a real defect

`follow` forwarded exactly two fields to its router: `agent_radius` and
`agent_height`. So `allow_jump_retry`, `retry_candidates` and `costs` were
unreachable through `follow` at all -- and the cache, receiving no `clock`, ran
on `os.clock` while the follower ran on whatever clock it was given. **Two
different clocks inside one agent**, with cache entries expiring on a timeline
the throttle knew nothing about. Now built once and forwarded whole, with a spec
that asserts each field arrives and that the clock is shared.

### Waypoint spacing

Asked for, already true and now checked: `compute` applies `WaypointSpacing =
math.huge` unconditionally -- there is no option to make it denser, in either
tree. Waypoints only where the route bends or acts. (The measurement behind it
is still in the module header: 5 waypoints at `math.huge` against 13 at the
default and 419 at `-1`, on one live route.)

Nine mutations across the cache and the forwarding, all caught.

---

## Pass 36 — 2026-08-29 · pathfinding that survives a closed door

`util/pathfinding` handled the happy path and the throttle. What it did not
handle was any of the ways a route stops being a route.

### What it survives now

- **A route that becomes blocked.** `Path.Blocked` is the only notification the
  engine gives, it gives it once, and the old `compute` dropped the Path on the
  floor -- so nothing could subscribe. A shut door meant the agent ground
  against it until the stuck timer noticed 1.5 s later. The Path now outlives
  the call, the follower subscribes for the life of each route, and a blockage
  AHEAD of the agent retires the route immediately. Behind it is ignored:
  reacting would throw away a good route repeatedly for anything walking away
  through a door closing behind it.
- **A goal it cannot reach.** `ClosestNoPath` / `ClosestOutOfRange` mean "here
  is the way to the nearest point I could reach". The old code returned nil for
  anything but `Success`, leaving the follower to choose between standing still
  and walking in a straight line at a target behind a wall. Partial routes are
  now followed and flagged, so a caller can tell "arrived" from "got as close as
  the navmesh allows".
- **A start or goal that is not on the navmesh at all.** An agent leaning on a
  prop overlaps its own agent cylinder and fails instantly with
  `FailStartNotEmpty` -- precisely when a route matters. A step back, a step up,
  the goal flattened to the caller's height, the goal pulled toward them. These
  came from the ghost game's test bot, tuned against live geometry; folding them
  into the util is the one thing that travelled in that direction this session.
- **A goal that is permanently unreachable.** Consecutive failures now back the
  interval off to a ceiling. Before, an agent shuffling at a wall computed every
  0.4 s forever, and `ComputeAsync` failures log.

### Three bugs, and what exposed each

**The clock became injectable and immediately paid for it.** `last_compute_at`
was initialised to `0`, which is only "long ago" because `os.clock()` returns a
big number. Hand it a clock starting near zero -- a spec's, or a run-relative
one -- and the FIRST compute is deferred by a whole interval: pathfinding does
nothing for the first half-second after an agent spawns. Nothing could have
found this while the clock was `os.clock` by construction.

**The stuck detector was absent from the case it was written for.** It sat at
the bottom of `move_to`, after the follower had committed to a waypoint, so it
was reached only while a route existed. Every early return skipped it -- no
route, route exhausted, target off the navmesh -- which are the same paths that
fall back to walking in a straight line, i.e. exactly when an agent is most
likely to be grinding against geometry. Found by a spec that walked an agent to
the end of its route and then stopped dead; the fix is four lines higher up.

**The stuck window could not be left.** Slowness was judged by comparing one
tick's displacement against a threshold that GREW with how long the agent had
been slow, so an agent stuck for a second needed to cover a full stud in a
single frame to count as moving. It could enter the state and not leave it under
its own power. Now distance and time accumulate over a window -- which also
survives Studio's frame delta not being wall time.

### Measured, not assumed

Probed a live Path: **`ConnectToBlocked` does not exist** (it is the `Blocked`
and `Unblocked` signals -- indexing the method name throws), the status set is
Success / ClosestNoPath / ClosestOutOfRange / FailStartNotEmpty /
FailFinishNotEmpty / NoPath, and a target 50,000 studs out **throws** while a
NaN target returns `NoPath` cleanly. The old comment had that backwards and
named NaN as the throwing case.

Honest about the gap: I could not produce a live `ClosestNoPath` -- the geometry
probe degenerated into pathing across Terrain -- so the partial branch is
written from the documented meaning of those statuses, and the follower treats a
partial route as best-effort rather than trusting it.

### Nine mutations, two of which found fixtures rather than code

All nine caught in the end. Two were too kind first: the moving phase in the
stuck test was shorter than `stuck_after`, so it passed whether or not the
window cleared; and a fixture asserted a waypoint was "behind" the agent when
the follower still considered it current -- the follower advances only within
`waypoint_range` of the CURRENT waypoint and does not skip ones it overshot,
which is worth knowing and is now written down.

**Not mirrored.** The game has no `util/pathfinding`; its ghosts steer, and its
test bot carries its own router. The template is where this belongs.

---

## Pass 35 — 2026-08-29 · a profiler, an observer audit, and two specs that lied to me

### util/debug/profile

`debug.profilebegin` / `debug.profileend` are already a two-line API, so the
wrapper had to earn itself. It earns itself on one measured fact: **an
unbalanced `debug.profileend()` is silently tolerated** -- no error, no warning,
no return value. A scope leaked by an early return does not announce itself;
every later scope just nests one level too deep and the MicroProfiler shows a
plausible, wrong picture. That is worse than no picture, because it is the tool
you open when you already distrust your own guesses.

Measured in Studio, warmed, best of five interleaved rounds:

    profilebegin + profileend        51.6 ns per pair
    ...with a concatenated label     92.1 ns per pair
    setmemorycategory + reset        77.4 ns per pair

51.6 ns is why there is NO debug-flag gate -- one property write is ~90 ns.
Markers are meant to be left in; the MicroProfiler runs on live servers, and a
marker you have to switch on is off when you need it. The cost worth avoiding is
the LABEL, not the marker: a concatenated label nearly doubles the pair and
allocates a string per frame.

Two forms, because a per-frame call site should not have to choose between cheap
and correct: `begin`/`close` allocates nothing, `open` returns a closure, and
`scope` closes even when the work throws. Wired into `render-step`,
`physics-step`, and in the game `ghost-service.step` (three labels: the tick
loop, replication, and the whole step).

### The docs check had a hole exactly where its own examples live

`tests/docs.spec` scanned `docs/`, `README.md` and `src/` comments -- not
`tests/`. Spec headers are dense with pointers and were the one place nothing
checked. Adding it took the count from 174 to 236 and immediately found that
**this very file cited a spec that exists in the game and not in the template**:
the check for stale references was carrying a stale reference, in the only
directory it declined to read.

Its own header then failed the widened check four more times, on the
deliberately-fictional paths it uses to explain itself -- the
documenting-an-invariant-trips-the-check trap, again. Fixed by making the
examples real or generic, plus a note at the top of the file: **keep concrete
tree paths out of a spec that is mirrored into a differently-shaped tree.**
Three of the ghost's six findings were exactly that mistake.

### Observers: 38 sites, no leaks, one wrong shape

Audited every `observe_players` / `observe_character` call in both trees. All 38
are module-scope, re-entry guarded, or hand the destructor somewhere -- so
nothing leaks today. One shape was still wrong: `validate.limiter` is a FACTORY
that took a fresh permanent subscription per limiter and returned no way to
release it. Every caller happens to build theirs once at module scope, so the
count is small and fixed; the shape only bites once somebody builds one per room
or per run. Now one subscription serves every limiter.

The rest of the value is the spec, because the invariant is invisible from any
single call site and the failure is silent: a subscription taken inside a
function that runs twice does not error or leak visibly, it STACKS. The fifth
run has five observers and every callback fires five times, so the bug appears
days in and scales with uptime.

### Both new specs lied to me first, and mutation is what said so

- **profile.spec** passed with the idempotence guard deleted. The test closed
  one scope twice at depth 0, where the *underflow* guard catches the second
  close anyway. The damage a double close actually does is eat the ENCLOSING
  scope, so the fixture needed an outer scope to damage.
- **observer-cleanup.spec** passed with an unguarded subscription injected,
  because it accepted any `if X then return end` anywhere in the function as a
  re-entry guard -- so every function with an ordinary early return read as
  guarded. Now it requires a matched flag pair appearing BEFORE the call.
- The same spec then reported four `vide.cleanup(observe_character(...))` sites
  -- the single most correct way to write this -- as violations, because
  "captured" only accepted assignment and `return`. Four false positives out of
  six findings is how a spec gets deleted. The rule is now the honest one: only
  a statement that STARTS with the call discards anything.

---

## Pass 34 — 2026-08-29 · removing fire_sync, and what it was holding up

`pseudo_signal.fire_sync` is gone at the owner's direction, and both step
dispatchers now use `fire`, which gives each listener its own thread. The
straight cost is the one the removed comment advertised: ~0.74us per listener
per frame, paid by every live per-effect listener. What it buys is error
isolation, and the interesting part is how much was resting on NOT having it.

### Four things had to move with it

- **`no-yield` lost its only caller.** The require is gone from pseudo-signal;
  the util module stays.
- **The scratch-buffer rationale was half-obsolete.** The take-and-hand-back
  shape was justified by re-entrancy AND by failing safe when a listener threw
  past the hand-back. `task.spawn` contains that now, so the second half is
  close to unreachable. The shape is kept for re-entrancy, and the comment says
  which half is still live rather than quietly keeping both claims.
- **Two specs asserted the OPPOSITE property.** `signals.spec` and the game's
  `pseudo-signal.spec` both pinned "a throw propagates, and the other listeners
  are lost" as deliberate. Inverted rather than deleted -- the new assertions
  are that the error does NOT reach the caller and that the other listeners
  still run.
- **`step-containment.spec` was built on the bare dispatch.** That spec had
  written its own escape hatch: "This spec's entire rationale is that /util
  dispatches bare. If that ever changes, the guard stops being load-bearing and
  this note should be revisited rather than silently kept." So it was, and its
  premise section now checks the inverse -- that `fire` spawns, and that no
  inline dispatcher has come back.

### The guard it was supposedly justifying is still needed

Easy to conclude the ghost-service pcall can go now. It cannot. The throw
widened in three circles and the dispatcher only closes the third: the rest of
the ghost loop and `replicate(now)` both live INSIDE that one listener, so no
dispatcher can contain them. The measured table (`after 0` unguarded, `after
481` guarded) is kept at the call site because it is why the guard is trusted --
relabelled as history rather than deleted.

### A phantom failure worth the note

`pseudo-signal.spec` passed standalone and failed under `tests/run.luau`. Lune
takes the process exit code from a thread that throws, and the new throwing
listener test leaves the scheduler reporting one after the verdict is printed.
The template harness has exited explicitly for this reason for passes; the
game's hand-rolled spec did not, and paid for it. Now it does.

---

## Pass 33 — 2026-08-29 · a refactor not done, and a draw that was almost right

### The refactor I did not do

`create-new` works now, and the template has 36 `Instance.new` sites while only
`make-display-part` uses the builder. Converting the clean ones looked like the
obvious next move -- a module the tree ships and does not use is exactly the
shape this log has flagged before.

It would have made the tree worse, and one probe said so:

    const part = Instance.new "Part"
    part.Sixe = Vector3.one
    --> luau-lsp: Key 'Sixe' not found in external type 'Part'

`Instance.new "Part"` already returns a typed `Part`, so every write after it is
checked ON THE COMMAND LINE -- where the builder's type function is not checked
at all. Ten conversions would have traded a CI check for a Studio-only one and
added a require per file to do it. The scoping rule is now in the module header
so the next person does not have to rediscover it: property-table builders earn
their place where properties are DATA, not as a general replacement for
straight-line construction.

(One asymmetry worth knowing: `part.Mass = 5` passes luau-lsp silently, while
`create("Part", { Mass = 5 })` is an error, because `prop.write` prunes
read-only properties. Not enough to justify a rewrite.)

Structural debt is genuinely low here, which is the other half of the answer:
the whole tree has three functions of 45+ lines, and one of those is a comment
block a brace-counter miscounted.

### A retry-once draw is not exclusion

`music-player.next_track` picked a track, and if it matched the one playing,
drew once more. The comment defended it as a fair trade -- retry once, never
risk looping on an unlucky draw.

It is a false dilemma, and it repeats a quarter of the time on a two-track
playlist. Drawing from the n-1 OTHERS and stepping over the current one's slot
is exactly uniform, makes a repeat impossible, is O(1), and has no loop to
bound. Both trees had the identical code; both now call
`util/tables/pick-other`.

The move that made it testable was pulling the draw out of the module. It sat
among `playlist`, `dead` and `playing_id`, reachable only through an export that
plays audio -- so it could not be specced where it was, which is why an
almost-right draw survived. As a pure function taking an injectable `Random`
(the convention `util/numbers/weighted-random` already set) it gets 16
assertions, including a distribution check.

Mutation-tested four ways -- `>=` to `>`, the shift removed, the single-element
case returning nil, and `current` ignored entirely. All four caught, 3-5
assertions each, so no single assertion is carrying the spec alone.

---

## Pass 32 — 2026-08-29 · the type function works, and two benchmarks that lied

### What made it work: reading the library that already solved it

vide does exactly this in `roblox_packages/.pesde/centau_vide@0.4.1/vide/src/create.luau`,
and reading it found three bugs that no amount of reasoning had:

- **`types.optional(t)` is the API for "or nil".** Building it by hand as
  `types.unionof(t, types.singleton(nil))` THROWS -- `singleton` takes a string
  or a boolean. A type function that throws poisons every type it produces,
  which is exactly the "every property is `*error-type*`" symptom.
- **`setproperty(key, ...)` takes the key type straight from iteration.**
  Rebuilding it via `types.singleton(name)` was a needless round trip.
- **`Properties` should take the INSTANCE TYPE, not the class name.** The
  name-to-type lookup belongs in the type alias, where the built-in `index` does
  it. That deletes the `:value()` call and with it the whole dependence on the
  solver keeping `"Part"` a singleton inside the type function.

The signature is now vide's shape too: `<Class>(class: Class | keyof<Creatable>,
properties: Properties<Class>?) -> Created<Class>`, ascribed to a plainly-typed
implementation so the body needs no casts. **Confirmed working in Studio.**

Also worth writing down because it wasted a round: `*error-type*` is what
luau-lsp renders for ANY type function. `util/tables/const-record`, which has
worked in Studio for months, produces 13 of them. Seeing it in an editor says
nothing about whether the thing works.

### Two benchmarks that said the opposite of the truth

The `task.defer` on the parent write is gone -- it is written last and
synchronously now. Getting to that took two wrong measurements, and both are
worth keeping:

**Reading the clock before the queue drains measures nothing.** Timing the loop
and stopping said deferral was SIX TIMES FASTER: 1.93us against 13.77us. That is
not work avoided, it is work that has not happened yet -- the 12.9us parent
write still lands, in the same frame. Deferring a sentinel last and yielding
until it fires gives the real answer: **15.56us deferred vs 14.99us synchronous,
so deferral COSTS 3.8%.** Deferring reorders work within a frame; it never
removes it, and it cannot help a frame budget.

**A constant key is a different benchmark from a variable one.** Testing the
extracted C setter with `inst["Size"] = v` said it was 2% *slower* than plain
assignment. That literal index gets Luau's inline cache, which the real loop --
keys from table iteration -- never gets. With a variable key it is 5% faster:
90.4 vs 85.8 ns/write.

That 5% is 23 ns across a five-property instance, against the 12.9us it costs to
parent one. **The setter trick is worth keeping because it is free once resolved
at module load, not because it is fast**, and the comment claiming otherwise has
been replaced with the numbers. Parenting is 90.3% of a create-and-parent call;
nothing else in this module is worth optimising, and per the perf notes the
game's own per-frame Luau is 0.5% of a hitch, so this was the last of it.

The synchronous parent write also deleted a footgun rather than just some time:
`create` now returns a parented instance, so `make-display-part`'s
hold-Parent-back dance -- which existed solely to dodge the deferred write
racing a `Destroy` -- is gone.

---

## Pass 31 — 2026-08-29 · measuring the things two files asserted

Two claims in this tree turned out to be written from memory rather than
measured. Both were load-bearing, and both were wrong.

### The fallback that had never once been taken

`util/instances/create-new` extracts the raw C property setter out of a
traceback, and carried a fallback for the environment where that trick fails.
The comment justifying it said Lune "accepts unknown properties silently, so
`xpcall` succeeds and there is nothing to extract".

Measured, Lune raises on that write exactly like Roblox does, and
`debug.info(2, "f")` hands back a genuine C function -- `debug.info(probed,
"sl")` reports `[C]`, it sets Name/Anchored/Size correctly, and it still
rejects a bogus property name. The fallback branch had never executed anywhere.
It is gone, and the module now calls the setter unconditionally.

Worth separating the two failures, because only one of them is about
performance: the branch cost a comparison per property write, which is real but
small. The larger cost is that the comment made the module *read* as though it
were propping up something fragile, and that reading was false.

### Reflection data, read instead of recalled

The same module's type side maps a property's `ScriptType` to a Luau type. That
mapping was invented, and roughly half wrong in both directions: it listed
`bool`, `int`, `int64`, `float` and `double` (all **EngineType** names --
ScriptType only ever says `boolean` and `number`), invented `Ray` and `Region3`
(no writable property uses either), and omitted `Content` and
`SecurityCapabilities`, which 87 writable properties across 61 classes do use.
The real set is 20 names, now read off a live `ReflectionService` rather than
guessed.

The same read produced two filters worth having. `GetPropertiesOfClass "Part"`
returns **96** entries; only **39** are things you would ever assign. `Permits`
sorts them -- the KEY is the signal, the values are `SecurityCapabilities` --
dropping 14 read-only (`Mass`, `ClassName`, `ExtentsSize`) and 16 with no script
permissions at all. `Display.DeprecationMessage` drops another 27, which permits
alone cannot catch: `archivable`, `brickColor` and `formFactor` are all fully
writable, and reflection hands back outright typos (`shap`, `siz`) as real
properties. `create("Part", { Mass = 5 })` is now an error rather than a silent
no-op.

**What is still unverified, and says so in the file.** Whether any of that
checking actually runs is not something this repo can answer. The Luau RFC that
introduced type functions specifies a fixed allowlist for their sandbox and
excludes host-provided APIs, which would make `game` nil inside one and quietly
route every call to the permissive fallback. `ReflectionService` being reachable
at RUNTIME -- which is where the numbers above came from -- proves nothing about
analysis time, and luau-lsp cannot arbitrate because it does not implement type
functions at all. The module documents the one-line test for anyone in front of
Studio: add `Sixe = 1` to a `create` call and look for a squiggle.

### Follow-up, same day: a correction, and why the question is still open

I recorded here that the reflection version had been "tested in Studio" and
found inert. **That was wrong, and wrong in the way this file exists to catch.**
The report was that types did not work; I treated that as a test result and
wrote it up as settled.

What was actually true: `create-new` **did not exist in Studio at all**. Rojo had
disconnected before the module was written, so `ReplicatedStorage.Util.instances`
had seven children and none of them was this one. `make-display-part` there was
still the old positional version and `prefabs` still called it positionally. The
type function had never been evaluated even once. "It does not check anything"
and "it is not there" produce the identical observation, and I did not
distinguish them before writing a conclusion down.

The design did change, and the new one stands on its own merits: a `Creatable`
name-to-type map with `:properties()` needs no host access, so it is immune to
the sandbox question rather than dependent on the answer. Built-in `index` and
`keyof` replaced a second hand-rolled type function. But the claim that
reflection-in-a-type-function is inert is back to being an INFERENCE from the
RFC's allowlist, not an observation, and it is written that way now.

**The rule this earns:** a user reporting "it does not work" is a symptom, not a
diagnosis, and the cheapest thing to rule out first is whether the code under
test is the code being run. Two tool calls against the live place would have
found it before any of the redesign.

### The docs check could not see most of the references

`tests/docs.spec` only counted a reference if it started at `src/`, `tests/`,
`docs/` or `scripts/`. But the house shorthand is `util/events/step-stats` --
and *every* reference in that form had gone unchecked since the spec was
written. Adding src-relative roots took the count from 109 to 165 here and
turned up genuinely stale pointers in both trees: `docs/models.md` named a
module that does not exist for the very convention it documents, and the game
had eleven, mostly modules that moved into a `common/` or `run/` subdirectory
while their comments stayed put.

Three refinements, each from a specific false positive rather than in
anticipation:

- **One slash is not enough on its own.** "the client/server boundary" is prose.
  The shorthand form now needs a hyphen or a dot in its last segment, or two
  slashes' worth of depth.
- **`%w` excludes underscores in Lua patterns.** The member-stripping rule for
  `module.some_function` silently matched nothing, because most member names are
  snake_case. Caught by a mutation, not by reading it.
- **`.client.luau` and `.server.luau` were never tried**, though `.spec.luau`
  already was for the identical reason. Five of the game's "broken" references
  were correct all along.

Mutation-tested both directions: breaking a `util/` reference in a doc and in a
code comment each fail now and each passed before.

---

## Pass 30 — 2026-08-29 · the reassessment, and what it actually found

Three candidates, all three worth doing, none of them large. Then the loop ends.

### (a) Divergence between the two trees

Eleven differences. Eight are intentional — the game keeps its own fonts, its own
shop funnels, a game-specific status effect, and a carousel wired to its own
sound module, while the template has three modules the game never needed.

**One was a genuine improvement that had not travelled**:
`util/instances/make-display-part`, reworked to named props in pass 25, with the
game still on the positional signature. Six call sites, all in one file, so
converging cost little and buys more than tidiness — the two trees now share the
module, so the next fix to it travels cleanly instead of having to be applied
twice and diverge again.

Both suites green afterwards: 53 in the game, 19 here.

### (b) lessons.md had accumulated rather than been written

Reading it as a document rather than as a list found three rules in the wrong
section — "a hang is not a failure", "a surviving mutation is usually a too-kind
fixture", and "a timing test can pass because the mutation had not happened yet"
had all landed under **Shape** when every one of them is about **writing a
check**.

The cause is worth naming because it will recur: each was appended next to the
*previous* edit rather than next to the content it belongs with. That is what
accumulation looks like from the inside — every individual step is reasonable and
the document drifts anyway. They now sit with the other mutation-testing rules,
which is also where a reader hits them at the moment they need them.

Nothing in it was stale, and all 108 path references still resolve.

### (c) Two headers describing code that had moved on

- `world/markers` still said tagging "keeps the builder passes from each
  importing CollectionService" — untrue since the switch to instance-level tag
  methods, and a reader would have gone looking for an import that is not there.
- `effects/shared/floor` explained its raycast filter in terms of ghost bodies
  and graybox prefabs, in a template that has neither. Reworded to the general
  case, which is the one that survives: a decal placed on the first thing a ray
  hit lands on somebody's head rather than on the ground.

### And that is the end of it

Nothing else is left that is worth doing rather than inventing. The porting
finished at pass 24, the prune at 25 and 28, the four abstractions at 26 and 27,
coverage of everything where a silent wrong answer would hurt at 29, and this
pass closed the drift between the trees and inside the docs.

Further passes would be manufacturing work, which is the one thing this log has
consistently said not to do.

---

## Pass 29 — 2026-08-29 · four specs where a wrong answer is silent, one skipped

Judged five untested modules by "would a wrong answer actually hurt". Four
earned a spec; one did not, and saying which is the point.

- **`make-display-part`** — the four inert flags are the entire reason the
  function exists, and its own header records them drifting once. `CanQuery` is
  the expensive one: a cosmetic part that answers raycasts blocks
  line-of-sight, stops floor probes and catches mouse hits, from something the
  player cannot touch. Nothing raises; an unrelated system just behaves oddly.
- **`replication-focus`** — both failure modes end with a player in a world that
  was never streamed to them, reported once, unreproducibly.
- **`folders`** — three lines, and the failure is a DUPLICATE: half the markers
  in one `Logic` and half in another, every lookup finding some of what it
  wanted. Three lines is exactly why it needs pinning; nobody re-reads three
  lines.
- **`party-gate`** — only the failsafe is reachable (`ready_count` walks
  `Players:GetPlayers()`, which does not exist here), and the failsafe is the
  part whose absence is fatal. Opening late is a bad minute; never opening is a
  dead session.
- **`teleport-guard` — skipped, deliberately.** Its retry logic lives inside a
  `TeleportInitFailed` handler that cannot be fired outside Roblox, and the only
  reachable surface is `strand_deadline`, which is one multiplication. A spec
  covering just that would be a green line about nothing.

Eleven mutations across the four; all caught.

### A mutation that HUNG instead of failing, and what it exposed

Removing the party gate's deadline (`while os.clock() < deadline + 100`) did not
fail the spec — it hung it, past the 60s guard on my own mutation harness, which
aborted the script **before it restored the file**. Caught and restored by hand.

Two things worth keeping from that:

**A hang is not a failure.** The spec asserts "does not hang past its deadline",
and that assertion cannot fire when the thing hangs — the case never reaches it.
Some properties can only be checked by something outside the process.

**And `tests/run.luau` has no per-spec timeout**, because Lune's `process.exec`
blocks and exposes none. So a spec with an accidental infinite loop stops the
suite with nothing on screen saying where. I started to add a "now running…"
line and then removed it: specs run in SORTED order and each prints when it
finishes, so the culprit is already derivable as the one alphabetically after
the last `PASS`. A second row per spec, in output where a carriage return does
not overwrite, was a real cost for information that was already there. The
inference is documented in the runner instead.

**Always restore from the backup before re-running anything**, including after
the harness itself dies. A mutation left in place is worse than one never made.

---

## Pass 28 — 2026-08-29 · an optimisation declined, and the module it made testable

### The hot path I went looking for, and did not take

`shared/world/markers` does three `GetDescendants()` walks — `find_in`,
`require_in`, `all_in` — each allocating an array of every descendant under the
root to find instances carrying one tag. `CollectionService:GetTagged(tag)`
would touch only the tagged ones.

**Not worth doing.** Two reasons, and the second is the one that decided it:

- These are the one-off lookups the module documents as "for the cases that do
  not want a whole scan" — a pad, a status sign. They run at setup, not per
  frame. `scan()` is the bulk path and is already a single walk for many tags.
- Lune does not implement `GetTagged`, so switching would make the module with
  the most lookup logic in the tree **untestable headlessly** — trading a win
  nobody can observe for the ability to check the behaviour at all.

### But looking at it produced a better change

`markers` used `CollectionService:HasTag(instance, tag)`. The instance form,
`instance:HasTag(tag)`, is the same operation — both are in the API — and it
drops a service dependency. It is also the one **Lune implements**, so the
module became testable.

`tests/markers.spec.luau`: 24 cases, all of them about a model authored WRONG,
because that is the case nobody exercises by hand — the models in front of you
are authored right. Mutation-tested three ways: treating a wrong-class tagged
instance as absent, dropping the class assert from `require_of`, and omitting
empty buckets from `scan`. All caught.

One limit written into the spec rather than left implicit: Lune does not
implement `Attachment.WorldCFrame`, so only the BasePart branch of
`require_marker_cf` is exercised. A reader should not have to guess which
branches a green run covered.

### The prune: nothing left worth cutting, and saying so

- **`src/util/ui`** (~20 files) — the library. Zero references there is not dead
  code; the next game uses a different third of it.
- **`src/effects` and its one example** — deleting the example would leave a
  registry with nothing documenting its contract, and deleting the folder takes
  the registry with it. One entry is the minimum that teaches the shape.
- **`item-util`, `controls`, `datastore-template`** — original template code,
  and `item-util` is what `award.luau` is built on.

The real prune already happened in pass 25, and it was not about unused modules
at all: it was about what ran uninvited. Manufacturing further removals now
would be the mirror image of inventing work.

---

## Pass 27 — 2026-08-29 · pathfinding is earned; a behaviour framework is not

### The evidence, before the opinion

The ghost game's nine enemy types **do not use PathfindingService at all**. They
steer — seek, flee, separation, orbit, wander — and move through one guarded
call that clamps then sweeps. The only `ComputeAsync` in the whole tree is in a
Studio-only test bot.

That cut both ways, and it is why reading first mattered:

- **For pathfinding**: the test bot is where every hard-won `PathfindingService`
  rule lives, and there are eleven of them. That is not a thin wrapper.
- **Against a behaviour framework**: a shipped game with nine enemy archetypes
  did not need a state machine or a behaviour tree. Each type is a plain module
  with a `tick`. The framework would have been a thing to understand before it
  could be deleted.

### `util/pathfinding/compute.luau` — four hazards behind a one-liner

`CreatePath():ComputeAsync()` looks like one call and behaves like four:

- **It THROWS** on degenerate input — a NaN target, a start inside geometry,
  coordinates outside the world. In an AI tick, an unguarded call takes out the
  entity's whole brain.
- **Success is a STATUS, not the absence of a throw.** A clean return can still
  be `NoPath`, and `GetWaypoints` on that leads nowhere in particular.
- **A one-waypoint route is not a route** — waypoint 1 is where you already are.
- **`WaypointSpacing` default is far denser than useful.** Measured on one route
  in a live place: `math.huge` → **5** waypoints, default → **13**, `-1` → **419**.

Plus the retry tier: ask for a walk-only route first, and only allow jumping if
there is none. `AgentCanJump = true` produces routes over railings that can drop
an agent somewhere it cannot get back from.

### `util/pathfinding/init.luau` — the four rules nobody remembers

**Throttle the recompute.** Without a minimum interval, an agent that cannot
reach its goal recomputes every tick forever, and failures log — in the game, a
bot shuffling against a wall filled the console and buried everything else. The
throttle is not an optimisation; it is what keeps the log readable.

**Re-anchor a live route periodically.** A route is computed from where you
were; follow it long enough and its waypoints describe a journey you are no
longer on.

**Recompute on goal DRIFT, not goal change.** A chasing agent's target moves
every frame. Treating that as a new goal is the unthrottled case with extra
steps.

**A stuck agent needs a different answer, not another path.** If the route is
fine and the agent is not moving, an identical route changes nothing.

And one that is not about paths at all: **a wandering agent must HOLD its goal.**
Re-rolling a random destination every tick leaves it shuffling, which every stuck
detector correctly reads as stuck — and then answers with the recompute storm
above. That bug looks like a pathfinding bug and is not one.

### Mutation testing caught a too-kind fixture, again

Four mutations; three caught immediately. "Start at waypoint 1 instead of 2"
was not — because the fixture put waypoint 1 exactly under the agent, where the
advance loop skipped it anyway.

The real case is a navmesh SNAP: `ComputeAsync` places the start on the mesh,
which can be several studs from the agent and sometimes *behind* it. With
waypoint 1 moved to -10, starting there walks the agent backwards before setting
off, and the mutation is caught.

Same shape as the sequence spec's timing bug one pass ago: **the fixture was too
kind to the code.** Worth naming as a category — a mutation that survives is
usually a fixture that avoids the interesting case, not a property that does not
matter.

### What could not be tested, said plainly

`PathfindingService` does not exist outside Roblox, so nothing here exercises a
navmesh. The spec covers the decisions — when to recompute, when to advance,
what to do with no route — through an injectable `route` seam that also serves
games with their own navmesh. Of `compute`, only the NaN guard is checkable.

---

## Pass 26 — 2026-08-29 · the sequence layer, and a design bug mutation testing found

### Cutscenes and event sequences are NOT one problem

I said last pass that they were. Reading `cutscene-player` properly showed they
are not, and the distinction decides the design:

- **A timeline** positions clips on an absolute axis and computes from
  `elapsed`. Scrubbing, speed and pause all mean something. `cutscene-player`
  is this, and it is a good one — 5 track kinds, markers, chaining.
- **A sequence** runs step N, then step N+1. Its length is not known in advance
  because a step can wait on a CONDITION rather than a duration.

A timeline cannot express "wait until every player is inside the zone"; a
sequence cannot be scrubbed. So `util/threads/sequence.luau` sits BESIDE the
cutscene player rather than replacing or wrapping it, and both files say which
to reach for — because a single abstraction covering both would do neither
well, and its users would spend their time working out which half they were in.

### What the sequence layer is actually for

Not ordering. This is already fine and is what everyone writes first:

```luau
task.spawn(function()
    open_door(); wait_for_everyone(); close_door(); start_wave()
end)
```

It is fine until the round ends in the middle of it. That coroutine does not
know: it closes a door on a room nobody is in and starts a wave into an empty
level, seconds after the thing it belonged to stopped existing. The module owns
exactly two things — **when a sequence stops, and what undoing it means.**

Cleanups unwind **newest-first**, because later steps are built on earlier ones:
the wave from step 3 has to clear before the arena from step 1 comes down.
Finishing does NOT unwind — `on_cancel` means undo-if-interrupted, not teardown,
or every sequence would undo itself the moment it worked.

### The design bug, and how it surfaced

The first version had `wait` RETURN false on cancellation, documented as "you
rarely need to check". Mutation testing said otherwise: removing the
cancellation check from inside `wait` **broke nothing**, which meant nothing was
relying on it.

Chasing that found the real problem. A step that opens a door, waits, then
closes it will still close it — because ignoring a return value is the default
and nothing forces the check. The safety property the whole module exists for
was resting on the caller remembering.

Waits now RAISE a sentinel, so a cancelled wait aborts the step outright. The
sentinel is a unique table compared by identity, and the xpcall handler passes
it through while building a traceback only for real errors — the other way
round, stringifying and matching on text, would make a step that raised the same
words look like a cancellation.

**"Remember to check the return value" is not a safety property.** It is a hope.

### And the test that passed for the wrong reason

The case written to catch that mutation *also* failed to catch it at first: a 5s
wait, a cancel at 0.15s, a check at 0.45s. With the guard removed, the step was
still inside its wait when the assertion ran, so the flag was unset and the case
passed. Shortened to a 0.4s wait with a 0.8s settle, it catches it.

The general form is worth keeping: **a timing test can pass because the thing
you are disproving has not happened yet.** Make the observation window outlast
it.

### One mutation deliberately not chased

Removing the post-loop cancellation check in `wait` is not caught. That guard
only matters when the deadline expires in the same instant as cancellation — a
race the loop check already covers. Contorting a test to pin a redundant guard
would buy a green line and no safety.

---

## Pass 25 — 2026-08-29 · refactor: two builders, one 23-function module, and what runs uninvited

### The display-part thing

There were **two part builders**. `make-display-part` took `(size, color,
material)` positionally — fine for three properties and useless for anything
else — so a second one grew inside the effects folder to add a CFrame, a
transparency, a shape and a parent. A general-purpose part builder living where
its first caller happened to be, differing from the real one only in how many
properties it could express.

One builder now, taking named props, with `extra` for anything unnamed so no
caller has to reach past it to a raw `Instance.new`. The floor module keeps the
single job its name claims.

The four inert flags are why the function exists at all rather than being
inlined: they get copy-pasted as a block and then one copy drifts. That already
happened once — a Neon disc lying flat on the floor kept `CastShadow` on, which
is not a look anybody chose. `CanQuery` off is the load-bearing one: a cosmetic
part that answers raycasts blocks line-of-sight checks and catches mouse hits
from something the player cannot touch.

### One module doing four jobs

`model-layout` was 23 functions, and its own export table already separated them
into groups with blank lines — folders, tag scanning, single-tag lookup,
authoring. Split into `world/folders` and `world/markers` along the seams it was
drawing for itself. **No re-export shim**: indirection is the thing being
objected to, and a module that exists only to forward is one more file to read
before finding the code.

### The prune, and what it actually turned up

The instinct is to hunt unused modules. That list is 68 entries and almost all
of it is `src/util`, which is a library — zero references there is not dead
code, it is a toolbox the next game uses a different third of.

The useful question was different: **what runs without being asked?** Seven
scripts did. Two of them were `setup-ragdolls`, client and server, which impose
`BreakJointsOnDeath = false`, register collision groups, put every character
part in a group, and hand corpse ownership back on death. That is a design
decision — a good default for some games, wrong for others — and a template that
makes it has to be undone by every project that wanted something else. Both are
now modules with `start()`, documented as needing each other (start one without
the other and death is a body that freezes upright).

Five scripts run now: boot, the two halves of the sync handshake, and the data
lifecycle. Those are the ones a game is broken without.

### And a real bug in the boot it exposed

`init.client` mounted the UI immediately. `wait-for-loaded` existed, unused,
for exactly this — so every screen rendered once from nil before data arrived: a
currency counter showing 0, an inventory showing empty, both correcting a beat
later. Nearly invisible in Studio, where data and character land instantly. Now
wired in, which fixes the boot and justifies the module in the same edit.

### camera-attach: asked whether it was needed, and it mostly was not

It ran in every project, watchdogging a race that only exists if you turn off
`CharacterAutoLoads` or swap cameras. Opt-in now — and making it one surfaced
that **it yielded at require time**, waiting on `LocalPlayer` at module scope.
That is the hazard `party-gate` documents from the other side: a module that
yields on require is how a boot sequence loses the handler it was about to
connect. The wait lives inside `start()`.

---

## Pass 24 — 2026-08-29 · the hitch watchdog, and the end of the porting

`src/client/debug/frame-watch.luau`, generalised: a pluggable context callback instead
of the game's entity counting and state reads.

### Why a watchdog when a profiler exists

A profiler tells you what a frame costs while you are watching it. This tells
you what was on screen during a hitch that happened to **somebody else**, on a
connection you do not have, in a situation you cannot reproduce. In the game
this came from, the client's Luau was profiled end to end and no path cost more
than ~2ms in a frame — heartbeat clean, heap flat, allocation ~9 KB/s — and the
stutters players reported did not reproduce in Studio at all, because a
backgrounded Studio window throttles to a hard 15fps and masks everything.

### The attribution is the whole point

`step=` comes from `util/events/step-stats`, which times the dispatch of the
shared step signals. A fraction of the frame means the game's own per-frame Luau
is **not** the cause and optimising it will not help — look at rendering,
streaming or the network. Most of the frame means a listener on a shared step
signal is the culprit. Without that number, "a 300ms frame happened in level 3"
is another round of guessing.

### A tension in the brief, resolved by splitting rather than picking

The instruction was to gate this on `records/debug-flags`; the module's own
reasoning is that it must be always on, "because a diagnostic you have to
remember to enable is not there on the frame you needed it". Both are right
about different halves:

- **detection is always on** — one clock read and one compare per frame, and the
  entire point is to be present when the unreproducible thing finally happens;
- **the periodic digest is behind the flag** — that one is for somebody actively
  looking, and a live player does not need a console line every two minutes.

Worth asking of any diagnostic: would you rather have it running for everyone,
or have it be quiet? The answer differs for "something just went wrong" and
"here is a periodic summary", and gating both the same way gets one of them
wrong.

### The porting is done

Two candidates were left and both were declined after reading them:

- **a solid-prop part builder** — five lines of defaults-plus-overrides, with a
  wood material baked in. The template already has `make-display-part` for the
  non-collidable case, and a default material is a game's choice.
- **footsteps** — the mechanism generalises (per-character positional steps off
  Humanoid state, cadence scaling from one reference speed, no network), but the
  module without a sound table is inert, and the template ships no sounds. Its
  transferable knowledge — positional audio wants `RollOffMinDistance`, the 2D
  versus 3D rule — is already in `src/client/audio/play-sound.luau` and lessons.md.

Everything still in the game is the game: level generation, enemy AI, combat,
the elevator feature, the HUD, tuning records, art direction. Porting any of it
would produce modules a new project has to understand before it can delete them,
which is worse than an empty folder.

---

## Pass 23 — 2026-08-29 · testing the thing that does the testing

`tests/harness.spec.luau`. Twelve specs trust the harness to be right, and this
exercise keeps finding bugs in checking infrastructure rather than in the code
being checked — a decorative RNG seed, an LCG with no low-bit entropy, a matcher
that saw everything, a matcher that saw nothing, an assertion that was never
true. That is five, against roughly the same number found in the tree itself.

### The circularity had to be broken, not managed

A spec that tested `h.check` by calling `h.check` reports clean if `check` is
broken to always pass. So this file counts and prints for itself and uses the
harness only as the subject.

That leaves `check`, `saw` and `done` untested here, and the honest answer is
that they are covered by something stronger than a test: **every spec in this
suite has been mutation-tested, and every one went red on its mutation.** A
`check` that could not fail would have made all of those pass. Direct evidence
beats a test that would have to be written in the same language as the thing it
doubts.

### What is tested is the part with logic in it

The stripper, the brace matcher, the key reader, the require extractor, the
walker. Each of those returning a subtly wrong answer produces a silently weaker
check somewhere else — which is the failure this whole suite is shaped against.

All five mutation-tested, and each named exactly the right case:

| mutation | caught by |
| --- | --- |
| stop blanking string bodies | 3 cases, naming each quote style |
| collapse the line structure | the line-count case (`got 1, want 5`) |
| brace matcher stops at the first `}` | "spans past a nested close brace" |
| `top_keys` ignores nesting depth | `got 5 keys, want 2` |
| the naive `[^)]*` require matcher | "crosses an inner paren" |

The last one is the specific bug this suite has hit before: that matcher cannot
cross the paren in a `game:GetService("X")` call, so it silently skips exactly
the files written in the inline style — and a scan that misses a file is
indistinguishable from one that passes it.

### Line structure is a contract, not an implementation detail

Worth stating because it is easy to lose in a refactor: several scans report a
line number, and a stripper that collapsed lines would make every one of them
point at the wrong place. That is worse than no line number, because it is
confidently wrong.

### Not done

The frame-hitch watchdog. It needs real generalisation work — the game's version
is wired to that game's atoms and counts its own entities — and rushing it into
the template at the end of a pass would produce exactly the kind of module that
has to be understood before it can be deleted.

---

## Pass 22 — 2026-08-29 · the last client modules

Read all six of the game's remaining client modules and ported four. The other
two are art direction — a light-flicker wobble and a hitch watchdog wired to
that game's own atoms — and a template is worth less with them in it, because
they have to be understood before they can be deleted.

### `lighting-fx` — tag first, parent second

Any reconciler that morphs Lighting's children toward a mood treats an
unexpected child as one to fade out and destroy. So a ColorCorrectionEffect a
script parents in by hand is destroyed the first time the mood changes, and the
script that made it goes on writing properties to a dead instance.

The ordering is the part worth having: **tag as ignored, then parent.** The
reconciler yields between children, so a parent-then-tag ordering leaves a
genuine window where an in-flight reconcile can see the effect. One function, so
the tag cannot be forgotten.

### `mouse-unlock` — the Modal trick, and the cursor nobody remembers

An invisible full-screen `TextButton` with `Modal = true` and `Active = false`
unlocks the cursor while enabled. Refcounted, because several UIs want it at
once.

The part that is not in any tutorial: under `LockFirstPerson` the cursor is
pinned to the middle of the screen, on top of the crosshair, where it can click
nothing. A UI that unlocks the mouse and draws no usable cursor is worse than no
unlock at all, so `MouseIconEnabled` follows the unlock — and is driven off the
`CameraMode` signal as well, since whatever locks the camera may boot after this
module is first required.

### `strip-character-sounds` — ported as opt-in

The engine's CoreScript builds Running, Jumping, Landing and the rest under
every HumanoidRootPart, a beat after the character arrives. The moment a game
ships its own footsteps, the stock loop is a second system playing out of phase
on a recording of a different floor.

Made a module with an `init()` rather than a script that runs itself: a template
that silenced the default footsteps on boot and shipped no replacement would
just be a quiet game.

Removal is **by name**. A blanket sweep of Sounds under the root part eats your
own positional audio, which is parented exactly there.

### `camera-attach` — for anyone who turns off `CharacterAutoLoads`

A character spawned before the client's camera scripts are up misses the
engine's own `CameraSubject` bind, and the camera is left floating where it
started. Routine as soon as spawning is manual.

### One real diagnostic, in both repos

`holders[key] = if open then true else nil` against a `{ [string]: true }` table
— nil-to-remove is the whole idiom, and the narrow type makes it an error on the
way in. Widened to `boolean` in the template and the game; both suites green
afterwards.

---

## Pass 21 — 2026-08-29 · verifying instead of adding

Built the template the way a new project would, and made the ad-hoc checks
durable as `tests/project.spec.luau`.

### What held

`rokit install`, `pesde install`, `rojo build` (not just `sourcemap` — the build
is the real test), `scripts/analyze.sh`, and all eleven specs. Every mount in
`default.project.json` resolves, and no file under `src/` sits outside one.

### A hypothesis that was wrong, checked rather than asserted

Two directories are empty — `src/replicated-first` and `src/shared/selectors` —
and **git cannot track an empty directory**, so neither survives a clone. Since
`ReplicatedFirst` is a mount target, the obvious conclusion is that a fresh
clone fails to build.

It does not. Renaming a mount's directory away and building anyway produced a
place file, minus that branch, exit 0. So the real failure mode is milder and
worse-shaped: **a mount pointing at nothing builds successfully and silently
omits a subsystem.**

Which is the whole reason to run the experiment rather than reason about it. The
wrong version of this entry would have said "fresh clones are broken", sent
somebody looking for a build error that does not exist, and missed the actual
property — that Rojo will never tell you a mount is dead.

`.gitkeep` added to `src/replicated-first` so the mount survives a clone.
`src/shared/selectors` is empty, unmounted, and unreferenced; it evaporates on
the next clone and nothing will miss it.

### `tests/project.spec.luau`

Asks the question nothing else in the suite asks. Everything else starts from
the mounts and reasons about files; this starts from the files:

- **no mount pointing at nothing** — builds fine, subsystem absent at runtime;
- **no file under `src/` outside every mount** — it typechecks, passes every
  source scan, and is not in the game. `loads.spec` cannot see it either,
  because that maps files THROUGH the mounts.

Mutation-tested both directions: renaming the effects mount to a path that does
not exist fails both checks (and usefully names the four files it orphans), and
a file dropped into an unmounted directory fails the second.

(Naming those two invented paths in backticks failed `docs.spec` — the fifth
time this session. At this point the pattern is not an anecdote: writing about a
path is not pointing at one, and the check is right to be strict, because the
version that let prose through would let a real stale link through too.)

### Docs brought back in line

The README's layout table said "Server scripts and modules" for a directory that
now holds thirteen of them. It lists what is actually there now, plus the
`scripts/` row it never had.

### Not done: committing

Nothing from any of these twenty-one passes is committed — 31 new files, 34
modified, one rename, all in the working tree. A fresh clone gets none of it.
That is the user's call to make, not mine.

---

## Pass 20 — 2026-08-29 · orchestration patterns, not orchestration

`src/server/players/party-gate.luau` and `src/server/players/replication-focus.luau`. The game's
run orchestrator is 1,300 lines and almost all of it is that game; two patterns
inside it are not.

### The party gate, and the rule that makes it work

Hold everyone at the start until the whole party has loaded. Three rules, and
only one of them is obvious:

- **A timeout is not optional.** The gate opening late is a bad minute; the gate
  never opening is a dead session for everybody.
- **`expected` is a callback, not a number.** Party size usually arrives with
  teleport data rather than being known at boot, and reading it per poll means a
  player who leaves shrinks the target instead of stranding it above anything
  reachable.
- **Nothing before the handler connect may yield.** This is the one that bites,
  and it is invisible.

That last one is worth stating in full because it is a whole class. sendbufs has
no queue, and a "ready" signal is fired ONCE per client with no retry. So if
anything in the setup ahead of that connect gives up its scheduler slice — a
`task.wait`, a `WaitForChild`, an async call — a client that finished loading
during the gap fires into nothing. The gate then holds the ENTIRE party on that
player for the full timeout: no error, nothing in the console, no failing test.
Just four people watching a status sign.

The defences are ordering plus a spec that enforces the ordering. `wait_for_party`
returns whether it opened because everyone arrived, so a rising
opened-on-timeout rate is visible — which is the difference between finding this
class in telemetry and finding it in a bug report that says "the game was stuck".

### `ReplicationFocus` has two traps and both strand a player in an empty world

- **`nil` does not mean "stream nothing".** It hands the choice back to Roblox,
  which falls back to the player's own character — which is what you want, and
  is exactly why clearing the field by hand looks fine. The problem is the path
  you forget: one route out of spectating that misses it leaves the focus parked
  on a teammate, and that player revives into a room streaming in late around
  their own feet. Routing every path through one function is what makes "did we
  clear it?" a question with an answer.
- **A focus that misses its part never retries.** Set it while the target is
  between characters — the window between "alive" and `LoadCharacter` returning
  is real and easy to land in — and there is no root part yet. Nothing
  re-attempts, so the watcher rides a camera through a world that never streams
  in.

And one worth forbidding outright: a focus left pointing at a part you are about
to destroy. Drop watchers before tearing down what they watch.

### Not ported

Revive, the run state machine, room generation, the ghost sim. Those are the
game, not a template — a downed/revive state machine that assumes a specific
notion of "downed" is worth less than nothing to the next project, because it
has to be understood before it can be deleted.

### The docs check caught a cross-repo reference for the fourth time

`party-gate`'s comment cited the game's init-no-yield spec by path. It exists —
in the other repo. Same rule as pass 14: a backticked path points into *this*
tree, and cross-repo references are prose. Four for four now; that check has
paid for itself several times over on a class I would not have thought worth
automating.

---

## Pass 19 — 2026-08-29 · the client modules worth generalising

`src/client/audio/music-player.luau`, `wait-for-loaded.luau`, `local-character.luau`.
Picked out of the game's client-common folder because they carry rules rather
than game logic; the rest (footsteps, atmosphere, camera rigs) are content.

### `music-player` — four rules, each from a symptom

A crossfading one-track-at-a-time player, taking a plain array of ids. It is a
module with a `set` rather than something that watches state, because what "the
situation" means differs per place and per game — each place ships a thin driver
deciding WHICH playlist, and they share this.

The rules, in the order they bite:

- **Setting the same playlist twice is a no-op.** Drivers re-run on every state
  change and almost none of those change the music. Without this, moving through
  a level restarts the track at every doorway.
- **A track that survives into the new playlist keeps playing**, so a driver
  recomputing an equivalent list does not restart what is already going.
- **A finished track prefers not to draw itself again** — one retry, which makes
  a two-track list mostly alternate without ever being able to loop.
- **A track that never LOADS is dropped and the next one starts.** This is the
  one that would otherwise be silent and permanent: `Sound.Ended` never fires
  for an asset that failed to load, so one delisted id ends the score for the
  rest of the session and leaks the Sound waiting on it. `IsLoaded` after a
  generous timeout is the only thing that separates "streaming slowly" from
  "never going to play", because the second raises no event at all.

Two smaller ones worth keeping: a **generation counter** bumped on every `set`,
so a superseded fade-in cannot write a volume behind the track that should be
playing; and `Debris:AddItem` rather than `task.delay` for the fade-out, so a
client leaving mid-fade does not leave a Sound parented forever.

### Nothing broken this pass, and one near-miss

Both `wait-for-loaded` and `local-character` ported unchanged. The port did
leave one stale type reference — `music.Playlist` after the record require was
dropped — which `scripts/analyze.sh` named immediately. Worth noting only
because it is the workflow behaving as designed: a leftover reference to a
deleted import is `Unknown type`, one line, and the counts baseline is what
makes one line visible.

---

## Pass 18 — 2026-08-29 · what this log should be

Seventeen passes, 1,233 lines, 65 subsections. As a record that is fine. As
something to *look something up in* it is the wrong shape: answering "what
should I watch for when writing a source-scanning check?" meant reading all
seventeen entries, because the material is organised by when it was found rather
than by when it is needed.

So the durable half is lifted into [lessons.md](lessons.md), organised into four
sections — writing a check, what fails silently in Roblox, what fails silently in
this toolchain, and shape. This file stays as the chronological record and keeps
the evidence: the measurements, the counts, the wrong turns. That division
matters more than it looks. A rule with its evidence attached is believable; the
same rule alone is just an opinion, and the first time it is inconvenient
somebody will decide it does not apply to them.

### What the log turned out to be about

Reading it end to end, one thing accounts for most of it, across passes that
looked unrelated at the time:

> **The failures that cost real time are the ones that look like success.**

Not the crash — a crash announces itself and gets fixed the same hour. The check
that examined nothing. The module nobody ever ran. The attribute that
replicated. The teleport that returned cleanly and arrived nowhere. The preload
that spent half a second and cached nothing. Every one of them presents as a
green light.

And the sharpest version, which took until pass 17 to say plainly: **the thing
that checks is as capable of being wrong as the thing being checked, and it
fails more quietly, because its failure looks like good news.** Several of the
bugs found in this exercise were in the test infrastructure — a decorative seed,
an RNG with no low-bit entropy, a matcher that saw everything, a matcher that
saw nothing, an assertion that was never true.

### Not done, and why

The README's dialect section stays in the README rather than becoming a separate
conventions document. It answers a question a reader has in their first thirty
seconds — "why does this say `const`?" — and a fourth document is a worse place
for that than the file they are already looking at. The README is 81 lines; it
is not overfull, and splitting it would trade a real benefit for a tidier
directory listing.

(That paragraph named the file it was declining to create, in backticks, and
`docs.spec` failed it — the third time this session that documenting a decision
tripped the check enforcing it. Three for three is no longer a coincidence; it
is the rule from lessons.md doing its job.)

---

## Pass 17 — 2026-08-29 · the distribution, and a broken random number generator

`tests/weighted-random.spec.luau`. The alias method is clever and its failure
mode is that **it still returns plausible values** — get the small/large stack
juggling slightly wrong and there is no error and no nil, just a loot table that
is quietly 15% off forever, in a direction nobody notices until someone counts.
Nothing else in the toolchain has an opinion about a distribution, so the test
is empirical: sample 60,000 times and compare.

Mutation-tested against two one-character bugs:

| mutation | result |
| --- | --- |
| halve one `prob` entry | shares move to 5 / 15 / 80 against 10 / 30 / 60 |
| `exponent = luck` instead of `1 / luck` | all three luck-direction cases fail |

The second is the one worth having. Inverting that exponent produces a working,
plausible distribution that makes *luck do the opposite of what every call site
believes*, and no test of "does it return a valid key" would ever notice.

### The spec's first run found a bug in the spec's own RNG

Four equally-weighted entries, sixty thousand samples, and **two of the four got
zero**. That reads as a badly built alias table. It was a badly built random
number generator: the fake was `state % 4`, and a linear congruential
generator's LOW bits have a period as short as 2 — so `% 4` cycled through two
values forever and never emitted the others.

Taking the high bits fixes it. The same bug was in `tests/roblox-env`'s `Random`
shim, so it is fixed in both, with the reasoning written down in each.

### And the shim's seed was decorative

While wiring this up: `roblox-env`'s `Random.new(seed)` stored the seed in a
field nothing read and answered from the global `math.random`. So
`Random.new(42)` looked deterministic and was not — the exact shape of a spec
that passes until the day it does not, with nothing to point at when it fails.
It is a real seeded generator now.

Both of those were in test infrastructure rather than in the tree under test,
which is the recurring shape of this whole exercise: **the thing that checks is
as capable of being wrong as the thing being checked, and it fails more quietly,
because its failure looks like good news.**

### On the tolerance

2 points of slack at 60k samples. Sampling error alone is ~0.2pt; the rest is
the LCG's structure, which lands about a point off on this table. It is
deterministic so it cannot flake, but the budget is sized so a later innocuous
change cannot creep over it either — and it is still far tighter than what it
guards against, since a mis-built alias table moves a share by tens of points.

---

## Pass 16 — 2026-08-29 · behaviour specs for the two bugs that were real

`tests/signals.spec.luau` and `tests/tween.spec.luau`. Both modules are pure
logic, both had bugs that shipped, and neither had a single test.

### What they pin

**pseudo-signal** — a listener that connects mid-dispatch runs on the NEXT fire,
not the one that created it; a listener disconnected mid-dispatch is called at
most once; re-entrant fires nest without shredding the outer walk; and the
signal still works after a listener throws.

**tween** — replacing a tween does not repaint the outgoing tween's start value;
explicit `:cancel()` still does, exactly once, with the start value; cancelling
a handle to an already-replaced tween is a no-op; instances are independent.

Both were mutation-tested by **restoring the original bug**, which is the only
version of that test worth running:

| mutation | result |
| --- | --- |
| `previous:cancel()` on replace | 3 cases fail, naming the repaint |
| dispatch off the live listener set | 2 cases fail, naming the mid-dispatch connect |

### The first draft of a spec asserted something that was never true

`fire_sync` runs listeners bare — that is the documented trade for not paying a
thread per listener per frame — so a throwing listener aborts the rest of THAT
dispatch. My first case asserted the other listener still ran, and it failed
deterministically, because table order put the thrower first.

The code was right and the spec was wrong, which is worth flagging as its own
failure mode: a red test is not evidence of a bug, it is evidence of a
disagreement, and the first question is which side is confused. The case now
asserts what actually matters — that the signal is not *permanently* broken,
which is the property the reusable scratch buffer exists to guarantee.

### And one duplicate, caught by looking before mirroring

`signals.spec.luau` was mirrored into the game, where a `pseudo-signal.spec`
already existed covering the same ground — mid-dispatch connect, re-entrancy,
throw survival, all of it. I had written a second implementation of a spec that
was already there.

Removed from the game, kept in the template. The lesson is small and repeats:
**check what the other repo already has before mirroring into it.** The mirror
rule is about fixes travelling, not about making the two trees identical.

---

## Pass 15 — 2026-08-29 · auditing the baseline found two more real bugs

The job was "check the known-benign table against a fresh baseline". The table
was mostly right. The **twelve files it did not mention** were the point, and two
of them were broken.

### `util/ui/hooks/use-tween` was written against an API that does not exist

It called `Ripple.createTween(...)` and used `Ripple.Tween`, `Ripple.TweenOptions`
and `Ripple.Animatable`. Ripple 0.6 exports `createMotion`, `config`,
`immediate`, `linear`, `spring` and `tween` — none of those. The module could
not have run.

Everything about it was quiet:

- a missing table key is `nil`, not a type error;
- it was a **byte-for-byte duplicate of `use-motion`**, same internal function
  name and all, with one call changed — so it read as obviously fine;
- it had **no callers**, so it never ran;
- luau-lsp did say `Key 'createTween' not found in table` — once, in a baseline
  of hundreds of lines.

It is the same class as the `vide.for_values` bug from pass 1, and
`tests/package-api.spec.luau` was written in pass 13 specifically to catch it —
but that check reads a package's real export table, which requires loading the
package, and **ripple cannot be loaded headlessly**. So the bug sat in the one
blind spot that spec declares by name. Which is the argument for declaring blind
spots explicitly: this one was findable because the list of what is not covered
was written down.

Reworked into something distinct from `use-motion` rather than deleted: a motion
pre-wired to the tween solver, with `to(goal, params)`.

### `change-lighting` had the weak-Instance-table bug too

`did_fade_out` was `setmetatable({}, { __mode = "k" })` keyed by Instance — the
same class that froze corpses upright in `util/ragdolls`, where a weak entry for
a live, parented instance is dropped on the first GC cycle (measured: 0 of 40
survived).

It has not bitten because **nothing reads the table**. It is written and never
consulted — a half-finished idea. Kept, with strong keys, precisely because a
write-only weak table is a trap for whoever wires up the read: they will find a
flag that is sometimes missing for no reason they can see.

### The table now covers the whole baseline

Twenty-eight files, every one accounted for — including the rows that say "this
is a bare `function` defined lower in the file, verified by the precise test, not
assumed". `tests/docs.spec.luau` checks all 86 paths in it resolve, so the table
cannot rot into naming files that have moved.

**"Delta clean" means no NEW diagnostics, never no defects.** Two audits of this
directory have now each produced two real bugs while every diagnostic around
them was noise.

---

## Pass 14 — 2026-08-29 · consolidation, made mechanical

The task was "read the log and fix what has drifted". Reading it by hand would
have worked once. `tests/docs.spec.luau` works every time.

### Docs go stale by MOVING, and nothing errors

Pass 11 moved six files out of `src/shared` into `services/` and `world/`, and
three references in this very log kept naming the old paths. Nothing complains.
The reader follows a precise-looking pointer, finds nothing, and now distrusts
the parts of the document that are still true — which is worse than the document
not existing.

The new spec checks every path referenced in `docs/`, `README.md` and **code
comments**. Found the three stale ones here immediately, and two in the game
(its asset checklist pointed at product and badge records that had been
removed from that tree).

### Its own false positives were the interesting part

Three rounds of them, and each one is a rule:

- **Quoted tool output looked like a path.** `` `src/rel/path.luau(98,10): LintName: ...` ``
  in docs/testing.md is an example of a diagnostic FORMAT, printed to show what
  to filter on. Fixed by requiring a candidate to contain no whitespace.
- **Three of five hits in the game were the house shorthand.** A comment naming
  a spec without its `.spec.luau` suffix is a pointer, not a mistake. Reporting
  those as broken is 60% noise, and a check that cries wolf gets deleted —
  taking the two real findings with it.
- **Correcting a doc tripped the check.** Writing "the record
  shared/records/products was removed" makes the checker flag a path that is
  *deliberately* gone. This is the path-shaped twin of the rule already in
  docs/testing.md: the more precisely you document something, the more certainly
  you trip the check enforcing it.

  Written here without backticks, because a bare path in prose is not a pointer
  — and I know that because **this paragraph failed the check when I first wrote
  it**, in the same commit that documented the trap. Twice, in fact: the second
  round was this log citing paths that exist in the GAME and not in this tree.
  That is the invariant the check actually enforces, and it is a good one: a
  backticked path points into *this* repo. Cross-repo references are prose.

Mutation-tested in both forms — a broken markdown link and a broken bare path in
a code comment. The second **was missed on the first attempt**, because comment
paths are usually not backticked; that gap is exactly what the mutation test was
for, and it is closed.

### A spec that printed `0 failed` and exited 1

`loads.spec` requires every module, which RUNS them, and a module that spawns a
thread at require time keeps running after the last assertion. One of those met
a stubbed service and threw — `attempt to compare table <= number` — long after
the verdict was printed. Lune took the process's exit code from that.

So the runner reported FAILED while the spec's own summary said every case
passed. A verdict contradicting itself is worse than either answer alone,
because the reader has to work out which half to believe.

`harness.done()` now exits explicitly on success as well as failure, so the
printed summary is authoritative and a late background throw cannot overrule it.
The throw still lands on stderr where a human can see it. And the runner no
longer reprints `0 failed` summary lines as if they were failures.

### One regression, caught by the thing that exists to catch it

Mirroring the template's `loads.spec` over the game's dropped the game's
documented `EXPECTED_ENGINE_FAILURES` entry for its boot-relocated client
bundle, and the game's suite went red on the next run. Restored. Worth noting
because it is the argument for running the suite after every mirror rather than
assuming a copy is safe: the two repos' specs are the same code with different
declared exceptions, and the exceptions are the part that does not travel.

---

## Pass 13 — 2026-08-29 · UI templates, and checking a package's real API

Ported `util/ui/templates/shadow.luau` and `viewport.luau`. Skipped the
game-styled ones (`chalk-frame`, `chalk-smear`, `panel-depth`) — they depend on
uploaded textures and commit to one art direction, which is not a template's
business. The one generic thing inside `panel-depth` was lifted out.

### Capability probes must probe what you actually write

`UIShadow` is a recent class, so a template that builds one unconditionally
breaks on older clients. The obvious probe checks the class:

```luau
pcall(function() vide.create "UIShadow" {} end)
```

which succeeds on a client where the class exists but the property VALUE is
rejected — and `BlurRadius` is a **UDim**, not a number, which is exactly the
mistake such a client would reject. So the probe reports "supported" and the
real call still throws. Worse, this is built inside a vide tree, so that throw
does not fail one shadow: it takes the whole mount down, and the screen it was
decorating with it.

The probe now sets the properties the function actually writes, and the function
returns nil when unsupported (vide skips a nil child), so the failure mode is no
shadow rather than no screen.

### `tests/package-api.spec.luau`

The carousel bug from pass 1 was `vide.for_values` — a function that does not
exist in vide 0.4 (it is `vide.values`). Nothing caught it:

- a table read is not a type error, it is `nil`;
- luau-lsp said `Key 'for_values' not found in table 'vide'`, one line among
  hundreds, in a file that also had four dead requires;
- `requires.spec` proves the require RESOLVES, which it did;
- `loads.spec` cannot load a module whose package needs the engine.

So it shipped and would have failed the first time a carousel rendered — which
never happened, because the module had four other reasons not to load.

The new spec is **exact rather than textual**: it requires the package through
`roblox-env` and reads its real export table, so there is no list to keep in
sync and a package that changes its API in an update fails on the next run.
Mutation-tested: reintroducing `vide.for_values` fails it, control clean. Run
against the game: **298 member reads verified.**

### The scan had to learn the difference between a type and a value

First run flagged `charm.Getter`, `charm.Cleanup` and `vide.Source` as missing
members. All three are exported TYPES, which do not exist as runtime keys — the
scan was right that they are not on the table and wrong about what that means.

Opening the hits rather than trusting the list is what caught it, and the fix
took three tells rather than one:

- followed by `<` → generic type arguments
- immediately preceded by `:` → an annotation or return type
- **PascalCase and not a runtime key** → almost certainly a type, because every
  value export in these packages is lowerCamel

The third exists because `(fx: () -> ...charm.Cleanup?)` puts the colon four
tokens back and has no `<`. Its cost is that a genuinely missing PascalCase
*value* would be classified away — so the count of type-classified reads is
PRINTED. A heuristic with a number on screen is auditable; the same heuristic
silent is just a hole.

---

## Pass 12 — 2026-08-29 · the effects registry

Ported `src/effects` — `init.luau`, `effect-types.luau`, `src/effects/shared/floor.luau`, a
README, one example entry — plus a generalized `tests/effects.spec.luau`.

### What the registry is actually for

One-shot visual moments, one file each, spawned by name. The thing it owns is
**lifetime**, and that is the part worth having:

```luau
effects.new("common/aura", { target = model }, { color = ... })
```

binds the effect's life to `model`. Three things can end it — the effect calling
`cleanup()`, the caller calling it, or **a bound instance being destroyed** —
whichever happens first wins, the rest are no-ops, and the teardown runs exactly
once. Before that, every one-shot hand-rolled its own bookkeeping, and the
bookkeeping is where the leaks were.

Two details in the machinery that read as fussy and are not:

- The effect body is **spawned, not called**. An effect that throws must not take
  its caller down (a broken telegraph should not cancel the attack), and one
  that yields must not stall the frame. `task.spawn` still runs the body up to
  its first yield immediately, so a telegraph is on screen *this* frame — which
  for a windup is the whole point.
- An effect that **throws must still be torn down**, via `xpcall` then re-raise
  rather than `pcall`. Without it the entry stays `is_running` forever and the
  only symptom is a long-run warning 60 seconds later pointing at an effect that
  is not running — a worse signal than the error, arriving a minute late and
  describing the wrong problem.

### The folder is the list, and that has exactly two holes

An effect exists because its file exists — no table to keep in sync. The cost is
symmetrical: a misspelled name resolves to nothing, and a file nobody spawns
looks alive because it sits in the folder next to the live ones.
`effect-types.luau` generates a type union from the folder shape, but **luau-lsp
cannot evaluate user-defined type functions**, so that check runs in Studio and
not on the command line — and a union that degraded to `string` would look
identical. The spec closes both directions against the real folder.

**The entry count is pinned exactly, not bounded.** A `>= 20` bound was
mutation-tested on the original and stayed green while three effects were
deleted one at a time. A bound is only a check outside its own slack.

### The spec's own scanner failed loudly first

My first matcher was `%.new%s*%(?%s*"([^"]+)"`, which found 35 "call sites" —
`Instance.new "Part"`, `BrickColor.new "Bright orange"`, `Instance.new "Sound"`
and twenty others, with the real ones buried among them.

Worth naming as the twin of the usual failure: **a scan can fail by seeing
nothing, and it can fail by seeing everything.** The second is louder and no
more useful — and it is more dangerous in one specific way, because the fix that
suggests itself is to add exclusions until the noise stops, which is how a
matcher quietly stops matching the real thing too.

It now resolves the registry's local alias per file
(`const effects = require(ReplicatedStorage.Effects)`) and matches only calls on
that name. Validated where it counts: run against the game, **10 entries, 13
call sites in 1 file, both directions clean, zero false positives.**

### And it says when it checked nothing

The template has no call sites yet, so both directional checks are inert. The
spec prints that rather than printing two green lines that examined nothing —
the same "could not check it is not the same as it is fine" split that
`requires.spec` makes.

---

## Pass 11 — 2026-08-29 · shape and switches

Four changes asked for directly, and one bug they turned up.

### `src/shared` split by concern

```
shared/
  network.luau          the wire
  place-context.luau    which place am I
  services/             alert, appearance, player-data, sync-registry
  world/                model-layout, character-exclusion
  records/  datastore/  item-util/  controls/
```

Eight files' worth of requires rewritten; `tests/requires.spec` is what made
that safe to do in one pass rather than one file at a time.

### One canonical instance id

`player-data` built its sync key by hand as `.PLAYER_DATA/{user_id}` while
`status-effect-handler` keyed the same players through
`util/instances/get-instance-id`. Two systems naming the same player differently
is a bug that only shows up when something tries to correlate them, so
`player-data` now goes through `get_instance_id` too. It is pure for a Player
(`?plr@<UserId>`, no attribute write), so it is safe on the client, where
minting an id would be a local-only write that never replicates and never gets
corrected.

### Debug drawing is a runtime switch, not a build-time one

`util/debug/gizmos` was gated on `RunService:IsStudio()`, decided once at
require time. That answers the wrong question in both directions: true in every
Studio session including the ones where you do not want the screen full of
wireframes, and false in the live server where the reproduction actually is.

It now reads `records/debug-flags`, an attribute on ReplicatedStorage:

```luau
game:GetService("ReplicatedStorage"):SetAttribute("DebugDraw", true)
```

Attributes there replicate server → client, so one write turns tooling on for
everyone; a client can also set it locally for itself, and that write simply
never leaves the machine. Neither needs a remote.

The gate is a single `queue()` choke point that all seventeen public methods
already funnelled through, so a new `Draw*` cannot forget it and there is
nothing to keep in sync. Off, it costs one attribute read.

### The `__index` stand-in had to go; the class metatable did not

Outside Studio the module returned `setmetatable({}, { __index = noop })`. That
stand-in answered **every** key with a function, so `gizmos.Clear = false`, a
typo, or a method that does not exist all silently succeeded — "drawing is off"
and "you called something that is not there" were the same thing. It now returns
the real table either way.

`Trailer`'s metatable stays. It is an ordinary class with real methods, not a
stand-in that swallows unknown keys, and the two are not the same problem. (I
converted it to closures first, on a reading of "no metatables" that was wider
than what was asked; reverted.)

### Every method checks, not just the queue

The tempting version gates the single `queue()` that all the draw calls funnel
through. That is shorter and it is **wrong in at least one place**: `AddToPath`
creates and appends to a Trailer *before* it queues anything, so with only the
queue guarded those trails would keep growing — forever, in production, for
drawing nobody can see. The guard is at the top of each of the eighteen public
methods, so a method's own side effects are covered and not just the draw call
at the end of it.

`Update` clears the queue when the flag is off too — otherwise anything queued
in the frame it was switched off would sit there and draw all at once when it
came back.

### The rework immediately produced the bug the docs describe

Placing `queue` above `local commands = {}` made it read `commands` as a
**global** — nil at runtime, so the first draw would have thrown
`table.insert(nil, ...)`. `scripts/analyze.sh` reported the exact pair
docs/testing.md names as the tell:

```
UnknownGlobal: Unknown global 'commands'
LocalShadow: Variable 'commands' shadows a global variable used at line 52
```

Same identifier in both, which is what separates a real stranded reference from
the ordinary noise of this dialect. Fixed by moving `queue` below the locals it
reads — and it is worth noting that the specs did **not** catch this: the module
loads fine, because the failure needs a draw call. The typecheck did.

### `make-display-part` now says what it is not for

Spawning a Part to see where a ray landed is the most common reason that helper
gets called, and it is the wrong tool: gizmos covers rays, casts, bounds,
CFrames and text, and clears itself every frame, so there is no instance to
name, parent, track or destroy. The boundary is in the header, because it
decides which you want: **gizmos is developer-only** (it draws nothing when the
flag is off), and `make-display-part` is for geometry a **player** sees.

---

## Pass 10 — 2026-08-29 · reading the util code, not its diagnostics

The last audit of `src/util` found two real bugs while every one of its ~400
diagnostics was noise. So this pass read the code. Two more real bugs, and both
were in files whose diagnostics were unremarkable.

### `util/ragdolls` stored per-Instance state in a WEAK table

```luau
const storage = setmetatable({}, { __mode = "k" }) :: { [Model]: RagdollObject }
```

The assumption is that a live, parented rig keeps its own entry alive. **In
Roblox that assumption is false.** An Instance's Lua-side wrapper is collectable
whenever nothing on the Lua side holds it strongly, whatever the DataModel
thinks. Measured in Studio: 40 parts created and left parented, referenced only
from a weak table — **0 of 40 entries survived**, and the state was
unrecoverable even by looking the same instance up again.

What that cost is worth spelling out, because the symptom pointed elsewhere:
`init_ragdoll` runs once at spawn, and that table is the only place the rig's
sockets, welds and saved collision groups live. A GC cycle later the entry was
gone, so the death that followed found `is_ragdolled()` answering false and
`set_ragdoll()` bailing with "ragdoll not init" — **the body froze upright**.
Dying seconds after spawning worked; dying a room later did not.

Fixed with strong keys plus a `Destroying:Once` release, which is the right
moment anyway: a character model is destroyed on respawn and on leave.

The full ported module also brings the collision-group setup (corpses do not
pile on each other, and the living walk through them) and a `sync_ragdoll` pass,
because **a character's rig is not fixed at spawn** — the appearance load
replaces the Head a few hundred ms in, destroying the Neck Motor6D and the
socket built on it. Without the re-sync every corpse's neck stayed rigid.

The two `setup-ragdolls` scripts came with it. The client one previously
connected `StateChanged` and **returned nothing** from the observer callback, so
that connection was never disconnected — one leaked per character, forever. It
also cast a timed-out `WaitForChild` to a non-optional type, so a character torn
down mid-spawn threw out of an observer factory that nothing pcalls.

### `util/game/on-shutdown` never fired on the server

It listened for `Players.PlayerRemoving` and compared against
`Players.LocalPlayer` — which is **nil on a server**, so the comparison was
never true and every callback registered server-side was silently dropped. A
module named `on-shutdown` that does not fire on the realm with the shutdown.
No error, no warning, just work that never happened.

Now: `game:BindToClose` on the server, `PlayerRemoving` on the client. And
because `BindToClose` is **a budget, not a notification** — the engine waits
roughly 30 seconds and then kills the server — callbacks run in parallel under a
20-second deadline, so one hung saver cannot hold the server open until the
engine force-closes it mid-write.

Nothing in either repo calls it yet, which is exactly why it was broken: an
untested utility is a utility nobody has found the bug in.

### Cleared, after reading

- `cutscene-player`'s three `Unknown global` diagnostics — `play`, `stop` and
  `set_speed` are all bare `function` declarations, i.e. per-script globals, so
  a call above the definition resolves. Benign by the precise test in
  docs/testing.md, which the `gizmos.drawCube` case proved is worth applying
  rather than assuming.
- `bezier`, `generate-id`, `color-gradient`, `shared-ctor`, `map-table`,
  `filter-table`, `observe-character`, `lerp-cieluv` — all generic-variance,
  narrowing or `return nil`-as-iterator-stop noise. Read, not assumed.

---

## Pass 9 — 2026-08-29 · the toolchain, and a mistake worth recording

Added `scripts/analyze.sh`, `docs/testing.md`, a real README, and `luau-lsp` to
`rokit.toml`.

### I reported "luau-lsp clean" several times against an empty stream

**luau-lsp writes its diagnostics to STDERR.** Every check I ran in passes 4-8
looked like `... 2>/dev/null | grep -E "<the files I touched>"`, which greps
nothing and prints nothing, and I read that silence as "no diagnostics".

Run properly, two of those files did carry findings — an unused
`game:GetService "Players"` left behind in `teleport-guard`, and a loop variable
in `preload` shadowing the module's own exported `start`. Neither changes
behaviour; both are now fixed. The wrong part was the claim, not the code.

The shape is worth more than the specific bug, and it is the same one this
repo's own specs are built to resist: **a check that examines nothing reports
clean**, and clean is exactly what you were hoping for, so nothing about it
invites a second look. I wrote the paragraph warning about this class in
`docs/testing.md` in the same session I fell into it.

`scripts/analyze.sh` now captures stderr, and asserts the analyzer printed its
startup line before believing an empty result — so "it did not run" fails loudly
instead of reading as "no problems".

### The toolchain was lore, and lore does not survive

`luau-lsp` was not in `rokit.toml`, so `~/.rokit/bin/luau-lsp` failed and every
typecheck had to go through a hand-written path into rokit's tool storage,
pinned to a version number somebody had to remember. The definitions file is not
in the repo and has to be fetched. The two `--ignore` flags are not optional:
without them the package tree drowns the real output, and without `--defs` every
Roblox type is unknown.

That is four ways to run a typecheck that *looks* like it worked. It is a script
now, and `luau-lsp` is pinned in `rokit.toml` in both repos.

### `--counts` is the mode that earns its keep

Per-file diagnostic counts, sorted by path so `diff` lines up. A raw dump of
several hundred lines hides one new diagnostic completely; a file going 0 → 1 in
a delta is instant, and that is what a deletion taking a live consumer with it
looks like. Total count alone is useless — a util diagnostic is re-reported once
per requiring path, so an unrelated new `require` moves it.

Baseline established: 31 files with diagnostics here, 60 in the game.

---

## Pass 8 — 2026-08-29 · anticheat

Added `src/server/anticheat/` (a movement/cadence watch plus its pure timing
maths) and `tests/anticheat-heuristics.spec.luau`.

### The `forgive()` contract is the whole thing

Blink detection asks "did this character move further in one sample than
movement allows?" — which is exactly what a **server-initiated** teleport looks
like. Spawn, respawn, an out-of-bounds rescue, a checkpoint, a cutscene, a debug
jump: every one of them must call `forgive(player)` to re-anchor, or the
anticheat kicks players for something **the server did to them**.

There is no way to detect a missing call from inside the module. The only
discipline that works is to grep every place that writes a character's CFrame
and check each one, which is why it is stated at the top of the file rather than
left to be discovered.

### Two false-positive classes that took real tuning

Both were found by players falling in holes, not by tests:

- **Blink must be measured on the HORIZONTAL jump.** The full 3D magnitude
  counts free-fall: an out-of-bounds drop passes a 120-stud threshold after
  about 1.1s of falling, and a rescue loop polling at 1Hz forgives it too late.
  An unlucky phase cost two strikes for falling in a hole.
- **The threshold must scale with the sample's real `dt`.** `dt` from a step
  signal is *accumulated* time, not the nominal interval — a backgrounded Studio
  server ticks at roughly 19% duty, so a nominal 0.5s sample arrives as ~2.6s,
  where a perfectly legal 45 studs/s covers 117 of a flat 120-stud budget.

Neither costs detection that matters: teleport hacks are horizontal and far past
the floor.

### The speed limit tracks `Humanoid.WalkSpeed`, not a constant

That one decision removes a whole category of future bug. Every legitimate speed
change the game makes — a slow effect, a buff, a catch-up boost, a debug command
— stays inside the limit **by construction**, instead of needing a new exception
each time somebody adds one and forgets.

### Never attribute suspicion onto a Player

An earlier version set an `AnticheatSuspect` attribute. **Attributes replicate**
— to every client, including the suspected one. Nothing read it, so its entire
effect was to hand a cheater the one fact worth hiding: how many strikes they
have and how many remain before a kick. Back off, wait out the decay, resume. It
broadcast the accusation to everyone else in the server too. Suspicion stays in
a server-side table.

### The spec lesson: read the config, do not restate it

The spec that exercises the metronome detector originally copied the thresholds
into itself under a comment saying "same config as anticheat.luau". That spec
keeps passing after somebody loosens the real threshold — it proves the numbers
it made up are consistent with themselves and says nothing about the program.

Both this template's spec and the game's now parse the config out of the source,
with a blindness guard on the parse. **Verified by mutation**: loosening
`max_cv` from 0.02 to 0.2 now fails the three human-behaviour cases in both
repos, and did not before.

This is also the first spec here to load its module through `tests/roblox-env`
rather than extracting text — possible because the timing maths lives in its own
Roblox-free module. Worth copying as a habit: anything whose correctness is
arithmetic belongs in a module that touches no engine API.

---

## Pass 7 — 2026-08-29 · model layout and tag lookup

Added the model-layout module (since split into `src/shared/world/folders.luau` and `src/shared/world/markers.luau`), `src/shared/world/character-exclusion.luau` and
`docs/models.md`.

### The cast is the bug

The habit these replace is one line:

```luau
const bounds = model:FindFirstChild "Bounds" :: BasePart
```

`FindFirstChild` returns `Instance?`. The `:: BasePart` **asserts the nil away
without checking anything**, so a model missing its marker does not fail at the
lookup. It fails a page later, on whatever first indexes the nil — `attempt to
index nil with CFrame` — possibly inside a build running under `fatal.guard`,
taking the server with it. The error names the wrong file, and the stack points
at the consumer rather than at the model that was authored wrong.

`require_*` fails **at the lookup**, naming the model, the tag, and the class it
expected. `optional_*` returns nil and means it, so the caller's type says so
and the analyzer forces the handling.

Related, and the same shape: a tagged instance of the **wrong class** is a bug,
not an absence. Silently treating a Model tagged for a BasePart as "not there"
hides a mis-tag until something downstream misbehaves for an unrelated-looking
reason.

### Names break silently; tags do not break

A tag survives reparenting the marker into a folder, renaming it in Studio, and
an author hand-building a model to the same contract. A name survives none of
those, and none of them raise an error — the marker is simply not found. Tag
names themselves live in `records/tags` rather than as string literals, because
a literal in two files is a contract nothing checks: server writes
`FlickerLight`, client scans for `FlickerLights`, no error, no warning, feature
quietly dead.

### One walk, not six

`scan(root, wanted)` does a single `GetDescendants` pass bucketed by tag.
Resolving a room wants half a dozen markers out of a few hundred instances, and
six separate lookups each allocate a fresh array of all of them.
`HasTag` in the inner loop beats `GetTags`, which allocates per descendant.

### Shared raycast filters

`character-exclusion` keeps ONE list of player characters for every
`RaycastParams` that must treat characters as "not terrain". Three systems in
the game it came from had grown identical copies, each running its own
`observe_players`/`observe_character` tree — three lifecycle subscriptions
rebuilding the same table on every spawn and death.

Two details that are load-bearing:

- **It sets `FilterType` for the caller.** An Exclude list on an Include filter
  is the one way to get this exactly backwards, and the symptom is a probe that
  collides with nothing but people — which reads as a physics problem rather
  than a one-word mistake.
- **It rebuilds on character lifecycle, not per ray.** *Assigning*
  `FilterDescendantsInstances` makes the engine rebuild the whole exclusion set
  whether or not anything in it changed, and the set only actually changes when
  somebody spawns or dies.

---

## Pass 6 — 2026-08-29 · remote hardening

Added `src/server/net/validate.luau`, `tests/wire-fields.spec.luau` and
`docs/network.md`.

### sendbufs has no queue, and that cuts both ways

**An event fired before its handler is connected is discarded, silently.** No
buffering, no retry.

As a hazard, that makes anything fired exactly once a coin flip against boot
order. A place script that creates the remotes and then *yields* — requires a
service and builds a level, probes a DataStore — leaves its own handlers
unconnected for exactly the frames a client needs to talk to it. The symptom is
a client that waits forever with nothing in the console. So: connect every
handler before anything that can yield, and make a handshake that matters
**retry until something proves the other side heard**.

As a defence, it is the cleanest way to make a debug wire unreachable in
production — declare the event, connect the handler only under
`if RunService:IsStudio()`. Any client can *fire* a remote; with no listener the
fire is a no-op. But that makes the security property an **ordering** one, and
ordering is exactly what a refactor breaks without looking like it broke
anything: move the connect above the guard and the wire goes live in production
while every test passes, the types check, and the diff reads like tidying.

### Handlers are hostile input, and `assert` is the wrong tool

sendbufs guarantees payload **shape** — a buffer schema cannot decode into the
wrong types. It guarantees nothing about **values** or **rates**.

Reject **silently**. Not `assert`, not `warn`. An assert on a remote handler is
a client-triggerable server error: free log spam, and an exception thrown out of
a shared dispatch costs whatever was scheduled after it on that frame.

And check NaN and infinity explicitly. `typeof(n) == "number"` is true for both,
and NaN poisons every comparison it touches — `n > max` and `n < min` are *both*
false — so a range check written the obvious way passes it straight through.

### The rate-limit boundary bites in both directions

`validate.limiter` is a **tumbling** window, not a sliding one. It was labelled
"sliding" for a while, which promises a stricter guarantee than it gives:

- **Attacker side:** `max_count` at the end of one window and `max_count` at the
  start of the next means the real worst case is **2x max_count** in a short
  span. Size limits against that.
- **Legitimate side:** a client sending at exactly the cap **loses sends** to
  the boundary, because its cadence and the window edge drift against each
  other. A sender that must not be throttled needs headroom *under* the cap.

The second direction is the one that surprises people, and it is why a "send at
the limit" design quietly drops traffic that was never abusive.

### Dead wire fields

`tests/wire-fields.spec.luau` asserts every field declared in a struct is read
somewhere. A field nothing reads is not an error, not a warning and not a type
failure — it is serialised, sent and discarded, forever, on every packet, for
the life of the server. It is also how a removed feature leaves a tail: the
reader goes, the writer and the schema stay.

Two things the port had to get right, both found by mutation:

- **The corpus must include `/util`.** The house rule is "do not *edit* `/util`",
  which is not the same as never *reading* it. Excluding it reported the entire
  analytics funnel as dead, because both its sender and its handler live there.
  The wire was fine; the scan had removed the consumer from its own corpus.
- **A single-line struct puts its later fields after a COMMA.** A
  newline-anchored field pattern sees only the first one, so a second field
  added on one line is invisible. Mutation-tested in both forms.

The parser also normalises the two spellings of a declaration
(`sendbufs.event(sendbufs.schema.struct` and the aliased `event(s.struct`)
before matching. Handling only one is a scan that silently checks half the wire.

---

## Pass 5 — 2026-08-29 · appearance, audio buses, preloading

### `src/shared/services/appearance.luau`

Anything that builds a rig, a viewmodel arm, or a portrait from a player's
avatar needs their `HumanoidDescription`, and asking the engine for it directly
is a trap in three ways:

- **There is a blank-default window.** Right after a spawn, the engine hands out
  a placeholder description with no body parts, clothing or colours before the
  real one applies. Snapshot inside that window and every consumer is dressed as
  the grey default for the rest of the session. This filters it by comparing
  against a freshly constructed `HumanoidDescription`.
- **`GetAppliedDescription` throws** while the engine is still applying — which
  is exactly the window above.
- **The character can be replaced mid-wait** (death, `LoadCharacter`), so a
  snapshot taken off the outgoing body overwrites the new one's.

One place asks the engine so nothing else has to, appearance changes arrive on a
signal (`DescendantAdded` catches every description that lands, without polling),
and `get_appearance_async` has a FINITE timeout — callers treat nil as "no
appearance this session" and fall back, which an unbounded wait would turn into
a permanent hang on an offline Studio run.

### `src/client/audio/sound-groups.luau` + `src/client/audio/play-sound.luau`

Without buses, every sound in the game is on one fader: music sits at whatever
volume each track was mastered at, ambience sits under it at whatever it was
recorded at, and the only way to make a chime audible over both is to keep
pushing the chime up. Grouping makes "duck the music" or a settings slider a
property write instead of a sweep of every call site.

`play-sound` is fire-and-forget 2D playback, and the sweep is the whole reason
it wants to be one function. Three things learned the hard way:

- **`Ended` never fires for an asset that failed to load**, so without a sweep a
  bad id leaks a Sound per play.
- **The obvious sweep — a flat `task.delay(4, ...)` — truncates every long cue.**
  Sound length is a tail: nine of twenty-one 2D cues in one live session ran past
  4s. Each lost its decay mid-air, which reads as the audio glitching rather than
  as a timer.
- **`TimeLength` is the tell, and the only one.** `IsPlaying` looks like the
  natural question and is not: measured against a deliberately dead id, a Sound
  that will never load reports `Playing = true` AND `IsPlaying = true`
  indefinitely, identically to one mid-playback. What it cannot fake is a
  duration. And divide by `PlaybackSpeed` — `TimeLength` is the ASSET's length,
  so a cue at 0.5 speed runs twice that. That last part was the *second* fix to
  the same bug: keying off `TimeLength` removed the flat cap and left a
  speed-dependent one behind it, which looked like a fix and was half of one.

### `src/client/boot/preload.luau`

A Sound whose asset is not resident does not play when you call `:Play()` — it
starts streaming and plays whenever it arrives.

**The measured finding worth the whole module: unparented preload probes are a
no-op.** The obvious implementation creates probe Sounds, passes them to
`PreloadAsync`, and destroys them immediately, reasoning that the global content
cache is what matters. In a running session:

- unparented probes → `PreloadAsync` yields ~0.5s, probes report unloaded, and
  fresh Sounds on those ids 100ms later are **still** unloaded, identical to a
  never-preloaded control. It spent the time and bought nothing.
- parented probes → fresh Sounds on those ids resolve immediately; the control
  does not.

The **control group** is what makes that measurement mean anything: reading
`IsLoaded` off the probe only proves the property does not populate, and a warmed
cache with a broken readback looks the same. Testing an id nothing has touched
separates them. Silently doing nothing *slowly* is the hardest kind of broken to
notice — it looks exactly like working.

Also carried over: chunk with a yield between (one `PreloadAsync` of a hundred
ids is a single uninterruptible stall, and chunking is what makes a progress bar
move); pcall each chunk (one delisted id makes the call throw); publish the
total before warming anything (so a loading screen has a real denominator from
its first frame); and **whatever happens, the gate opens** — a broken preload
must degrade to streaming on demand, never to a loading screen that will not
open. The plan splits punctual sounds from `heavy_sounds` so a mid-bar skip
still leaves the player everything that has to land on cue.

---

## Pass 4 — 2026-08-29 · boot and multi-place

All opt-in. A single-place game pays nothing for any of it being present.

### What is here now

- **`src/server/boot/fatal.luau`**, and `init.server` now boots inside it. The
  default behaviour is worse than it looks: if the datastore fails to start, the
  boot script dies and **every other server script carries on regardless** —
  players in a live session whose progress cannot be saved, with nothing on
  screen to say so. `fatal` logs the crash as an `error` (so it reaches the
  Creator Hub error report with its traceback) and empties the server.
- **`src/shared/records/place-ids.luau`** + **`src/shared/place-context.luau`**.
  One build is published to every place, so nothing in a script's contents can
  say where it is — `game.PlaceId` is the only runtime truth. Unmatched ids fall
  back to `main` rather than failing, so an unpublished place, a fresh `.rbxlx`
  and a single-place game all work unconfigured; it warns once outside Studio
  when there *was* something to match and nothing did.
- **`src/server/players/teleport-guard.luau`** — retry and recovery for cross-place
  teleports.
- **`docs/multi-place.md`** — the client-bundle relocation pattern, and what it
  costs.

### The three things that actually cost time

**`TeleportAsync` returning cleanly does not mean anybody arrived.** The failure
lands afterwards, asynchronously, as `TeleportService.TeleportInitFailed`. With
nothing listening, the player ends up strictly worse off than never having left:
their save session was released *before* the teleport (that is what lets the
destination load it), so their data is gone from this server; whatever launched
them has already reset itself, so the next tick starts the same failing
departure again; and nothing has told them anything. In the game this came from,
the run side grew this listener and the lobby side — the side that starts every
session — went months without it.

**Retry with the SAME `TeleportOptions`.** A reserved server is addressed by the
access code inside them. Fresh options on a retry send that player to a *public*
server: they arrive somewhere real, alone, the party splits, and no error is
raised anywhere. (Related, and worth knowing: keep the options **per player**,
not one module-level copy. Two departures can be in flight at once, and a retry
that fires against a superseded one drags a player back out of the departure
that worked.)

**A `RunContext = Client` script cannot run or replicate from ServerStorage.**
Which is exactly where both client bundles have to live in a multi-place build,
so the one matching this place is renamed into `ReplicatedStorage.PlaceClient`
during server boot. It works, and the price is that those requires cannot be
resolved by anything static: luau-lsp reports `Unknown require` for every one of
them *and* silently degrades anything read through them to an error-type, so
those field accesses stop being type-checked at all. That is a blind spot, not
noise. `tests/requires.spec` declares the prefix in `IGNORED_PREFIXES` so the
skip is stated rather than silent.

### Not done, deliberately

The game's two teleport paths still have their own hand-rolled copies of this
loop. Refactoring a shipped game's working departure code onto the new module is
a real change with real risk, and nobody asked for it — the module is here for
the next game, and the game's own copies are noted as duplicates rather than
quietly rewritten.

---

## Pass 3 — 2026-08-29 · loading real modules in a spec

### The headline

Lune cannot require a Roblox module — no DataModel, no `game:GetService`, and
the tree the requires index into is a build artifact. So every spec that wanted
to exercise real code pulled a function out of the file with a regex and
`luau.load`-ed the text:

```luau
local body = source:match("\nfunction hold_clearance%f[%W].-\nend\n")
local chunk = ("local Vector3 = ...\n%s\nreturn hold_clearance"):format(body)
```

That works, and it is miserable. The extraction breaks when the function moves
or gains a helper; every constant it reads has to be re-parsed out of the file
by hand; and when the regex stops matching, the spec does not fail — it passes,
having tested nothing.

### What is here now

**`tests/roblox-env.luau`** loads a real `src/` module under a stubbed engine:

```luau
local env = require "./roblox-env"
local tags = env.load "ReplicatedStorage.Shared.records.tags"
local data = env.load("ReplicatedStorage.Shared.player-data", { realm = "client" })
```

It rewrites the three constructs Roblox's Luau accepts and Lune's rejects
(`const` at statement position — only there, because `local const = require(...)`
is a variable legitimately named `const`; `f<<T>>()` explicit type arguments;
`@native`), resolves Rojo mounts, pesde link files, wally `"$path": "src"`
manifests and Lune `@self` requires, and stubs the services.

**`tests/loads.spec.luau`** requires every module in `src/`, in both realms, and
fails if any throws. **92 of 111 load in this template; 182 of 228 in the game
it came from.** The rest are blocked by third-party packages that need the
engine — and blocked is not the same as passing: the spec names the package,
and a module that fails for any *other* reason is a failure.

This is the check that catches the three worst require-time classes: a record
key renamed out from under a module-scope read, a `local function` called above
its own declaration (nil at runtime, and luau-lsp cannot tell it apart from a
benign forward reference), and a package API that does not exist under that name
— `vide.for_values`, in this very tree.

### Four things the build taught, all the same lesson

Every one of these produced a *wrong answer that looked like a right one*:

- **A stub is not free of behaviour.** `Players:GetPlayers()` returned a
  callable stub, and Luau's generic `for` treats a callable as the iterator
  function — so the loop ran with a nil player and failed on
  `player.CharacterAdded`. An error about the loader, reported against the
  module under test. Fixed with `__iter`.
- **A real service is *stricter* than a stub.** Making Workspace a real Lune
  instance fixed parenting and immediately broke a module using `BulkMoveTo`,
  which Lune's Workspace does not have. Real services now earn their place only
  where the alternative is a parenting failure.
- **`FindFirstChild` must be allowed to return nil.** Handing back a node
  unconditionally made a lookup for an instance that does not exist look like a
  hit, and the caller then failed on `tag:IsA(...)`. It now resolves against
  what is actually on disk.
- **`IsStudio()` answers true**, because it is true. A module asserting on
  production-only configuration (`place_ids.run ~= 0`) is behaving correctly;
  answering false failed it for a reason that had nothing to do with its code.

And the mutation test on this spec **missed both mutations on the first run** —
the anchor string was `local SYNC_AFTER` where the file says `const SYNC_AFTER`,
so nothing was ever mutated and "not caught" was really "not tried". Verify the
mutation LANDED (`!=` the backup) before believing a mutation-test result. With
that fixed, both classes are caught and the restored control is clean.

---

## Pass 2 — 2026-08-29 · the test story

### The headline

The ghost game grew **45 specs, ~15,600 lines**, and there was no way to run
them except one at a time by hand: `lune run tests/<name>.spec.luau`, forty-five
times, remembering which ones exist. There was also no shared scaffolding, so
every spec carried its own copy-pasted `check`, `strip`, `walk` and brace
matcher — forty-five chances to get one of them subtly wrong, and the ones that
went wrong reported **clean**, which is indistinguishable from passing.

### What is here now

- **`tests/harness.luau`** — assertions, source walking, a comment/string
  stripper, a brace-matched table reader, and a balanced-paren `require`
  extractor. Plus `saw()`, which is the important one: an assertion that a scan
  actually *found* what it was looking for.
- **`tests/run.luau`** — runs every spec, one process each so a spec that throws
  or hangs cannot take the suite with it, reprints only the failing lines at the
  end, and exits non-zero. `lune run tests/run` or `lune run tests/run <filter>`.
- **`tests/requires.spec.luau`** — resolves every require in `src/` against the
  mounts in `default.project.json`. This is the check that would have caught
  four of the five dead modules from pass 1, in 45ms.

### Two things this pass proved about writing these checks

**A scan that silently checks nothing reports a pass.** The first working
version of `requires.spec` said `68 checked, 87 skipped, all fine`. The 87 were
not skipped for any good reason: the harness's `strip()` blanks string bodies
(so a spec cannot be tripped by its own documentation), and every hyphenated
module in the tree is required as `tables["extend-object"]` — the module name
lives *inside* a string. Blanked, that becomes `tables[""]`, which resolves to
the directory and reports OK. The real number was **155**. Both halves were
wrong in the direction of green.

The habit that catches it: make the scan **print what it checked**, and check
that number against one you can estimate independently. `saw()` exists to make
that a failing assertion rather than a line of output nobody reads. Its floor is
set near the real count for the same reason — a floor of "at least one" would
have passed the broken version.

**"Could not check it" needs splitting.** The spec now separates a *computed*
require (`require(child)` in a folder-walking loader — honestly uncheckable)
from a **static path that matches no mount**, which is not unknown at all: it is
exactly what a require copied in from another codebase looks like. Lumping them
together under "skipped" is what let five dead modules ship at once. Anything
genuinely unresolvable goes in `IGNORED_PREFIXES` with a comment saying why.

Mutation-tested both ways before being believed: breaking a dotted path and
breaking a bracketed one each fail the spec, and the restored control passes.

### Run against the game it came from

871 requires resolved, 1 computed, 36 explicitly ignored (a multi-place build
relocates its client bundle at boot, so no static check can see those).

---

## Pass 1 — 2026-08-29 · after shipping the ghost-catching game

### The headline

`src/util` is the template's toolbox, and reading it end to end turned up **ten
outright bugs and five modules that could not even be required**. None of them
were caught by stylua, by luau-lsp, or by a spec — they were all found the slow
way, by something misbehaving in a playtest and being traced back.

Four modules threw at their first line, so the failure landed on whoever first
reached for them rather than on whoever shipped them.

### Modules that could not load

| Module | What was wrong |
| --- | --- |
| `util/ui/templates/carousel` | Required `ReplicatedStorage.Client.ui.traits.*` and `Shared.util.sound` — paths that exist in no project built from this template. Also called `vide.for_values`, which is not a function in vide 0.4 (it is `vide.values`), and passed it a plain array where it wants a source. Three independent breakages in one file. |
| `util/ui/hooks/use-motion`, `use-tween` | Required `Packages.ripple`, which was not in `pesde.toml`. `carousel` depends on `use-motion`, so the UI templates were a chain of dead modules. |
| `util/ui/hooks/use-product-price` | Required `Packages.promise`; the package is published as `typed-promise`. |
| `util/extra-features/change-lighting` | Required `Shared.constants`, which no project has. |
| `util/analytics/__analytics_funnels` | Required `Client.network` / `Server.network` (the real names are `client-network` / `server-network`), **and** fired `network.analytics.log_funnel`, an event `shared/network.luau` never declared. |

**Fixed:** every require now resolves; `ripple` is a declared dependency;
`carousel` takes its click cue as an injected `OnClickSound` callback instead of
reaching for a game's sound module; `network.luau` declares the `analytics`
group the analytics util has always assumed.

### Silent runtime bugs

- **`util/instances/use-attribute`** watched `GetPropertyChangedSignal(k)` for
  an *attribute*. That signal never fires for one, so the hook read the value
  once at bind time and then never updated. → `GetAttributeChangedSignal`.
- **`util/numbers/synced-time`** started its "last synced" stamp at `0`, and the
  refresh gate compares against `os.clock()` (process uptime). For a server's
  first six seconds it therefore returned *uptime*, then jumped ~1.7e9 on the
  first call after. Any pair of timestamps straddling that jump compares
  nonsensically, and nothing errors.
- **`util/tween`** *cancelled* a running tween when a new one replaced it, and
  cancel repaints the property at alpha 0 — i.e. to the **outgoing** tween's
  start value, one frame before the replacement's first frame. Every re-tween
  of one instance flashed backwards. Invisible when the endpoints are constants;
  very visible when the start value is captured (a progress bar re-tweened on
  each damage tick jumps back up). → replace, don't cancel; explicit `:cancel()`
  still reverts for callers that want it.
- **`util/events/pseudo-signal`** iterated the listener set with `next` while
  dispatching. A listener that connects during dispatch — routine for per-frame
  effects that spawn more effects — mutates a table mid-traversal, which in Lua
  can skip listeners or throw `invalid key to 'next'`. → snapshot into a reused
  buffer first.
- **`util/debug/gizmos`** called `drawCube` from `drawPath` above its
  `local function drawCube` declaration, so that call compiled as a global read
  and was nil: `drawPath(points, closed, dotsSize)` threw for any
  `dotsSize > 0`. → forward-declare. (Worth knowing as a *class*: a `local`
  is not in scope above its own declaration, but a bare `function name()` is a
  per-script global and resolves fine. luau-lsp reports both identically.)
- **`util/ui/hooks/px`** wrote a vide source from inside a vide effect
  (recursive graph update — vide 0.4 has no deferred effects), and hooked
  `workspace.CurrentCamera` once. The camera instance is *replaced* on
  respawn, so UI scaling silently stopped responding to window resizes after
  the first death. → compute outside the graph, re-hook on camera swap.
- **`util/ui/hooks/use-atom`** wrote the vide source from inside charm's flush
  via `task.spawn` (which resumes immediately), nesting graph evaluation inside
  the flush. → `task.defer`.
- **`util/extra-features/status-effect-handler`** read `effect.max_stacks` where
  `effect` was the string key, not the record; never published on change (it
  deep-copied and replicated the whole table every slow step regardless); and
  compared `container.last_update > 10` — an absolute timestamp against a
  duration — so empty containers were never swept.
- **`util/analytics/__analytics_funnels`** `assert`ed on a remote handler. A
  client can fire that event as fast as it likes, so the asserts were
  client-triggerable server errors. → rate-limited, silent rejection, and the
  session id is checked for alphabet as well as length.

### Infrastructure that every game has to build, so the template should ship it

- **The charm-sync handshake did not work.** `sync.server` never called
  `addSignalsToClient`, so no atom ever replicated; it also called
  `charm_sync.server:removeClient()` with no player. `sync.client` did
  `task.wait(1)` and then connected — but sendbufs has **no queue**, so an
  event that arrives before its handler exists is dropped in silence.
  → Added `shared/services/sync-registry.luau` (feature modules `register` an atom;
  the server hands a joining client every registered atom at once, and
  `register_for_player` covers private per-player state), plus a real
  handshake: the client asks and keeps asking until a payload proves the
  server heard, and the server coalesces requests inside its cooldown instead
  of dropping them. Dropping the second request was what stranded clients:
  a module that registers an atom *after* the first ask triggers a re-request
  within a frame or two, and charm-sync only ever sends `init` for a key once.
- **Saved data never reached the client, and nothing loaded or unloaded it.**
  The datastore module built a lyra store and stopped there.
  → Added `shared/services/player-data.luau` (per-player atom, private to that player)
  and `server/data/data-lifecycle.server.luau` (load, unload, `BindToClose`, and an
  honest kick if a load fails — playing on unloaded data means nothing saves).
- **Studio without API access kicked everyone.** Every DataStore call 403s
  there, so with the lifecycle above, no one could play offline.
  → The store probes API access once in Studio and falls back to lyra's mock.
- **The schema callback crashed on success.** `e:formatErr()` where `e` is nil
  when the match *succeeds*.

### New utils worth having

`util/events/step-stats` (attribute a frame hitch to the game's own step
dispatch, or rule it out — two clock reads a frame, always on),
`util/instances/make-display-part` (anchored / non-colliding / non-query /
shadowless, the flags every cosmetic-geometry builder was copy-pasting),
`util/ui/zoom-to-extents` (fit a viewport camera to a model),
`util/analytics/__analytics_economy` (was a literal `UNFINISHED` placeholder),
`shared/records/tags` (tag names as constants, so a typo is a nil index at
require time instead of a feature that quietly stops working).

### Still open

- **No test runner, and no shared spec harness.** The ghost game grew 45 specs
  / ~15k lines, each run by hand as `lune run tests/<name>.spec.luau`, and each
  carrying its own copy-pasted `check` / `strip` / `walk` / `block_after`
  helpers. Every spec that wants to exercise real game code does it by
  regex-extracting a function out of the source file and `luau.load`-ing the
  text, because there is no way to require a Roblox module under Lune.
- **No way to check requires resolve.** Four of the five dead modules above
  would have been caught by a twenty-line script.
- Boot / multi-place layout, the appearance service, sound groups and
  fire-and-forget playback, asset preloading, the fatal handler, remote
  payload validation, and model layout by tag are all still game-local and
  still worth generalising.
