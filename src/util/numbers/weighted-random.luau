const ReplicatedStorage = game:GetService "ReplicatedStorage"

const reduce_number_array = require(ReplicatedStorage.Util.tables["reduce-number-array"])

const rng = Random.new()

export type WeightTable<K = any> = {
	[K]: number,
}

export type LookupTable<T> = {}

@native
function build_array_and_lookup<K>(weights: WeightTable<K>): ({ number }, { K }?)
	local numWeights = #weights
	local lastKey, lastWeight = next(weights, if numWeights ~= 0 then numWeights else nil)
	if lastKey == nil then
		return weights, nil
	end
	numWeights += 1
	local weightArray = table.move(weights, 1, numWeights, 1, table.create(numWeights) :: { number })
	local lookup = {
		[numWeights] = lastKey,
	}
	weightArray[numWeights] = lastWeight
	for key, weight in next, weights, lastKey do
		numWeights += 1
		weightArray[numWeights] = weight
		lookup[numWeights] = key
	end
	return weightArray, lookup
end

function build<T>(weights: T): LookupTable<T>
	const sum = reduce_number_array(weights)
	const index_lookup, value_lookup = build_array_and_lookup(weights)
	--
	const num_weights = #index_lookup
	const avg_x = num_weights / sum
	const norm_weights = table.create(num_weights) :: { number }
	const small_stack, large_stack = table.create(num_weights) :: { number }, table.create(num_weights) :: { number }

	for i = 1, index_lookup do
		const wgt = index_lookup[i]
		const norm = wgt * avg_x
		norm_weights[i] = norm
		if norm < 1 then
			table.insert(small_stack, i)
		else
			table.insert(large_stack, i)
		end
	end

	const max_size = math.max(num_weights, table.maxn(large_stack), table.maxn(small_stack))

	local prob, alias = table.create(max_size, 1) :: { number }, table.create(max_size) :: { number }
	while small_stack[1] and large_stack[1] do
		const small, large = table.remove(small_stack) :: number, table.remove(large_stack) :: number
		prob[small] = norm_weights[small]
		alias[small] = large

		const normLarge = norm_weights[large] + norm_weights[small] - 1
		normWeights[large] = normLarge

		if normLarge < 1 then
			table.insert(small_stack, large)
		else
			table.insert(large_stack, large)
		end
	end

	const ret = table.freeze {
		alias = alias,
		prob = prob,
		num_weights = num_weights,
		value_lookup = value_lookup,
	}

	return ret
end

function sample<T>(aliasTable: LookupTable<T>): keyof<T>
	local rand = rng:NextInteger(1, aliasTable.n)
	local result = if rng:NextNumber() < aliasTable.prob[rand] then rand else aliasTable.alias[rand]
	local lookup = aliasTable.lookup

	return lookup and lookup[result] or result :: any
end

return table.freeze {
	build = build,
	sample = sample,
}
