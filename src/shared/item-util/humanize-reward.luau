local ReplicatedStorage = game:GetService "ReplicatedStorage"

local currencies = require(ReplicatedStorage.Shared.records.currencies)
local format_color = require(ReplicatedStorage.Util.strings["format-color"])
local format_number = require(ReplicatedStorage.Util.strings["comma-number"])
local get_reward_information = require(script.Parent["get-reward-information"])
local parse_reward = require(script.Parent["parse-reward"])

return function(str: parse_reward.RewardString)
	local info = get_reward_information(str)
	local display_name = currencies[info.name].name
	local color = currencies[info.name].color
	local amt = info.amount
	local sign = if math.sign(amt) ~= -1 then "+" else "-"

	return format_color(`{sign} {format_number(amt)} {display_name}`, color)
end
