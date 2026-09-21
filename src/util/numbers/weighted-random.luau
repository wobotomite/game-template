const ReplicatedStorage = game:GetService "ReplicatedStorage"

const reduce_number_array = require(ReplicatedStorage.Util.tables["reduce-number-array"])

-- Built on FIRST USE rather than at require time -- see `default_random`.
local rng: Random? = nil

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

-- The fallback generator for callers that do not bring their own, created
-- lazily so that REQUIRING this module costs nothing. `build` is the half most
-- consumers use -- it is pure, and a lookup table is often built at load and
-- sampled from somewhere else entirely -- so seeding a generator on every
-- require was work done for nobody. It also detached the seed from require
-- ORDER, which is a dependency nothing in a call site could have told you about.
--
-- Anything that needs a reproducible sequence passes its own Random to
-- `sample` and never reaches this at all; `tests/weighted-random.spec` does
-- exactly that.
function default_random(): Random
	local r = rng
	if not r then
		r = Random.new()
		rng = r
	end
	return r
end

-- Pick an index from a roll in [0, 1), by straight linear scan over the raw
-- weights. Deliberately NOT the alias method above: this is for the case where
-- the weights are different on every call -- a drop table re-weighted by the
-- player's luck, a spawn table filtered by what is already alive -- so the
-- O(n) build the alias method needs would be paid every time and never amortised.
-- Use `build` + `sample` when one weight table is sampled many times; use this
-- when it is sampled once.
--
-- The roll is supplied rather than drawn so the caller keeps control of the
-- generator: the same roll always gives the same index, which is what makes
-- this testable and what lets a server replay a client's pick.
--
-- `roll` is not normalised against `total` by the caller -- it is scaled here
-- -- and the final `return #weights` catches the float case where the
-- subtractions do not quite reach zero. A roll of exactly 1, or weights that
-- sum to zero, therefore land on the last index rather than on nothing.
function index_at(weights: { number }, roll: number): number
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local at = roll * total
	for index, weight in weights do
		at -= weight
		if at < 0 then
			return index
		end
	end
	return #weights
end

function sample<T>(aliasTable: LookupTable<T>, luck: number?, random: Random?): keyof<T>
	const r = random or default_random()
	local result: number
	-- `luck <= 0` takes the unweighted path too. The exponent below is
	-- `1 / luck`: zero makes it infinite (every weight under 1 becomes 0, every
	-- weight over 1 becomes inf, and the roll is NaN), and a negative one
	-- INVERTS the table, so a debuff that drove luck below zero made the rarest
	-- drop the most common. Neither errors.
	if luck == nil or luck == 1 or luck <= 0 then
		const rand = r:NextInteger(1, aliasTable.num_weights)
		result = if r:NextNumber() < aliasTable.prob[rand] then rand else aliasTable.alias[rand]
	else
		const adjusted, sum = redistribute_by_luck(aliasTable.weights, luck)
		const roll = r:NextNumber() * sum
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
	index_at = index_at,
}
