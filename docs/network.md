# The wire

Events are declared in one place, `src/shared/network.luau`, and both realms
build their side from that same table (`client-network`, `server-network`).
Everything below is a property of that arrangement plus sendbufs, and every item
is something that produced a real bug rather than a hypothetical one.

## sendbufs has no queue

**An event fired before its handler is connected is discarded, silently.** There
is no buffering and no retry. This has two faces, and they pull in opposite
directions:

**As a hazard.** Anything fired exactly once, with no retry, is a coin flip
against boot order. A place script that creates the remotes and then *yields* —
requires a service and then builds a level, probes a DataStore — leaves its own
handlers unconnected for exactly the frames a client needs to talk to it. The
symptom is a client that waits forever with nothing in the console.

The rule that follows: **connect every handler before anything that can yield.**
If a handshake matters, make it retry until something proves the other side
heard — see `client/net/sync.client.luau`, which keeps asking until a payload
arrives rather than trusting one fire.

**As a defence.** It is also the cleanest way to make a debug wire unreachable
in production: declare the event, and connect a handler only inside
`if RunService:IsStudio()`. Any client can *fire* a remote; with no listener the
fire is a no-op.

But notice what that makes the security property: an **ordering** one. Move the
connect above the guard, or lift the handler into a file that has no guard, and
the wire goes live in production while every test still passes, the types still
check, and the diff reads like tidying. If you rely on this, write a spec that
asserts it — a confident comment is not evidence.

## Event ids are declaration order

sendbufs assigns each event an id by the order `event()` calls appear in the
table. **Inserting an event in the middle renumbers every event after it.**
Append new events at the end of their group.

This matters beyond a mid-deploy version skew: if you ever hand-craft a buffer
to probe a live handler, the id you need is the declaration index, and struct
fields are packed with their keys in DESCENDING order.

## Handlers are hostile input

sendbufs guarantees payload **shape** — a buffer schema cannot decode into the
wrong types. It guarantees nothing about **values** or **rates**, and both are
what a modified client sends.

Use `src/server/net/validate.luau`:

```luau
const validate = require(ServerScriptService.Server.net.validate)

const limit = validate.limiter(10, 5) -- 10 per 5s, per player

server_network.combat.swing:connect(function(player, data)
	if not limit(player) then
		return
	end
	const direction = validate.sane_direction(data.direction)
	if not direction then
		return
	end
	const root = validate.alive_root(player)
	if not root then
		return
	end
	...
end)
```

**Reject silently.** Not `assert`, not `warn`. An assert on a remote handler is
a client-triggerable server error: free log spam, and an exception thrown out of
a shared dispatch costs whatever was scheduled after it on that frame. Drop the
message and move on.

**Check for NaN and infinity explicitly.** `typeof(n) == "number"` is true for
both. NaN in particular poisons every comparison it touches — `n > max` and
`n < min` are both false — so a range check written the obvious way passes it
straight through.

### The rate limit

`validate.limiter` is a sliding ring of timestamps per player, and a rejected
call does not consume a slot. How it behaves at the edges, what it costs and why
it replaced a tumbling window are in `docs/server-hardening.md`, which owns the
whole of `src/server/net/validate.luau`.

## Dead fields

`tests/wire-fields.spec.luau` asserts that every field declared in a struct is
read somewhere in `src/`. A field nothing reads is not an error, not a warning
and not a type failure — it is serialised, sent and discarded, forever, on every
packet, for the life of the server.

It is also how a removed feature leaves a tail: the reader goes, the writer and
the schema stay, and the wire keeps carrying it.

The spec's corpus **includes `/util`**. An earlier version excluded it — the
house rule is "do not *edit* `/util`", which is not the same as never *reading*
it — and it reported the whole analytics funnel as dead, because both its sender
and its handler live there. The wire was fine; the scan had removed the consumer
from its own corpus.
