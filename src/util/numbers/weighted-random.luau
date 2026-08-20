const ReplicatedStorage = game:GetService "ReplicatedStorage"

const reduce_number_array = require(ReplicatedStorage.Util.tables["reduce-number-array"])

const rng = Random.new()

export type WeightTable<K = any> = {
	[K]: number,
}

export type LookupTable<T> = {
	alias: { number },
	prob: { number },
	num_weights: number,
	weights: { number },
	value_lookup: { [number]: any }?,
}

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
	const weight_array, value_lookup = build_array_and_lookup(weights :: any)
	const num_weights = #weight_array
	const sum = reduce_number_array(weight_array)
	const avg_x = num_weights / sum
	const norm_weights = table.create(num_weights) :: { number }
	const small_stack, large_stack = table.create(num_weights) :: { number }, table.create(num_weights) :: { number }

	for i = 1, num_weights do
		const wgt = weight_array[i]
		const norm = wgt * avg_x
		norm_weights[i] = norm
		if norm < 1 then
			table.insert(small_stack, i)
		else
			table.insert(large_stack, i)
		end
	end

	local prob, alias = table.create(num_weights, 1) :: { number }, table.create(num_weights) :: { number }
	while small_stack[1] and large_stack[1] do
		const small, large = table.remove(small_stack) :: number, table.remove(large_stack) :: number
		prob[small] = norm_weights[small]
		alias[small] = large

		const norm_large = norm_weights[large] + norm_weights[small] - 1
		norm_weights[large] = norm_large

		if norm_large < 1 then
			table.insert(small_stack, large)
		else
			table.insert(large_stack, large)
		end
	end

	const ret = table.freeze {
		alias = alias,
		prob = prob,
		num_weights = num_weights,
		weights = weight_array,
		value_lookup = value_lookup,
	}

	return ret
end

function redistribute_by_luck(weights: { number }, luck: number): ({ number }, number)
	const exponent = 1 / luck
	const adjusted = table.create(#weights) :: { number }
	local sum = 0
	for i, weight in weights do
		const adj = weight ^ exponent
		adjusted[i] = adj
		sum += adj
	end
	return adjusted, sum
end

function sample<T>(aliasTable: LookupTable<T>, luck: number?): keyof<T>
	local result: number
	if luck == nil or luck == 1 then
		const rand = rng:NextInteger(1, aliasTable.num_weights)
		result = if rng:NextNumber() < aliasTable.prob[rand] then rand else aliasTable.alias[rand]
	else
		const adjusted, sum = redistribute_by_luck(aliasTable.weights, luck)
		const roll = rng:NextNumber() * sum
		local cumulative = 0
		result = aliasTable.num_weights
		for i, weight in adjusted do
			cumulative += weight
			if roll < cumulative then
				result = i
				break
			end
		end
	end

	const lookup = aliasTable.value_lookup
	return lookup and lookup[result] or result :: any
end

return table.freeze {
	build = build,
	sample = sample,
}
