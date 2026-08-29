const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const charm_sync = require(ReplicatedStorage.Packages["charm-sync"])

-- Central registry for charm-synced atoms. Feature modules call `register`
-- (both realms) instead of talking to charm-sync directly, so the server can
-- hand a joining client every atom at once when it requests its first sync,
-- and re-send full snapshots on demand.
--
-- `register` keys replicate to every client. `register_for_player` keys
-- replicate only to the given player (use for private state like saved data;
-- keys must still be globally unique, e.g. suffixed with the user id).

const registered: { [string]: any } = {}
const player_registered: { [Player]: { [string]: any } } = {}
const attached: { [Player]: true } = {}

local on_late_register: (() -> ())? = nil

local function register(key: string, atom: any)
	assert(registered[key] == nil, `duplicate sync key {key}`)
	registered[key] = atom

	if RunService:IsClient() then
		charm_sync.client.addSignals { [key] = atom }
		if on_late_register then
			on_late_register()
		end
	else
		for player in attached do
			charm_sync.server.addSignalsToClient(player, { [key] = atom })
		end
	end
end

local function register_for_player(player: Player, key: string, atom: any)
	assert(RunService:IsServer(), "register_for_player is server-only; clients use register")
	local keys = player_registered[player]
	if not keys then
		keys = {}
		player_registered[player] = keys
	end
	assert(keys[key] == nil and registered[key] == nil, `duplicate sync key {key}`)
	keys[key] = atom
	if attached[player] then
		charm_sync.server.addSignalsToClient(player, { [key] = atom })
	end
end

-- Server: subscribe (or re-subscribe) a client to every registered atom.
-- Removing first marks all keys pending again, so the client always receives
-- a full snapshot — safe to call repeatedly.
local function attach(player: Player)
	assert(RunService:IsServer(), "attach is server-only")
	charm_sync.server.removeClient(player)
	attached[player] = true
	charm_sync.server.addSignalsToClient(player, registered)
	const private_keys = player_registered[player]
	if private_keys then
		charm_sync.server.addSignalsToClient(player, private_keys)
	end
end

local function detach(player: Player)
	assert(RunService:IsServer(), "detach is server-only")
	attached[player] = nil
	player_registered[player] = nil
	charm_sync.server.removeClient(player)
end

-- Client: invoked by sync.client to be notified when an atom registers after
-- the initial request, so it can re-request a snapshot.
local function set_late_register_hook(fn: () -> ())
	assert(RunService:IsClient(), "late-register hook is client-only")
	on_late_register = fn
end

return table.freeze {
	register = register,
	register_for_player = register_for_player,
	attach = attach,
	detach = detach,
	set_late_register_hook = set_late_register_hook,
}
