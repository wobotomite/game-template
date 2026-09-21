const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const player_data = require(ReplicatedStorage.Shared.services["player-data"])
const BOOT = require(ReplicatedStorage.Shared.settings).boot

-- Yields until the local player is actually "in": saved data has synced down
-- and a character exists. UI scripts call this before parenting anything to
-- PlayerGui so nothing flashes on screen mid-load.
--
-- Polled rather than driven off the atom + CharacterAdded, deliberately: an
-- event-driven wait has to hand-roll a coroutine resume, and getting that
-- subtly wrong hangs the client on the loading screen forever. A poll cannot
-- fail that way, so the only thing worth tuning is the interval.
--
-- THE THREE WAITS ARE SEPARATE, AND THE ORDER IS THE POINT. The one-line
-- version of this -- `while player_data.atom() == nil or
-- Players.LocalPlayer.Character == nil` -- carries two failures that are
-- invisible in Studio, where all three conditions come true at once:
--
--   LocalPlayer is nil early     A client script can run before Players has
--                                populated it, and `.Character` on nil throws
--                                out of the very call every UI script in the
--                                game is waiting on. So LocalPlayer is waited
--                                for FIRST, alone, and never indexed before.
--   the character wait is        A spawn that never completes then takes the
--   unbounded                    whole UI with it: no HUD, no menus, and a
--                                loading cover that never comes down. A player
--                                with no body and a working menu can at least
--                                SEE that something went wrong.
--
-- Only the character wait gets a deadline. Data is what the UI is made of --
-- mounting a currency counter before it lands is the flash this exists to
-- prevent -- so giving up on that one would defeat the purpose.
return function()
	while not Players.LocalPlayer do
		task.wait(BOOT.POLL_SECONDS)
	end
	const local_player = Players.LocalPlayer
	while player_data.atom() == nil do
		task.wait(BOOT.POLL_SECONDS)
	end
	const deadline = os.clock() + BOOT.SPAWN_WAIT_SECONDS
	while local_player.Character == nil and os.clock() < deadline do
		task.wait(BOOT.POLL_SECONDS)
	end
end
