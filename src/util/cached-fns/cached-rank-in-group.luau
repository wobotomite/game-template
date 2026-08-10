const GroupService = game:GetService "GroupService"

const cache_function = require(script.Parent["cache-function"])

return cache_function(function(uid: number | User)
	return GroupService:GetRolesInGroupAsync(uid, game.CreatorId)
end, 5 * 60)
