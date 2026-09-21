const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm_sync = require(ReplicatedStorage.Packages["charm-sync"])
const sync_registry = require(ReplicatedStorage.Shared.services["sync-registry"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const server_network = require(script.Parent["server-network"])

-- The server half of the charm-atom handshake: a joining client asks for a
-- snapshot, this hands it every registered atom, and charm-sync streams patches
-- from then on.
--
-- A MODULE WITH `start()`, not a script that runs itself. Two reasons, and the
-- second is the one that bites:
--
--   * boot ORDER. Nothing may register an atom before this connects
--     `request_sync`, and a self-running script's position in the boot is
--     whatever order the engine happened to run the scripts in. An explicit
--     `start()` in the boot list is a line you can read and move.
--   * `wait_for_attach` below has to be callable, and a script exports nothing.
--
-- `start-sync.server.luau` beside this file is the one-line script that calls
-- it, for a game that has no boot list of its own yet.

-- Minimum gap between full snapshots for one player, so a client cannot spam
-- us into rebuilding its whole state every frame.
--
-- ONE SECOND, and the client's retry interval is sized against it -- see
-- `src/client/net/sync.client.luau`. Raising it makes the trailing edge below
-- worse in a way that is easy to miss: every late atom registration waits out
-- the full cooldown before its initial state reaches a client that has already
-- stopped retrying.
const REQUEST_COOLDOWN = 1 -- seconds between full-snapshot requests per player

const last_attach: { [Player]: number } = {}
const trailing: { [Player]: true } = {}
-- Players whose atoms have actually been handed over at least once. This is
-- the question `wait_for_attach` answers, and it is NOT the same as "is in the
-- server": a player exists for as long as it takes their client to boot,
-- request, and be answered.
const attached: { [Player]: true } = {}
const waking: { [Player]: { () -> () } } = {}

-- Release every waiter for this player, whatever the outcome. Called on attach
-- AND on departure: a waiter on somebody who left must not sit out its whole
-- timeout, because the caller is usually holding a round, a spawn, or a queue
-- slot behind it.
function wake_all(player: Player)
	const waiters = waking[player]
	if not waiters then
		return
	end
	waking[player] = nil
	for _, wake in waiters do
		wake()
	end
end

function attach_now(player: Player)
	last_attach[player] = os.clock()
	sync_registry.attach(player)
	if attached[player] then
		return
	end
	attached[player] = true
	wake_all(player)
end

-- Yields until this player's atoms are attached, or `timeout` seconds pass.
-- Returns whether they are attached -- check it; the timeout is not an error
-- and a caller that assumes success will write into a client that is not
-- listening.
--
-- WHAT THIS IS FOR. Firing a UI event at a client whose atoms have not
-- attached yet is a message about state the client cannot see: the event lands,
-- the panel reads an atom that is still nil, and nothing happens. Before this,
-- the fix at every call site was a `task.wait(2)` chosen by feel -- too long on
-- a fast join, and still too short on a slow one.
function wait_for_attach(player: Player, timeout: number): boolean
	if attached[player] then
		return true
	end
	const thread = coroutine.running()
	-- `settled` because there are two ways to be woken and they race: the
	-- attach and the timeout. Resuming a thread that has already been resumed
	-- throws "cannot resume non-suspended coroutine" from inside whichever
	-- arrived second, which is a scheduler error reported against innocent code.
	local settled = false
	local function wake()
		if settled then
			return
		end
		settled = true
		-- spawn rather than resume: this runs from inside `attach_now`, and
		-- resuming the waiter inline would run the rest of ITS function before
		-- the rest of the attach.
		task.spawn(thread)
	end
	local waiters = waking[player]
	if not waiters then
		waiters = {}
		waking[player] = waiters
	end
	table.insert(waiters, wake)
	task.delay(timeout, wake)
	coroutine.yield()
	return attached[player] == true
end

local started = false
function start()
	if started then
		return
	end
	started = true

	charm_sync.config.validatePatches = false

	charm_sync.server.connect(function(player: Player, payload)
		server_network.charm.sync:fire(player, payload)
	end)

	-- A request inside the cooldown is COALESCED, never dropped. Dropping it is
	-- what used to strand clients: the client re-requests when a feature module
	-- registers an atom after its first ask, and that re-request always lands
	-- within a frame or two of the first — i.e. always inside the cooldown. The
	-- client had already seen a payload by then, so its retry loop had stopped,
	-- and the late-registered key's initial state was never sent. charm-sync only
	-- sends `init` for a key once, so that state was gone for good.
	server_network.charm.request_sync:connect(function(player: Player)
		const last = last_attach[player]
		if not last then
			attach_now(player)
			return
		end

		const remaining = REQUEST_COOLDOWN - (os.clock() - last)
		if remaining <= 0 then
			attach_now(player)
			return
		end

		if trailing[player] then
			return
		end
		trailing[player] = true
		task.delay(remaining, function()
			-- The same hole guarded from both sides: detach has already run for
			-- a player who left, and re-attaching would resurrect their entry in
			-- the registry and pin them in memory. The flag is cleared on
			-- departure, so it answers first; the Parent check also covers a
			-- player who leaves during this very frame.
			if not trailing[player] then
				return
			end
			trailing[player] = nil
			if player.Parent ~= nil then
				attach_now(player)
			end
		end)
	end)

	observe_players(function(player: Player): () -> ()
		return function()
			last_attach[player] = nil
			trailing[player] = nil
			attached[player] = nil
			wake_all(player)
			sync_registry.detach(player)
		end
	end)
end

return table.freeze {
	start = start,
	wait_for_attach = wait_for_attach,
}
