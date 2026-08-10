local Players = game:GetService "Players"

const cache_function = require(script.Parent["cache-function"])

return cache_function(function(uid: number | User)
	return Players:GetNameFromUserIdAsync(uid)
end)
