local DataStoreService = game:GetService "DataStoreService"
local Players = game:GetService "Players"
local ReplicatedStorage = game:GetService "ReplicatedStorage"
local RunService = game:GetService "RunService"

local migrations = require(script.migrations)
local lyra = require(ReplicatedStorage.Packages.lyra)
local datastore_schema = require(ReplicatedStorage.Shared.datastore["datastore-schema"])
local datastore_template = require(ReplicatedStorage.Shared.datastore["datastore-template"])
local player_data = require(ReplicatedStorage.Shared.services["player-data"])

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

return lyra.createPlayerStore<<typeof(datastore_schema:type())>> {
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
		function(key, new_data)
			local player = Players:GetPlayerByUserId(tonumber(key) or 0)
			if player then
				player_data.set(player, new_data)
			end
		end,
	},
}
