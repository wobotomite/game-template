local Players = game:GetService "Players"

const cache = require(script.Parent.cache)
return cache(function(uid: number | User)
	return Players:GetNameFromUserIdAsync(uid)
end)
