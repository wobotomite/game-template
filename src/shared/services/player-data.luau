const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const charm = require(ReplicatedStorage.Packages.charm)
const datastore_schema = require(ReplicatedStorage.Shared.datastore["datastore-schema"])
const get_instance_id = require(ReplicatedStorage.Util.instances["get-instance-id"])
const sync_registry = require(ReplicatedStorage.Shared.services["sync-registry"])
const deep_copy = require(ReplicatedStorage.Util.tables["deep-copy"])

export type Schema = typeof(datastore_schema:type())

-- Replicates each player's own saved data to (only) their client as a charm
-- atom. Server: seeded/updated by the datastore's changedCallbacks. Client:
-- `atom` is nil until the first sync lands.

-- ONE canonical way to name an instance, shared with everything else that
-- keys by instance -- util/extra-features/status-effect-handler is the other
-- one today. Hand-rolling `{user_id}` here would work and would drift: two
-- systems naming the same player differently is a bug that only appears when
-- something tries to correlate them.
--
-- get_instance_id is pure for a Player (it returns `?plr@<UserId>` without
-- writing an attribute), so this is safe to call on the client, where minting
-- an id would be a local-only write that never replicates and never gets
-- corrected.
function key_for(player: Player): string
	return `.PLAYER_DATA/{get_instance_id(player)}`
end

if RunService:IsClient() then
	const atom = charm.atom(nil :: Schema?)
	sync_registry.register(key_for(Players.LocalPlayer), atom)

	return table.freeze {
		atom = atom,
	}
end

const atoms: { [Player]: (Schema?) -> Schema? } = {}

function set(player: Player, data: Schema)
	-- The final save on unload fires changedCallbacks after the player is gone.
	-- Re-creating the atom here would resurrect an entry that nothing clears
	-- again — sync_registry.detach has already run — pinning the Player and
	-- their whole save in memory for the life of the server.
	if player.Parent == nil then
		return
	end
	local atom = atoms[player]
	if not atom then
		atom = charm.atom(nil :: Schema?)
		atoms[player] = atom
		sync_registry.register_for_player(player, key_for(player), atom)
	end
	atom(deep_copy(data) :: any)
end

function get(player: Player): Schema?
	const atom = atoms[player]
	return atom and (atom :: any)()
end

function clear(player: Player)
	atoms[player] = nil
end

return table.freeze {
	set = set,
	get = get,
	clear = clear,
}
