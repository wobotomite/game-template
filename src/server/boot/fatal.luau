const Players = game:GetService "Players"

-- Last resort for errors the game cannot recover from: boot failures, a level
-- that won't build, run state that can't advance. Recoverable problems belong
-- in a pcall at the call site — this is for "the server is wrong, and every
-- second it stays up makes things worse". Tripping it logs the crash and
-- empties the server, because a session that never progresses is a worse
-- experience than an honest kick.
--
-- Use `guard` around anything at boot whose failure would leave the server
-- half-built. The alternative is what a bare require does: the failing script
-- dies, every other script carries on, and the game runs in a state nobody
-- designed — no saves, no level, no way for a player to tell.

const KICK_MESSAGE = "The server hit a problem it couldn't recover from, so the session was shut down."
	.. " It's been logged — please rejoin!"

local tripped = false

local function trip(context: string, err: unknown, trace: string?)
	if tripped then
		return
	end
	tripped = true

	-- error (not warn) so the crash lands in the Creator Hub error report,
	-- carrying the traceback from the failure site when we have one.
	const detail = if trace and trace ~= "" then `\n{trace}` else ""
	task.spawn(error, `[fatal/{context}] {tostring(err)}{detail}`)

	for _, player in Players:GetPlayers() do
		pcall(player.Kick, player, KICK_MESSAGE)
	end
	-- The server is dead; anyone who slips in mid-shutdown goes home too.
	Players.PlayerAdded:Connect(function(player)
		pcall(player.Kick, player, KICK_MESSAGE)
	end)
end

-- Run fn(...); if it throws, trip the fatal handler with its traceback.
local function guard(context: string, fn: (...any) -> ...any, ...: any)
	xpcall(fn, function(err)
		trip(context, err, debug.traceback("", 2))
	end, ...)
end

return table.freeze {
	trip = trip,
	guard = guard,
}
