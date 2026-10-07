# Server hardening

What the server half of the template assumes about a hostile client and an
unhelpful boot order, and the seams a new game plugs into rather than patches.

Every rule below came out of a shipped game, not a threat model. The companion
document for the wire itself is `docs/network.md`; this one is about what
happens once a payload has been decoded.

## The limiter is a sliding ring

`validate.limiter(max_count, window)` in `src/server/net/validate.luau` keeps a
per-player ring of `max_count` timestamps and asks one question: *was the
oldest of my last `max_count` calls inside the window?* If it was, the call is
rejected **without consuming a slot**, so a client hammering a closed limiter
cannot push its own legitimate call out of the ring.

This replaces a tumbling window, whose failure is a burst at the boundary:
`max_count` at the end of one window and `max_count` at the start of the next
is **2x max_count** in a moment, and the limiter reports nothing unusual. Size
a limit against the behaviour you want, not against twice it.

```luau
const limit = validate.limiter(10, 5) -- 10 per 5s, per player
```

Two properties worth knowing before you tune one. The ring is allocated at
`limiter()` time per player, `max_count` entries of `-math.huge`, so a large
`max_count` costs memory per concurrent player rather than per call. And a
player who leaves is forgotten by the limiter, which means a rejoin resets the
window — every limiter here is a comfort limit, never the only thing standing
between a client and something expensive.

## Shape is not value

sendbufs proves a payload decodes into the declared types. It proves nothing
about the numbers inside, and the validators exist for the gap:

- `count(n, max)` — a whole number in `[0, max]`. Fractions, negatives, NaN and
  infinity are all rejected. Most "how many" fields on a wire want this one.
- `text(s, max_chars)` — a string within a length ceiling, so a handler that
  concatenates or stores one cannot be handed a megabyte.
- `user_id(n)` — a plausible user id: whole, positive, below `2^53`, where
  doubles stop counting exactly and equality between two ids stops being
  reliable.
- `finite`, `finite_vector`, `sane_direction` — the numeric guards, kept from
  before; NaN passes `typeof(n) == "number"` and defeats a range check written
  the obvious way, because `n > max` and `n < min` are both false for it.
- `alive_root(player)`, `downed(player)` — the character-state questions a
  handler asks before acting on a request.

`tests/validate.spec.luau` pins the arithmetic, including the boundary burst
the old window got wrong.

## The sync handshake is a module

`src/server/net/sync.luau` is the charm-sync registry's server half, and it is
a module with `start()` and `wait_for_attach(player, timeout)` rather than a
script, so a service that must not act before a player's atoms exist can wait
for that instead of guessing:

```luau
if not sync.wait_for_attach(player, 10) then
	return -- they left, or the handshake never landed
end
```

`start()` is idempotent, and the boot list in `src/server/init.server.luau`
calls it first, before anything can register an atom or yield.

The waiter is a coroutine parked on `coroutine.yield`, woken either by the
attach or by a `task.delay` timeout, whichever comes first, with a `settled`
flag so it can never be resumed twice. On detach the flag is cleared **and
every parked waiter is woken** — a waiter left parked on a departed player is a
thread that never returns and a closure that holds that Player alive for the
life of the server.

## Characters

`src/server/players/setup-ragdolls.luau` builds a rig's ragdoll constraints
through `src/util/observers/observe-rig.luau`, which answers the one question
that matters — *are all the parts here yet* — instead of racing `CharacterAdded`
against replication. It guards on the rig it has already prepared, because the
observer can fire again for the same character, and it clears
`humanoid.RequiresNeck`, without which the engine kills the character the
instant the ragdoll's neck goes slack.

`src/shared/world/character-exclusion.luau` maintains the raycast filter of
live character models. It forgets a character **by identity** when that
character goes away, and it checks `character.Parent` as well as existence,
because `player.Character` keeps pointing at the old model for a frame or two
after a death — long enough for a rebuilt filter to contain a corpse.

## Alerts are text; the sound is a seam

`src/shared/services/alert.luau` owns what a line LOOKS like — upper-cased,
keywords coloured from `settings.alerts.HIGHLIGHTS`, rich text the caller wrote
left exactly as written — and knows nothing about audio. The client audio
registers itself:

```luau
alert.set_voice(function(sound: string?)
	-- map an alert.SOUND key to a cue
end)
```

A direct require of the client's audio would make this module client-only, and
it is required on the server too. Until something registers, alerts are silent
and still readable, which is the right failure.

Three things in `decorate` are not obvious and all three were bugs first: a
rich-text **entity** is copied through un-raised (`&amp;` upper-cased becomes
`&AMP;`, which Roblox draws literally); keyword matching requires a non-letter
on both sides, or "COIN" colours three letters of "COINCIDE"; and text already
inside a caller's own `<font>` is shouted but never highlighted, because Roblox
takes the innermost colour and a caller who coloured a span meant it.
`tests/alert-text.spec.luau` pins all three.

## The anticheat's speed ceiling is a setting

`src/server/anticheat` flags nothing below `settings.character.TOP_SPEED`
multiplied by its own slack. `TOP_SPEED` is the fastest a **legitimate** player
travels by any means the server does not express as `Humanoid.WalkSpeed` — a
vehicle, a launcher, a conveyor, a sprint multiplier on the assembly. It is the
one number a game revisits when it adds a fast loadout, and the only thing
between that loadout and a kick.

`anticheat.observed_speed(player)` exposes the sampler's own reading, decayed
rather than instantaneous, so a feature that wants "are they moving fast right
now" reads the number the anticheat already computes instead of sampling the
character a second time.

## Studio commands sit behind three gates

`src/server/debug-commands.server.luau` gives a Studio session `god`, `heal`,
`kill_me` and `wipe_data`, and a game adds its own to the `commands` table.
Three independent things keep it out of production, deliberately:

1. the whole file is behind an early `return` outside Studio;
2. the remote that carries a command is declared `nil` outside Studio in
   `src/shared/network.luau`, so it does not exist to be fired;
3. `execute` re-checks before it dispatches.

The cost of a forgotten gate is a shipped `wipe_data` any client can fire, so
none of the three is redundant.

Two entry points reach `execute`: the remote, and a `BindableFunction` named
`StudioDebug` in ReplicatedStorage. The bridge is for anything inside the same
Studio session — the command bar, a plugin, an automated harness — and it
returns a **string**, either an error or a state line, because both callers
want to report a failure somewhere specific rather than have one thrown through
them. An empty command name means "just tell me the state".

A multi-place game puts its own commands in a `debug-commands` module inside
its `PlaceServer<Role>` folder; the script finds that folder **by name** and
merges it, so a place a build does not contain is an absent folder rather than
a require that fails. The merge is over the generic table, so a place can
replace a generic command as well as add one.

Everything a command says to a player is in `strings.debug`, prefixed `DEBUG:`.
In a session full of toasts the one thing worth knowing at a glance is which
lines are the game talking and which are you.
