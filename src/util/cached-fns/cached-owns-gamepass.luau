const MarketplaceService = game:GetService "MarketplaceService"

const cache = require(script.Parent.cache)
return cache(function(uid: number | User, gamepass: number)
	return MarketplaceService:UserOwnsGamePassAsync(uid, gamepass)
end, 120)
