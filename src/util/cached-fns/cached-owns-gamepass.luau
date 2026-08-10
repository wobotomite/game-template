const MarketplaceService = game:GetService "MarketplaceService"

const cache_function = require(script.Parent["cache-function"])

return cache_function(function(uid: number | User, gamepass: number)
	return MarketplaceService:UserOwnsGamePassAsync(uid, gamepass)
end, 120)
