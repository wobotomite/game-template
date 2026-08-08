const BadgeService = game:GetService "BadgeService"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const cached = {}
function cached_user_has_badge(p: Player, badge_id: number)
	if cached[p] and cached[p][badge_id] then
		return true
	end
	const success, res = pcall(BadgeService.UserHasBadgeAsync, BadgeService, p.UserId, badge_id)
	if success and res then
		cache_owned(p, badge_id)
		return res
	end
	return false
end
function cache_owned(p, badge)
	if not cached[p] then
		cached[p] = {}
	end
	cached[p][badge] = true
end

function grant(p: Player, badge_id: number)
	if cached_user_has_badge(p, badge_id) then
		return false
	end

	if BadgeService:AwardBadgeAsync(p.UserId, badge_id) then
		cache_owned(p, badge_id)
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
	grant_if = grant_if,
	grant = grant,
}
