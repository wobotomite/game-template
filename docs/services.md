# The server services

Everything the server runs is a module with a `start()`, and
`src/server/init.server.luau` is the list of them in order. That list is the
answer to "what is running on this server", and it is a list rather than a pile
of side effects at require time so that the answer does not have to be
reassembled by reading every file.

Two things start themselves, both because something else already has to require
them, and both say so in their own headers:
`src/server/data/data-lifecycle.server.luau` and
`src/server/leaderboards/leaderboards.server.luau`.

Each `start()` is idempotent. A game that also starts one from somewhere of its
own gets one instance, not two.

## Everything is data first

A service here owns a rule, not a number. The numbers are in
`src/shared/settings.luau`, the ids in `src/shared/assets.luau`, the words in
`src/shared/strings.luau`, one section per service. **An id that is not set is
`0` or `""`, and every service degrades rather than breaking on it**: the badge
service skips an unset badge and warns once, the pass service reports an unset
pass as not owned, the reminder scheduler stays idle. That is what makes a fresh
clone of this template boot and play before anything has been created on the
Creator Dashboard.

Joined tables live in `src/shared/records/` — `src/shared/records/products.luau`
is the three-way join of `settings.commerce.PRODUCTS`, `assets.products` and
`strings.commerce.PRODUCTS` by KEY, and it is what the receipt path indexes by
Roblox product id. Adding a product means adding a row to each of the three, not
touching a service.

## Saved data, and who hears about it

`src/server/data/datastore/init.luau` returns a lyra `PlayerStore` and is the
only file that talks to lyra's configuration.
`src/server/data/lifecycle.luau` owns the lifecycle around it — load on join,
unload on leave, close on shutdown — and it is where a service says "tell me
when a player's save is in memory":

```luau
lifecycle.on_loaded(function(player: Player) ... end)
```

**Registering late replays.** The callback is called immediately for everyone
already loaded, because Roblox does not promise which Script runs first and a
service that registered a moment after a fast joiner would otherwise miss them —
a bug that only exists on a live server. Which is also the constraint on your
callback: it must be safe to run for a player mid-session, not only at their
join.

The alternative shape — the lifecycle requiring each service and calling them in
order — is what the game this was ported from did, and it makes one file require
half the server at boot whether the game uses those services or not.

New saved fields go in `src/shared/datastore/datastore-schema.luau` AND
`src/shared/datastore/datastore-template.luau`, plus a step in
`src/server/data/datastore/migrations.luau`. The template only fills a profile
being created for the first time, so a field added later is absent on every
existing save until a migration adds it — and the schema then rejects the load.

## Commerce

`src/server/players/receipts.luau` owns `MarketplaceService.ProcessReceipt`, and
it is the one file here where being slightly wrong costs real money in both
directions. Two rules, and everything in it is one of them:

- **Grant idempotently.** The purchase id goes into a ledger inside the player's
  own save, in the same transaction as the grant. A ledger in server memory only
  answers for receipts that arrive on the server that granted them, which is the
  easy half.
- **Save before you say yes.** `PurchaseGranted` is returned only after the
  profile is written. `NotProcessedYet` is not a failure — it is "ask me again
  later", and it is the only correct answer when the grant could not be made
  durable.

A product that grants something other than currency registers an `apply` with
`set_apply`; it runs INSIDE the transaction, so it must be a pure function of
the save. Anything that yields or talks to the client goes in `set_on_granted`.

`src/server/players/pass-service.luau` caches pass ownership, retries a nil
answer, and mirrors each pass onto a Player attribute so a client can read it
without a round trip. `on_owned(fn)` is how a game applies what a pass unlocks.
Every yield in it is followed by an `if player.Parent == nil then` guard, which
is not defensiveness: an ownership check is a web call, and a player can leave
during it.

`src/server/players/badge-service.luau` has `award`, with a retry, a
`UserHasBadgeAsync` guard and an in-flight dedupe per player. `refresh` is left
as a seam: it is where a game awards the badges its own progress fields have
earned, and the template cannot know what those are.

## Leaderboards

`src/server/leaderboards/service.luau` publishes global boards from
OrderedDataStores. **The one rule it exists for: never publish a score that is
not saved.** A board cannot be rolled back and a save can, so a board that is
ahead of the save is permanently wrong — a player who sees their best score on
the board and not in their own profile is looking at a bug nobody can fix.

That rule is why the coupling with
`src/server/data/datastore/init.luau` exists rather than the service reading
saves itself. Only that file knows the difference between "this changed" and
"this is durable", so it feeds the service both: `queue` on a change,
`confirm_saved` on a write, `discard_unsaved` when a session ends badly, and a
`set_checkpoint` the board worker calls to force a save for a score that is due.

Which stat, which store, how many rows and how often are all
`settings.leaderboards`. **The store NAME is the board**: bump the suffix to
start a season, and understand that doing it by accident silently retires a live
one.

`src/server/leaderboards/name-cache.luau` turns user ids into names — batched,
spaced, LRU-evicted, and never retried immediately on failure, because a board
is fifty ids every refresh for hours and one call per row is how the rate limit
is hit. A player who is in this server is not cached at all: their name is on
their Player instance, free and current.

Boards reach the client as the `boards` atom in
`src/shared/atoms/leaderboard-atoms.luau`, whose `status` has four states.
`loading` and `unavailable` are different facts — one is "wait", the other is
"the DataStore is down" — and a UI that cannot tell them apart shows a spinner
forever during an outage.

## Daily rewards

The rules are pure and live in `src/shared/economy/daily-rewards.luau`: what day
a streak is on, whether it can be claimed, what that day pays. They take the
save's record and the current day as arguments and touch no clock, which is what
lets `tests/daily-rewards.spec.luau` drive the two cases that matter — the grace
window's edge, and the rollover.

**Days are numbers, not timestamps.** `day_of` floors unix time by
`settings.daily.DAY_SECONDS`, and the save holds the result, so "have they
claimed today" is an integer comparison and the rollover is one instant for
every player in the game. A rule written against elapsed time instead gets the
midnight case wrong in both directions.

`src/server/players/daily-rewards.luau` is the claim. It decides everything
inside the lyra transaction — "have they claimed" and "credit them" have to be
the same write, or two claims arriving together both read "not yet" and both pay
— and then forces a save, because an unflushed claim is one that can be made
again on the next server. A game that wants the rewards gated behind something
registers a `set_gate` rather than editing the file; that gate runs inside the
transaction too, so it must be pure.

`src/server/players/daily-reminders.luau` is optional and idle until
`assets.notifications.DAILY_READY` names a notification string authored on the
Creator Dashboard, with Roblox's Open Cloud package present in
ServerScriptService. It is a MemoryStoreSortedMap used as a due-queue, with the
due time as the sort key, and a lease: every server in the game polls the same
map and will see the same due item in the same second, so taking an item means
winning a write. Without the lease a player in a twenty-server game gets twenty
notifications.

## Voice

`src/server/players/voice-service.luau` attaches one `AudioDeviceInput` per
player, named from `settings.voice.INPUT_NAME`. It pairs with the
`VoiceChatService` block in `default.project.json` — the new Audio API enabled,
the default voice pipeline off — and neither half does anything useful without
the other.

## Adding a service

1. A module with `start()`, idempotent, under `src/server/`.
2. Its numbers, ids and words in the three data files, one section each, every
   value carrying why it is that value.
3. A line in the boot list in `src/server/init.server.luau`, placed where the
   comments say order matters and at the end where it does not.
4. If it needs a player's save, `lifecycle.on_loaded` — not a require from the
   lifecycle.
5. If it needs the wire, a new group in `src/shared/network.luau`, and connect
   the handler before anything that can yield. See `docs/network.md`.
