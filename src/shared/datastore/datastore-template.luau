local ReplicatedStorage = game:GetService "ReplicatedStorage"

local datastore_schema = require(ReplicatedStorage.Shared.datastore["datastore-schema"])

-- The starting profile, built as a FRESH TABLE on every call.
--
-- A shared constant would be handed to lyra and then written into by the first
-- player whose profile was created from it, so the next new player would start
-- with the previous one's progress.
return @native function(): typeof(datastore_schema:type())
	return {
		currency = {
			coins = 0,
		},

		commerce = {
			granted = {},
		},

		progress = {
			best_score = 0,
		},

		daily = {
			streak = 0,
			last_day = 0,
			best_streak = 0,
		},
	}
end
