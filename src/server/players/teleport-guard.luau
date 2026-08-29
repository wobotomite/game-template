const ReplicatedStorage = game:GetService "ReplicatedStorage"
const TeleportService = game:GetService "TeleportService"

const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

-- Retry and recovery for player teleports between places.
--
-- THE HOLE THIS FILLS. `TeleportService:TeleportAsync` returning cleanly does
-- NOT mean anybody arrived. The failure can land afterwards, asynchronously, as
-- `TeleportService.TeleportInitFailed` — and if nothing is listening for it,
-- the player is left in a state strictly worse than "never left":
--
--   * their save session was very likely UNLOADED before the teleport (that is
--     what releases the lock so the destination can load it), so their data is
--     gone from this server;
--   * they are standing wherever the departure left them, which the sending
--     system has usually already reset — so the next tick starts the same
--     failing departure over;
--   * and nothing has said a word to them.
--
-- The common cause is `Flooded`, which is transient, so the right response is
-- to retry before giving up.
--
-- RETRY WITH THE SAME OPTIONS. This is the part that is easy to get wrong and
-- expensive when you do: a reserved server is addressed by the access code
-- inside the TeleportOptions the party was sent with. Building fresh options
-- for the retry sends that player to a PUBLIC server instead — they arrive
-- somewhere real, alone, and the party is split with no error anywhere.
--
-- Both directions of a two-place game need this, and in the game this came from
-- each side had grown its own copy of the same loop. One implementation, two
-- call sites:
--
--   local guard = require(ServerScriptService.Server.players["teleport-guard"])
--   guard.configure { on_give_up = function(player, place_id) ... end }
--   guard.send(place_id, player, options)

export type Config = {
	-- How many attempts in total, including the first.
	attempts: number?,
	-- Seconds between attempts.
	retry_delay: number?,
	-- Called when the budget is spent, or when a teleport we have no options
	-- for fails. THIS IS WHERE RECOVERY LIVES: reload the player's save,
	-- put their character somewhere legal, and tell them what happened.
	-- Without it, a spent budget is silent.
	on_give_up: ((player: Player, place_id: number) -> ())?,
}

local attempts = 3
local retry_delay = 2
local on_give_up: ((player: Player, place_id: number) -> ())? = nil

-- The options each player was last sent with, per player rather than one
-- module-level copy: every party has its own access code, and two departures
-- can be in flight at once.
const sent_with: { [Player]: TeleportOptions } = {}
const sent_to: { [Player]: number } = {}
const retries: { [Player]: number } = {}

local function forget(player: Player)
	sent_with[player] = nil
	sent_to[player] = nil
	retries[player] = nil
end

local function give_up(player: Player, place_id: number)
	forget(player)
	if on_give_up and player.Parent then
		-- pcall: recovery is the LAST thing standing between this player and
		-- being stranded, so a throw inside it must not also lose the cleanup
		-- above or the rest of the handler.
		const ok, err = pcall(on_give_up :: any, player, place_id)
		if not ok then
			warn(`[teleport-guard] recovery for {player.Name} threw: {err}`)
		end
	end
end

function configure(config: Config)
	attempts = config.attempts or attempts
	retry_delay = config.retry_delay or retry_delay
	on_give_up = config.on_give_up or on_give_up
end

-- Record a teleport this module did not fire itself. Anything that calls
-- TeleportAsync directly must call this, or its failures land in the silent
-- path: `TeleportInitFailed` arrives with no options to retry from.
function record(player: Player, place_id: number, options: TeleportOptions)
	sent_with[player] = options
	sent_to[player] = place_id
	retries[player] = nil
end

-- Send a player, recording them for retry. Returns false if the call threw
-- outright — in which case recovery has already run, so a caller only needs
-- this to stop doing whatever came next.
function send(place_id: number, player: Player, options: TeleportOptions): boolean
	record(player, place_id, options)
	const ok, err = pcall(function()
		TeleportService:TeleportAsync(place_id, { player }, options)
	end)
	if not ok then
		warn(`[teleport-guard] TeleportAsync to {place_id} threw for {player.Name}: {err}`)
		give_up(player, place_id)
		return false
	end
	return true
end

-- Longest a caller should wait before treating a player as stranded: every
-- retry, plus a grace. DERIVED rather than restated, so raising `attempts`
-- cannot quietly move a watchdog deadline in underneath the retries it is
-- supposed to sit behind.
function strand_deadline(grace: number): number
	return attempts * retry_delay + grace
end

local started = false
function init()
	if started then
		return
	end
	started = true

	observe_players(function(player: Player): () -> ()
		return function()
			forget(player)
		end
	end)

	TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, _message, place_id: number)
		const options = sent_with[player]
		if not options or not player.Parent then
			-- Nothing to retry with, or nobody to retry for. Recovery still
			-- runs: an unrecorded teleport strands a player exactly as a
			-- recorded one does.
			give_up(player, place_id)
			return
		end

		const used = (retries[player] or 0) + 1
		retries[player] = used
		if used >= attempts then
			give_up(player, place_id)
			return
		end

		task.delay(retry_delay, function()
			-- Both guards matter: the player may have left, and they may have
			-- been sent somewhere else in the meantime — retrying a superseded
			-- departure would drag them back out of the one that worked.
			if not player.Parent or sent_with[player] ~= options then
				return
			end
			const ok = pcall(function()
				TeleportService:TeleportAsync(place_id, { player }, options)
			end)
			if not ok then
				give_up(player, place_id)
			end
		end)
	end)
end

return table.freeze {
	init = init,
	configure = configure,
	record = record,
	send = send,
	strand_deadline = strand_deadline,
}
