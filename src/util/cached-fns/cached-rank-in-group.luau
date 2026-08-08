const GroupService = game:GetService "GroupService"

const cache = require(script.Parent.cache)
return cache(function(uid: number | User)
	return GroupService:GetRolesInGroupAsync(uid, game.CreatorId)
end, 5 * 60)
