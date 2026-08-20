local ReplicatedStorage = game:GetService "ReplicatedStorage"

local datastore_schema = require(ReplicatedStorage.Shared.datastore["datastore-schema"])

return @native function(): typeof(datastore_schema:type())
	return {
		currency = {
			coins = 0,
		},
	}
end
