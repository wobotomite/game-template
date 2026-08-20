local ReplicatedStorage = game:GetService "ReplicatedStorage"

local currencies = require(ReplicatedStorage.Shared.records.currencies)
local parse_reward = require(script.Parent["parse-reward"])

export type return_type = {
	name: string,
	type: string,
	display_name: string,
	amount: number,
}

return function(s: parse_reward.RewardString): return_type
	local parsed = parse_reward(s)
	local data
	if parsed.kind == "currency" then
		data = currencies[parsed.value]
	else
		error "INVALID KIND!"
	end
	return {
		name = parsed.value,
		type = parsed.kind,
		display_name = data.name,
		amount = tonumber(parsed.amount) or 0,
	}
end
