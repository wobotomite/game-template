local ReplicatedStorage = game:GetService "ReplicatedStorage"

local alert = require(ReplicatedStorage.Shared.services.alert)
local currencies = require(ReplicatedStorage.Shared.records.currencies)
local humanize_reward = require(ReplicatedStorage.Shared["item-util"]["humanize-reward"])
local parse_reward = require(ReplicatedStorage.Shared["item-util"]["parse-reward"])

local datastore = require(script.Parent.datastore)

local function fire_alert(player: Player, reward: string)
	alert.send_to(player, `GOT {humanize_reward(reward :: parse_reward.RewardString)}`)
end

-- Applies a reward string (e.g. "currency/coins/100") to a player's saved data.
-- Returns the datastore:update promise, resolving to whether data actually changed.
local function award(player: Player, reward: parse_reward.RewardString)
	local result = parse_reward(reward)
	return datastore:update(player, function(data)
		if result.kind == "currency" then
			assert(currencies[result.value], "INVALID CURRENCY")

			local casted_curr = data.currency :: any
			local current: number = casted_curr[result.value] or 0
			casted_curr[result.value] = current + result.amount

			fire_alert(player, reward)
			return true
		end

		return false
	end)
end

return award
