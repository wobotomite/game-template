const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const player_data = require(ReplicatedStorage.Shared.services["player-data"])

-- Yields until the local player is actually "in": saved data has synced down
-- and a character exists. UI scripts call this before parenting anything to
-- PlayerGui so nothing flashes on screen mid-load.
-- Polled rather than driven off the atom + CharacterAdded, deliberately: an
-- event-driven wait has to hand-roll a coroutine resume, and getting that
-- subtly wrong hangs the client on the loading screen forever. A poll cannot
-- fail that way, so the only thing worth tuning is the interval.
--
-- 0.05 rather than 0.2: every UI script gates on this, so the old interval
-- could leave up to 200ms of dead time on screen after the data had actually
-- landed. Twenty wakeups a second, only while loading, costs nothing.
return function()
	while player_data.atom() == nil or Players.LocalPlayer.Character == nil do
		task.wait(0.05)
	end
end
