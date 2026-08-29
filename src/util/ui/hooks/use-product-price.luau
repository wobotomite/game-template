const MarketplaceService = game:GetService "MarketplaceService"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const promise = require(ReplicatedStorage.Packages["typed-promise"])
const vide = require(ReplicatedStorage.Packages.vide)

return function(product_id: number, info_type: Enum.InfoType)
	const price = vide.source(0)
	task.defer(function()
		promise.retryWithDelay(function()
			const p = MarketplaceService:GetProductInfoAsync(product_id, info_type).PriceInRobux
			price(p)
			return p
		end, 10, 5)
	end)
	return function()
		return price()
	end
end
