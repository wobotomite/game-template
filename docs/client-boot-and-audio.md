# The client boot, and the sound it makes

Two halves of one problem. The boot decides **when the player is allowed to
look at the game**; the audio bus decides **which of the things happening at
once the player is allowed to hear**. Both are arbitration, both are invisible
when they work, and both fail in the same direction: in Studio, on a local
machine, with two assets and one player, every version of them looks correct.

## The order is the feature

`src/client/init.client.luau` is four steps and the order is the whole file:

```luau
preload.start { content = images, sounds = cues, heavy_sounds = music }
wait_for_loaded()
vide.mount(app, PlayerGui)
ReplicatedFirst:SetAttribute(TRANSITION.DISMISS_ATTRIBUTE, true)
```

**Preload starts and is never waited on.** `client/boot/preload` returns
immediately and warms on its own thread, so the pass overlaps the data sync and
the spawn instead of running after them. Nothing blocks on `preload.finished()`:
a player who is in and has a body should be playing, and an asset that has not
arrived streams in on demand — which is worse than preloaded and far better than
a loading screen held open for a music bed.

**Nothing mounts before `wait_for_loaded`.** It blocks until saved data has
synced and a character exists. Mounting first is the default and it is wrong in
a way that is easy to miss in Studio, where both arrive in the same breath:
every screen renders once from nil, so a currency counter shows 0 and an
inventory shows empty, then both correct themselves a beat later. On a real
connection that beat is long enough to read.

The character wait is **bounded** by `settings.boot.SPAWN_WAIT_SECONDS`. Data is
waited on forever because the game cannot function without it; a character is
waited on for a while because a game with no spawn, or a place that deliberately
has no character, must still reach its interface rather than hanging behind the
cover with nothing in the console.

**The dismiss is last and it is an attribute.** See below for why it cannot be a
shared module.

## The cover

`src/replicated-first/loading-cover.client.luau` is in ReplicatedFirst because
StarterPlayerScripts do not run until the player's scripts have replicated,
which is most of the wait being covered. That position has a price: **nothing it
requires may live in ReplicatedStorage** — no packages, no widget kit, no shared
services. `src/replicated-first/transition-screen.luau` is therefore
hand-rolled Instances, and it is the one place in the tree that builds UI
without vide.

It reads its numbers and its one string through the `Transition*` aliases in
`default.project.json`, which mount the three shared data files a **second
time**, into ReplicatedFirst.

### The two-instance caveat

A file mounted twice is two ModuleScripts. Equal values, **distinct tables**. So:

- Nothing may compare across that boundary **by identity**. Two tables with the
  same contents are not `==`.
- Nothing may **mutate** one expecting the other to see it. Both copies are
  deep-frozen, so an attempt raises rather than going quiet — which is the only
  reason this is a caveat and not a trap.
- What crosses safely is what is compared by value: strings and numbers.

That is exactly why the hand-off is an **attribute on the ReplicatedFirst
service** holding a string from `settings.transition`, and not a shared signal
or a flag in a module. The two scripts genuinely cannot share one object.

### It takes itself down either way

The cover fades on the attribute, and `settings.transition.FAILSAFE_SECONDS`
after it starts it fades regardless. A boot that never reaches the hand-off — a
profile that will not load, an error thrown on the way — must not leave a player
staring at a title card with no way to tell it from a slow connection. The
teardown is idempotent because both can happen: the failsafe fires while the
fade from a normal dismissal is still running.

Two smaller things worth knowing. The screen is **destroyed**, not left faded:
a `GroupTransparency` of 1 still renders, still sinks input and still runs the
progress sweep for the rest of the session. And a client arriving by teleport
brings the departing place's `SetTeleportGui` screen with it — nothing else will
ever remove it, so the cover destroys it on arrival.

The colours and metrics in `settings.transition` are a deliberate placeholder:
neutral, high-contrast, chosen so the cover is legible rather than so it matches
anything. It does **not** read `settings.ui`, because it cannot — see above. It
is the first block a real game should overwrite, and overwriting it means
writing the palette twice on purpose.

## Buses before cues

`client/audio/sound-groups` owns four SoundGroups — SFX, UI, AMBIENCE, MUSIC —
with levels in `settings.audio.BUS_VOLUME`. Reach for a named bus rather than a
number: a mix built out of per-call volumes has no master, so "quieten the
ambience" becomes a sweep through every call site that plays one.

UI is its own bus rather than part of SFX for one reason: it is the family that
must stay audible when the world is ducked. A menu opened during a boss fight
still has to click.

`client/audio/sound-profile` is the other axis. A spec says how loud a cue is
**in the mix**; a profile says how loud that **recording** is, and can trim the
silence off the front of a badly-cut asset. Keeping them apart is what lets a
sample be swapped without re-balancing every cue that plays it.
`settings.audio.profiles` is empty in a fresh game and should stay that way —
every entry is a correction for one specific upload.

## The cue bus

`client/audio/cue` is the part that earns its complexity. Everything that plays
a one-shot goes through it, and it answers three questions the naive version
never asks.

```luau
const cue = require(ReplicatedStorage.Client.audio.cue)

cue.fire(SPEC, position_or_part, source_key)   -- one shot
cue.hold(SPEC, level, part, key)               -- a looping bed at a level
```

**Should this play at all?** A cue carries a `min_interval` **per source**, so a
sound driven by a per-frame condition fires once rather than sixty times a
second, while the same cue from a different source is unaffected. A positional
cue past its `radius` is not played — not played quietly, not played at zero:
building a Sound to be inaudible costs the same as building one to be heard.

**What gets dropped when everything happens at once?** There is a voice budget
(`settings.audio.cue.MAX_VOICES`). Over it, the weakest existing voice is
evicted if the newcomer outranks it, and otherwise the newcomer is refused.
Priorities are spaced by ten — BACKGROUND, ROUTINE, IMPORTANT, URGENT — so a
game can slot its own tier between two of them without renumbering anything it
did not write. The levels are about **attention**, not loudness.

**When is a voice finished?** Mostly `Ended`. But `Ended` never fires for an
asset that failed to load, so a sweep runs on an interval and retires anything
past `LOAD_DEADLINE` that never reported a `TimeLength` — the only reliable
"did this actually load" tell the engine offers. Without that sweep, every dead
id permanently consumes a slot in the voice budget, and the symptom is a game
that gradually goes quiet over a session.

Beds (`hold`) are the stateful half: a level, a grace period so a bed that
flickers off for a frame does not restart, and a decay in the sweep so one that
stops being asked for fades rather than cutting.

`gate`, `weakest` and `decay` — the three decisions, without the Sounds — are
exported so `tests/cue-policy.spec.luau` can pin them, and so a game can ask the
same questions without playing anything.

### The interface voice

`client/audio/ui-sounds` is six functions — `hover`, `click`, `open`, `close`,
`purchase`, `alert` — over the same bus, with their mixes in
`settings.audio.cues.ui` and their ids in `assets.sounds`. The widget kit calls
`click()` and `hover()` by name.

Every id there is `""`, which is the unset sentinel: the engine treats an empty
SoundId as silence, so a fresh game boots with no audio configured, **says so
once per cue**, and plays nothing rather than playing nothing for a reason
nobody can find.

`alert(sound)` exists to be handed to the shared alert service as its voice, so
a notification makes a sound without the service knowing anything about audio.
That wiring is one line and it belongs at boot.

## Music

`client/audio/music-player` takes a playlist — an array of ids from
`assets.music` — and crossfades between tracks. Two details that were bugs
first.

`Looped` is set to **false explicitly** rather than left at the default. A
looped Sound never fires `Ended`, so one playlist entry that happens to be a
looping asset ends the score for the rest of the session: the track plays
forever and the handler that would pick the next one never runs. The load
watchdog does not catch it either, because the asset *did* load.

`stop()` exists as its own call because `set` skips work when handed the
playlist it already has — and that test is by **identity**. A caller writing
`music_player.set {}` to mean silence builds a fresh table every time and
restarts the fade on every call. `stop()` hands over one shared frozen empty
instead.

## The character, at boot

`client/character/local-character` is `root()` and `head()` for the local
player, nil while the character is dead or still loading. It exists because the
hand-rolled four-liner is wrong twice: it searches the tree on every call, from
per-frame code, and it trusts the first model it finds — `CharacterAdded` can
fire with an **empty** model, so a root resolved at that instant is nil and
stays cached that way. Built on `observe-rig`, the answer corrects itself as
the parts arrive.

`client/character/setup-ragdolls` rebuilds its joints **on every rig**, not once
at boot. A character that respawns is a new model with new Motor6Ds, so a
version that ran once worked perfectly until the first death. It also re-applies
an active ragdoll state to the new rig, because the server's opinion about
whether a player is ragdolled outlives the body it was formed about.

## When the frame rate is the bug

`client/debug/frame-watch` warns on a frame long enough for a player to feel,
and the reason it is worth having next to a profiler is that a profiler tells
you what a frame costs **while you are watching it**. This tells you what was on
screen during a hitch that happened to somebody else, on a connection you do not
have. Register a `add_context` callback per system and a captured line names a
situation instead of a timestamp.

It also keeps a rolling **histogram** — frames at 60, 30, 20, 10 and below —
rather than an average, because an average is the one statistic that cannot see
a stutter. Sixty good frames and one 200ms frame average out to fine, and the
200ms frame is the entire complaint.

## The effects kit

`effects/shared/burst`, `effects/shared/ring` and
`effects/shared/visual-ghost` are general pieces for the moments in
`src/effects/list` to build from — particles, an expanding band, an inert copy
of something still in the world. They are silent by construction, and
`src/effects/README.md` says why: the sound belongs to whoever knows what the
moment means.
