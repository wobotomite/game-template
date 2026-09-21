const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

-- Hold everyone at the start until the whole party has actually loaded in.
--
--   const gate = require(ServerScriptService.Server.players["party-gate"])
--
--   gate.configure {
--       expected = function() return party_size end,
--       on_progress = function(ready, expected) show(`WAITING…  {ready}/{expected}`) end,
--   }
--   server_network.run.client_loaded:connect(gate.mark_ready)   -- see below
--   gate.wait_for_party()                                        -- yields
--
-- WHY A GATE AT ALL. Players arrive at wildly different times — a teleport
-- lands them seconds apart, assets stream at whatever the connection allows,
-- and saved data has to come down before anything can be drawn from it.
-- Starting when the first one is ready means the rest miss the opening, and in
-- a co-op game the opening is usually the part that explains the rules.
--
-- =========================== THE THREE RULES ==============================
--
-- **A TIMEOUT IS NOT OPTIONAL.** A player whose client crashed, or whose
-- teleport half-failed, never reports ready — and without a failsafe the whole
-- party waits on them forever. The gate opening late is a bad minute; the gate
-- never opening is a dead session for everybody.
--
-- **NOTHING BEFORE THE HANDLER CONNECT MAY YIELD.** This is the rule that
-- actually bites, and it is invisible.
--
-- sendbufs has no queue: an event that arrives before its handler is connected
-- is dropped in silence. A ready signal is fired ONCE per client, with no
-- retry. So if any of the setup ahead of that connect gives up its scheduler
-- slice — a `task.wait`, a `WaitForChild`, an async call — a client that
-- finished loading during the gap fires into nothing and is never counted. The
-- gate then holds the entire party on them for the full timeout, with no error,
-- nothing in the console, and no failing test to point at it.
--
-- Two defences, and use both: order your boot so every handler is connected
-- before anything that can yield, and write a spec that enforces it. The game
-- this came from has an init-no-yield spec -- a source scan over its named
-- entry points, first-order deliberately, because the transitive reach is not
-- statically tractable. First-order is enough to catch the regression that
-- actually happens: somebody adds a wait to a service init.
--
-- **`expected` IS A CALLBACK, not a number.** The party size is not known at
-- boot in most shapes of game — it arrives with teleport data, or it is however
-- many players are in the server when the countdown ends. Reading it per poll
-- also means a player who leaves during the wait shrinks the target instead of
-- stranding it above what can ever be reached.

export type Config = {
	-- How many players the gate is waiting for, asked once per poll. Return 0
	-- to mean "not known yet" -- the gate keeps waiting rather than opening on
	-- a vacuous match.
	expected: (() -> number)?,
	-- Called on each poll while waiting, for a status sign or a loading label.
	on_progress: ((ready: number, expected: number) -> ())?,
	-- Failsafe, in seconds.
	timeout: number?,
	-- How often to re-check.
	interval: number?,
	-- EARLY OPEN. Seconds of quiet after which "everyone who is actually here is
	-- ready" counts as the whole party. Unset means never: the gate then waits
	-- out the full timeout for a player who may not be coming. See
	-- `wait_for_party`.
	stall: number?,
}

local expected_fn: (() -> number)? = nil
local on_progress: ((number, number) -> ())? = nil
local timeout = 30
local interval = 0.25
-- Infinity, so the early open is OFF until a game asks for it. The gate's
-- guarantee is "everybody who was expected got in"; trading that for a faster
-- start is the caller's call to make, not a default to inherit.
local stall = math.huge

const ready_players: { [Player]: true } = {}

-- When the roster last grew. Compared against `stall` below, so a player
-- arriving restarts the quiet period and cannot be left behind by an early
-- open that was already halfway through deciding.
local last_arrival = os.clock()

local started = false
local function ensure_cleanup()
	if started then
		return
	end
	started = true
	-- A player who leaves is neither ready nor expected; leaving their entry
	-- behind would let a later join inherit someone else's readiness.
	observe_players(function(player: Player): () -> ()
		last_arrival = os.clock()
		return function()
			ready_players[player] = nil
		end
	end)
end

function configure(config: Config)
	expected_fn = config.expected or expected_fn
	on_progress = config.on_progress or on_progress
	timeout = config.timeout or timeout
	interval = config.interval or interval
	stall = config.stall or stall
	ensure_cleanup()
end

-- Connect this to whatever event a client fires when it is genuinely ready --
-- data synced, assets warmed, character spawned. Idempotent, because a client
-- that reconnects mid-gate may well send twice.
function mark_ready(player: Player)
	ensure_cleanup()
	ready_players[player] = true
end

function is_ready(player: Player): boolean
	return ready_players[player] == true
end

function ready_count(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if ready_players[player] then
			count += 1
		end
	end
	return count
end

-- Yields until the party is ready or the failsafe passes. Returns whether it
-- opened because everyone arrived — a caller that wants to log or telemeter the
-- difference between "started properly" and "started on the timeout" can, and
-- that difference is worth watching, because a rising timeout rate is the first
-- sign the ready signal is being lost.
function wait_for_party(): boolean
	ensure_cleanup()
	const deadline = os.clock() + timeout
	while os.clock() < deadline do
		const expected = if expected_fn then expected_fn() else #Players:GetPlayers()
		const ready = ready_count()
		if expected > 0 and ready >= expected then
			return true
		end
		if on_progress then
			on_progress(ready, expected)
		end

		-- THE EARLY OPEN. `expected` is a prediction -- the party size the
		-- teleport promised -- and it is routinely wrong by one: somebody
		-- declined the teleport, or crashed on the way over. Waiting the full
		-- failsafe for a player who is not coming costs every other player that
		-- whole timeout, which is the common case of a gate feeling broken.
		--
		-- So: if everyone who is ACTUALLY IN THIS SERVER is ready and nobody new
		-- has joined for `stall` seconds, treat that as the party. `present > 0`
		-- keeps an empty server from matching vacuously, the same guard
		-- `expected > 0` is above. This returns TRUE -- it is a real start, not a
		-- failsafe -- and a game that needs to tell the two apart should count
		-- players itself rather than read the return value.
		const present = #Players:GetPlayers()
		if present > 0 and ready >= present and os.clock() - last_arrival >= stall then
			return true
		end

		task.wait(interval)
	end
	warn(`[party-gate] opened on the {timeout}s failsafe with {ready_count()} ready`)
	return false
end

function reset()
	table.clear(ready_players)
	-- Otherwise the first poll of the NEXT gate measures quiet since the last
	-- join of the last one, and opens early on arrivals that already happened.
	last_arrival = os.clock()
end

return table.freeze {
	configure = configure,
	mark_ready = mark_ready,
	is_ready = is_ready,
	ready_count = ready_count,
	wait_for_party = wait_for_party,
	reset = reset,
}
