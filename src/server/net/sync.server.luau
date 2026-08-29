const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm_sync = require(ReplicatedStorage.Packages["charm-sync"])
const sync_registry = require(ReplicatedStorage.Shared.services["sync-registry"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const server_network = require(script.Parent["server-network"])

-- Minimum gap between full snapshots for one player, so a client cannot spam
-- us into rebuilding its whole state every frame.
const REQUEST_COOLDOWN = 1 -- seconds between full-snapshot requests per player

charm_sync.config.validatePatches = false

charm_sync.server.connect(function(player: Player, payload)
	server_network.charm.sync:fire(player, payload)
end)

const last_attach: { [Player]: number } = {}
const trailing: { [Player]: true } = {}

local function attach_now(player: Player)
	last_attach[player] = os.clock()
	sync_registry.attach(player)
end

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
		trailing[player] = nil
		-- detach has already run for a player who left; re-attaching would
		-- resurrect their entry in the registry and pin them in memory.
		if player.Parent ~= nil then
			attach_now(player)
		end
	end)
end)

observe_players(function(player: Player): () -> ()
	return function()
		last_attach[player] = nil
		trailing[player] = nil
		sync_registry.detach(player)
	end
end)
