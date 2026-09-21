local DataStoreService = game:GetService "DataStoreService"
local Players = game:GetService "Players"
local ReplicatedStorage = game:GetService "ReplicatedStorage"
local RunService = game:GetService "RunService"

local migrations = require(script.migrations)
local lyra = require(ReplicatedStorage.Packages.lyra)
local datastore_schema = require(ReplicatedStorage.Shared.datastore["datastore-schema"])
local datastore_template = require(ReplicatedStorage.Shared.datastore["datastore-template"])
local player_data = require(ReplicatedStorage.Shared.services["player-data"])
local leaderboards = require(script.Parent.Parent.leaderboards.service)

type Schema = typeof(datastore_schema:type())

-- In Studio without "Allow Studio Access to API Services", every DataStore
-- call 403s; fall back to lyra's in-memory mock so gameplay stays testable
-- (nothing persists between sessions in that mode).
local use_mock = false
if RunService:IsStudio() then
	local ok = pcall(function()
		DataStoreService:GetDataStore("__api_access_probe"):GetAsync "probe"
	end)
	use_mock = not ok
	if use_mock then
		warn "[datastore] Studio API access unavailable — using lyra's mock store (no persistence)"
	end
end

-- THE LEADERBOARD HANDSHAKE lives in this file, because this is the only place
-- that knows when a player's data has actually been WRITTEN.
--
-- `src/server/leaderboards/service.luau` must never publish a score that is not
-- saved (its header says why: a board cannot be rolled back and a save can), so
-- it needs telling two different things -- "this changed" and "this is durable"
-- -- and nothing outside lyra can tell those apart. Hence the three pieces
-- below: the changed callback, the wrappers around `save` / `unload` / `close`,
-- and the checkpoint the boards call to force a save.
--
-- The last snapshot lyra published for each loaded player, kept because `unload`
-- and `close` have to tell the boards what was saved AFTER lyra has released
-- the session and will not hand it over any more.
local profiles: { [number]: Schema } = {}
-- Sessions this server currently owns. A snapshot for a key that is not active
-- is one from a session that has already ended, and must not be re-published.
local active: { [number]: boolean } = {}
local closing = false

local store = lyra.createPlayerStore<<typeof(datastore_schema:type())>> {
	name = "PlayerData",
	useDSSLocking = true,
	useMock = use_mock,
	template = datastore_template(),
	migrationSteps = migrations :: never,
	schema = function(r)
		local s, e = datastore_schema:matches(r)
		return s, if e then e:formatErr() else nil
	end,
	changedCallbacks = {
		function(key, new_data, old_data)
			local user_id = tonumber(key) or 0
			if old_data == nil then
				-- THE FIRST CHANGE FOR A KEY IS THE LOAD, and what came back out
				-- of the DataStore is durable by definition -- this is how a
				-- returning player's existing scores reach the boards at all.
				active[user_id] = true
				leaderboards.confirm_saved(user_id, new_data)
			else
				-- Every later change is in memory only until something saves it.
				leaderboards.queue(user_id, new_data)
			end
			if active[user_id] and not closing then
				profiles[user_id] = new_data
			end
			local player = Players:GetPlayerByUserId(user_id)
			if player then
				player_data.set(player, new_data)
			end
		end,
	},
}

-- The three wrappers are set ON THE STORE TABLE, which shadows lyra's own
-- methods for anything that calls them through `self`. That is deliberate and
-- load-bearing: `saveAsync` is `self:save(player):expect()` and `closeAsync` is
-- `self:close():expect()` inside lyra, so wrapping `save` and `close` covers the
-- yielding forms too -- including the ones this template's own code calls.
local wrapped = store :: any

local save = store.save
wrapped.save = function(self: lyra.PlayerStore<Schema>, player: Player)
	-- The snapshot is taken BEFORE the save rather than after, so that what is
	-- confirmed is at worst behind what was written -- never ahead of it. A
	-- change landing between these two lines is simply confirmed by the next
	-- save.
	return self:get(player):andThen(function(snapshot)
		return save(self, player):andThen(function()
			leaderboards.confirm_saved(player.UserId, snapshot)
		end)
	end)
end

local unload = store.unload
wrapped.unload = function(self: lyra.PlayerStore<Schema>, player: Player)
	local user_id = player.UserId
	-- Read and cleared FIRST: the session is over either way, and a changed
	-- callback arriving during the unload must not put it back.
	local snapshot = profiles[user_id]
	active[user_id] = nil
	profiles[user_id] = nil
	return unload(self, player)
		:andThen(function()
			-- lyra saves before releasing the session, so a clean unload makes
			-- the last snapshot durable.
			if snapshot then
				leaderboards.confirm_saved(user_id, snapshot)
			end
		end)
		:finally(function()
			-- Runs whether the unload succeeded or not, and it is the failure
			-- that matters: anything queued for this player that never reached
			-- `confirm_saved` is rolled back here rather than published.
			leaderboards.discard_unsaved(user_id)
		end)
end

local close = store.close
wrapped.close = function(self: lyra.PlayerStore<Schema>)
	closing = true
	-- Taken and cleared before the close, for the same reason as `unload`: the
	-- close writes every open session, and each of those fires a changed
	-- callback that would otherwise refill these tables as it went.
	local snapshots = table.clone(profiles)
	table.clear(profiles)
	table.clear(active)
	return close(self):andThen(function()
		for user_id, snapshot in snapshots do
			leaderboards.confirm_saved(user_id, snapshot)
		end
	end)
end

-- "Save this player right now, and tell me whether you did." Called by the
-- board worker when a score is due to be written but has not been confirmed
-- saved yet -- the save it forces is what moves the score into `confirmed`,
-- through the wrapper above.
--
-- Returning false is a real answer, not a failure: the player has left, or
-- their session is not ours, or the server is closing and the close is already
-- saving everything. The score stays pending and is retried.
leaderboards.set_checkpoint(function(user_id: number): boolean
	local player = Players:GetPlayerByUserId(user_id)
	if not player or not active[user_id] or closing then
		return false
	end
	store:saveAsync(player)
	return true
end)

return store
