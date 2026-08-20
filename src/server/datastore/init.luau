local ReplicatedStorage = game:GetService "ReplicatedStorage"

local migrations = require(script.migrations)
local lyra = require(ReplicatedStorage.Packages.lyra)
local datastore_schema = require(ReplicatedStorage.Shared.datastore["datastore-schema"])
local datastore_template = require(ReplicatedStorage.Shared.datastore["datastore-template"])

return lyra.createPlayerStore<<typeof(datastore_schema:type())>> {
	name = "PlayerData",
	useDSSLocking = true,
	template = datastore_template(),
	migrationSteps = migrations :: never,
	schema = function(r)
		local s, e = datastore_schema:matches(r)
		return s, e:formatErr()
	end,
}
