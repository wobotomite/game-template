const MarketplaceService = game:GetService "MarketplaceService"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const promise = require(ReplicatedStorage.Packages["typed-promise"])
const vide = require(ReplicatedStorage.Packages.vide)

return function(product_id: number, info_type: Enum.InfoType)
	const price = vide.source(0)
	-- The lookup outlives the scope by up to 10 retries x 5 s. A shop closed
	-- before the price arrived must not have its (destroyed) source written, and
	-- must not start the lookup at all if it closed within the defer.
	local alive = true
	vide.cleanup(function()
		alive = false
	end)
	task.defer(function()
		if not alive then
			return
		end
		promise
			.retryWithDelay(function()
				const p = MarketplaceService:GetProductInfoAsync(product_id, info_type).PriceInRobux
				if alive then
					price(p)
				end
				return p
			end, 10, 5)
			-- An unhandled rejection after the last retry is reported by the promise
			-- library as an anonymous error with no product id in it.
			:catch(function(err)
				warn(`[use-product-price] {product_id} price lookup failed: {err}`)
			end)
	end)
	return function()
		return price()
	end
end
