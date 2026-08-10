const BadgeService = game:GetService "BadgeService"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const cache_function = require(script.Parent["cache-function"])

const has_badge = cache_function(function(p: Player, badge_id: number)
	const has = BadgeService:UserHasBadgeAsync(p.UserId, badge_id)
	return has
end)

function grant(p: Player, badge_id: number)
	if has_badge(p, badge_id) then
		return false
	end
	if BadgeService:AwardBadgeAsync(p.UserId, badge_id) then
		has_badge:rm_entry(p, badge_id)
		return true
	end
	return false
end
function grant_if(condition: boolean, p: Player, badge_id: number)
	if condition then
		return grant(p, badge_id)
	end
	return false
end

return table.freeze {
	has_badge = has_badge,
	grant_if = grant_if,
	grant = grant,
}
