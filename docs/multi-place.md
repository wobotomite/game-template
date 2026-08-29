# Multi-place games

Everything here is opt-in. A single-place game needs none of it and pays
nothing for it being present: `place-context` resolves to `main` and no other
piece is required.

## The one fact everything follows from

**One build is published to every place in the universe.** Rojo builds one
tree; you upload that same tree to the lobby place, the run place, and any
other. So a script cannot tell where it is from its own contents — every place
has identical code.

`game.PlaceId` is the only runtime truth. `shared/records/place-ids` maps a role
to each published place id, and `shared/place-context` resolves the role once:

```luau
const place_context = require(ReplicatedStorage.Shared["place-context"])

if place_context.is "lobby" then
	-- lobby-only setup
end
```

Ids are filled in **after** publishing each place. Until then they are 0, which
matches no real PlaceId, so an unconfigured universe behaves like the default
experience instead of like a bug. In Studio, a `PlaceTag` StringValue in
ReplicatedStorage overrides the answer, so a dev file with `PlaceId == 0` can
still be tested as either place. That override is ignored outside Studio — a
tag accidentally baked into a published file must never be able to lie about
which place a live server is.

## Splitting the code per place

Server code is easy: every place's server scripts can live under
ServerScriptService, and each one gates itself on `place_context`.

Client code is not, and this is the part that costs an afternoon if you meet it
cold. **A `RunContext = Client` script cannot run or replicate from
ServerStorage**, and you do not want the run place's client bundle replicating
to every lobby client. The working arrangement is:

- ship **both** client bundles in `ServerStorage`, where neither runs;
- during **server boot**, before any player can join, move the one matching this
  place to `ReplicatedStorage.PlaceClient`.

```json
"ServerStorage": {
  "$className": "ServerStorage",
  "PlaceClientLobby": { "$path": "src/client/lobby" },
  "PlaceClientRun":   { "$path": "src/client/run" }
}
```

```luau
-- src/server/init.server.luau, first thing, inside fatal.guard
fatal.guard("place-boot", function()
	const bundle_name = if place_context.is "run" then "PlaceClientRun" else "PlaceClientLobby"
	const bundle = assert(ServerStorage:FindFirstChild(bundle_name), `missing {bundle_name} in ServerStorage`)
	bundle.Name = "PlaceClient"
	bundle.Parent = ReplicatedStorage
end)
```

Client code then requires `ReplicatedStorage.PlaceClient.<module>` and does not
care which place it is in.

### What this costs you, stated plainly

Those requires **cannot be resolved statically by anything**. The tree they
index into does not exist until a server boots. So:

- `luau-lsp` reports `Unknown require: game/ReplicatedStorage/PlaceClient/*` for
  every one of them, permanently. Worse, anything read *through* such a require
  resolves to an error-type, so the analyzer silently stops type-checking those
  field accesses — a blind spot, not just noise.
- `tests/requires.spec.luau` cannot check them either. Declare the prefix in its
  `IGNORED_PREFIXES` with a comment, so the skip is a stated exception rather
  than a silent one, and any *new* unresolvable prefix still fails.

That trade is worth making, but make it knowingly: a field read through a
relocated bundle has no automated checking behind it at all, and needs a spec
that reads the source, or a check against the live place.

## Teleports between places

Use `server/players/teleport-guard`. The single most important thing it exists for:

**`TeleportAsync` returning cleanly does not mean anybody arrived.** The failure
can land afterwards, asynchronously, through
`TeleportService.TeleportInitFailed`. If nothing listens for that event, the
player is stranded in a state worse than never having left — their save session
was released before the teleport, so their data is gone from this server, and
whatever launched them has already reset itself.

```luau
const guard = require(ServerScriptService.Server["teleport-guard"])

guard.configure {
	attempts = 3,
	retry_delay = 2,
	on_give_up = function(player, place_id)
		-- Reload their save FIRST -- an alert and a retry button are both
		-- useless to a player whose data is not in this server.
		datastore:loadAsync(player)
		put_them_somewhere_legal(player)
		alert.send_to(player, "Couldn't get you there — you're back in the lobby.")
	end,
}
guard.init()

guard.send(place_ids.run, player, options)
```

**Retry with the same `TeleportOptions`.** A reserved server is addressed by the
access code inside them. Building fresh options for a retry sends that player to
a *public* server instead: they arrive somewhere real, alone, the party is split,
and no error is raised anywhere.

Both directions need this. In the game this template came from, each side had
grown its own copy of the same loop, and the lobby side — the side that starts
every session — was written months after the run side and had the whole thing
missing.

## Boot failures

Wrap anything at boot whose failure would leave the server half-built in
`fatal.guard`. The default behaviour is bad: the failing script dies, every
other script carries on, and the game runs in a state nobody designed — a live
session that cannot save, with nothing on screen to say so. `fatal` logs the
crash (as an `error`, so it reaches the Creator Hub error report with its
traceback) and empties the server, which is the honest outcome.
