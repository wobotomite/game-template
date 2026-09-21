const BadgeService = game:GetService "BadgeService"
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const badges = require(ReplicatedStorage.Shared.assets).badges
const rules = require(ReplicatedStorage.Shared.settings).badges

const lifecycle = require(script.Parent.Parent.data.lifecycle)

-- Badge awards, made safe to call from anywhere and as often as you like.
--
-- WHY THIS IS NOT JUST `AwardBadgeAsync`. That call yields, throws on a web
-- failure, and the engine never retries it: a badge dropped by a blip is gone
-- until the player happens to hit the same milestone again, which for a
-- one-time badge is never. It is also rate limited, so a milestone that fires
-- on a loop -- "reached 100 coins", checked every time coins change -- turns
-- into a stream of duplicate calls the moment it is true.
--
-- So `award` is fire-and-forget: it returns immediately, dedupes the awards
-- already in flight for that player, checks `UserHasBadgeAsync` before spending
-- an award call, and retries a failure a couple of times.

-- Every key in `assets.badges`. Listed as a union rather than typed `string` so
-- a misspelled badge name is an analyzer error at the CALL SITE, which is the
-- only place anyone would notice: a bad key at runtime looks exactly like a
-- badge that is simply not configured yet.
export type Badge = "WELCOME"

-- Awards in flight, per player, so the same badge asked for twice in a frame
-- costs one web call.
const pending: { [Player]: { [number]: boolean } } = {}
-- Badge keys already warned about, so an unset id warns ONCE per server rather
-- than on every call of a milestone that fires in a loop.
const unconfigured: { [string]: boolean } = {}

function award(player: Player, badge: Badge)
	const id = badges[badge]
	if id == nil or id == 0 then
		if not unconfigured[badge] then
			unconfigured[badge] = true
			warn(`[badges] assets.badges.{badge} is not set; nothing was awarded`)
		end
		-- DEGRADE, do not error. A template ships with unset ids by definition,
		-- and a game part way through configuring them should still run.
		return
	end

	-- `player.Parent ~= Players` rather than `== nil`: a Player being torn down
	-- is reparented before it is destroyed, and awarding to one is a guaranteed
	-- wasted call.
	if player.Parent ~= Players then
		return
	end

	local active = pending[player]
	if not active then
		active = {}
		pending[player] = active
	end
	if active[id] then
		return
	end
	active[id] = true

	-- Captured, because `pending[player]` may already have been cleared by the
	-- time this thread finishes and we must not resurrect it for a player who
	-- has left.
	const awards = active
	task.spawn(function()
		for attempt = 1, rules.ATTEMPTS do
			if player.Parent ~= Players then
				break
			end
			const ok, result = pcall(function(): boolean
				-- ASK FIRST. `UserHasBadgeAsync` has the looser rate limit of
				-- the two, and a player who already has the badge -- the common
				-- case for anything checked at join -- costs nothing further.
				if BadgeService:UserHasBadgeAsync(player.UserId, id) then
					return true
				end
				if player.Parent ~= Players then
					return false
				end
				return BadgeService:AwardBadgeAsync(player.UserId, id)
			end)
			if ok and result then
				break
			end
			if attempt == rules.ATTEMPTS then
				warn(`[badges] could not award {badge} to {player.Name}: {tostring(result)}`)
			else
				task.wait(rules.RETRY_SECONDS)
			end
		end
		awards[id] = nil
		if next(awards) == nil then
			pending[player] = nil
		end
	end)
end

-- SEAM. Called once per player after their save has loaded (see the fan-out in
-- `src/server/data/lifecycle.luau`), so a game can hand out the badges a player
-- has already earned -- a badge added after launch, or one whose award call
-- failed on a previous session.
--
-- Deliberately near-empty: what counts as earned is the one thing a template
-- cannot know. The pattern is a line per badge reading the save, e.g.
-- `if data.progress.best_score >= 100 then award(player, "HIGH_SCORE") end`.
-- Awards are idempotent, so being generous here is free.
function refresh(player: Player)
	-- Given out to everyone who plays; the worked example for the seam above.
	award(player, "WELCOME")
end

local started = false
function start()
	if started then
		return
	end
	started = true

	-- AFTER THE SAVE, not on join: `refresh` is meant to read progress, and at
	-- `PlayerAdded` there is nothing to read. Registering here rather than
	-- having the lifecycle call this service keeps the dependency pointing one
	-- way -- services know about the lifecycle, the lifecycle knows about none
	-- of them.
	lifecycle.on_loaded(refresh)
end

return table.freeze {
	start = start,
	award = award,
	refresh = refresh,
}
