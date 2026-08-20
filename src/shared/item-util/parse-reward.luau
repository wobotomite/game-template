local ReplicatedStorage = game:GetService "ReplicatedStorage"

local currencies = require(ReplicatedStorage.Shared.records.currencies)

export type CurrencyKey = keyof<typeof(currencies)>

-- Adding a new reward kind: require its record table above, add a param here,
-- and loop over its components below to extend the RewardString union.
type function RewardStringOf(c: type)
	local ret_union = types.unionof(types.string)

	local function add_prefix(prefix: string, keyval: string)
		ret_union = types.unionof(ret_union, types.singleton(`{prefix}/{keyval}`))
	end

	for _, comp in c:components() do
		local key = comp:value()
		if type(key) == "string" then
			add_prefix("currency", key)
		end
	end

	return ret_union
end

export type RewardString = RewardStringOf<CurrencyKey>

@native
function parse_reward(s: RewardString | ""): {
	read amount: number,
	read kind: "currency",
	read value: string,
}
	local result = s:split "/"

	assert(#result >= 2, `INVALID SIZE - {s}`)
	return table.freeze {
		amount = tonumber(result[3]) or 1,
		kind = result[1] :: never,
		value = result[2],
	}
end

return parse_reward
