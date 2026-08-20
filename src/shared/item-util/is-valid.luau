local ReplicatedStorage = game:GetService "ReplicatedStorage"

local currencies = require(ReplicatedStorage.Shared.records.currencies)
local parse_reward = require(script.Parent["parse-reward"])

return function(s: string)
	local success, result = pcall(parse_reward, s)
	if not success then
		return false
	end

	if result.kind == "currency" and (not currencies[result.value] or not result.amount) then
		return false
	end

	return true
end
