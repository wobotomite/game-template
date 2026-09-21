const ReplicatedStorage = game:GetService "ReplicatedStorage"

const assets = require(ReplicatedStorage.Shared.assets)
const settings = require(ReplicatedStorage.Shared.settings)
const strings = require(ReplicatedStorage.Shared.strings)

-- Developer products, joined once at require time out of the three data files.
--
-- THIS IS THE WORKED EXAMPLE for the settings / assets / strings split. A
-- product is three unrelated things wearing one name: a SHAPE (what it grants,
-- which category it sits in) that a designer tunes, an ID that changes whenever
-- the product is recreated on the dashboard, and COPY that an editor rewrites.
-- Keeping them in one table means every one of those three people edits the
-- same file and reviews each other's diffs; keeping them apart means the join
-- has to live somewhere, and this is it.
--
-- The join is by KEY, so a row present in one file and missing from another is
-- an error AT BOOT rather than a nil description on a shop card three screens
-- in. That is the trade this file makes: a loud failure in Studio in exchange
-- for never shipping a half-configured product.
--
-- WHAT READS IT. The receipt service resolves an incoming `ProductId` through
-- `by_id`; a shop UI walks `list`; a "you cannot afford this" prompt asks
-- `pack_for` which bundle to offer. All three want the same frozen tables, so
-- they are built once here rather than per consumer.

export type Product = {
	key: string,
	-- `0` when the product has not been created on the dashboard yet. Such a
	-- product stays in `list` and `by_key` (a shop can still lay it out, greyed
	-- out) but is deliberately absent from `by_id`, so nothing can buy it.
	id: number,
	category: string,
	icon: string,
	name: string,
	description: string,
	-- Currency key -> amount, by the keys in `src/shared/records/currencies.luau`.
	grants: { [string]: number },
}

const list: { Product } = {}
const by_id: { [number]: Product } = {}
const by_key: { [string]: Product } = {}

for _, offer in settings.commerce.PRODUCTS do
	const copy = strings.commerce.PRODUCTS[offer.key]
	assert(copy ~= nil, `no strings.commerce.PRODUCTS entry for product "{offer.key}"`)
	const product: Product = table.freeze {
		key = offer.key,
		id = assets.products[offer.key] or 0,
		category = offer.category,
		icon = offer.icon,
		name = copy.name,
		description = copy.description,
		grants = offer.grants,
	}
	table.insert(list, product)
	by_key[product.key] = product
	if product.id > 0 then
		-- TWO PRODUCTS SHARING AN ID is the single worst typo possible in
		-- `assets.products`: the receipt service resolves by id, so one of the
		-- two silently grants the other's contents to every buyer, forever, and
		-- the only evidence is a support ticket. Assert at boot instead.
		assert(by_id[product.id] == nil, `duplicate product id {product.id}`)
		by_id[product.id] = product
	end
end

-- The smallest purchasable product that covers `shortfall` of `currency`, or
-- the largest one there is when none does.
--
-- WHY FALL BACK TO THE LARGEST rather than to nothing: a player 40 short with
-- no bundle that big is still better served by an offer than by a dead button.
-- Nil means the game genuinely sells nothing for that currency yet.
function pack_for(currency: string, shortfall: number): Product?
	local best: Product? = nil
	local largest: Product? = nil
	for _, product in list do
		const amount = product.grants[currency]
		if amount == nil or amount <= 0 or product.id <= 0 then
			continue
		end
		if largest == nil or amount > (largest.grants[currency] or 0) then
			largest = product
		end
		if amount >= shortfall and (best == nil or amount < (best.grants[currency] or 0)) then
			best = product
		end
	end
	return best or largest
end

return table.freeze {
	list = table.freeze(list),
	by_id = table.freeze(by_id),
	by_key = table.freeze(by_key),
	pack_for = pack_for,
}
