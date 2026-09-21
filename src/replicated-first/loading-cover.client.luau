const Players = game:GetService "Players"
const ReplicatedFirst = game:GetService "ReplicatedFirst"
const TeleportService = game:GetService "TeleportService"

const transition = require(ReplicatedFirst["transition-screen"])
const TRANSITION = require(ReplicatedFirst.TransitionSettings).transition
const TEXT = require(ReplicatedFirst.TransitionStrings).loading

-- THE FIRST THING THE PLAYER SEES. This is a LocalScript in ReplicatedFirst,
-- which the client runs before ReplicatedStorage has replicated and long
-- before any character exists -- so it puts a cover up immediately, and the
-- client boot takes it down when the game is actually ready to be looked at.
--
-- WITHOUT IT the player watches the game assemble itself: an empty baseplate,
-- then terrain, then a character dropping in, then panels appearing one by one
-- with placeholder numbers in them. None of that is broken and all of it looks
-- broken.
--
-- WHY THIS IS NOT IN `src/client`. Scripts under StarterPlayerScripts do not
-- run until the player's scripts have replicated, which is most of the wait
-- this covers. ReplicatedFirst is the only place a script can run early enough
-- to be in front of that, and the price is that nothing it requires may live
-- in ReplicatedStorage: no packages, no widget kit, no shared services. It
-- reads its numbers and its one line of text through the `Transition*` aliases
-- in `default.project.json`, which mount the shared data files a second time.
-- See the header of `src/replicated-first/transition-screen.luau` for what
-- being mounted twice does and does not mean.
--
-- THE HAND-OFF, both halves of it:
--
--   * `src/client/init.client.luau` sets the DISMISS_ATTRIBUTE attribute on
--     the ReplicatedFirst service once the player is in and the interface is
--     mounted. That is the normal path and the cover fades on it.
--   * FAILSAFE_SECONDS after this script starts, the cover takes itself down
--     regardless. A boot that never reaches the hand-off -- a profile that
--     will not load, an error thrown on the way -- must not leave the player
--     staring at a title card with no way to tell it from a slow connection.

const screen = transition.create("LoadingCover", TEXT.TITLE)

-- A TELEPORT ARRIVES WITH SOMEONE ELSE'S COVER ALREADY ON SCREEN: the gui the
-- departing place handed to `TeleportService:SetTeleportGui`. It is not parented
-- to anything this script owns and nothing else will ever remove it, so it
-- stays on top of this one for the rest of the session.
--
-- pcall'd because the call is only meaningful on an arriving client; asking for
-- it on a player who joined normally is not an error worth taking the cover
-- down for.
const ok, arriving = pcall(function()
	return TeleportService:GetArrivingTeleportGui()
end)
if ok and arriving then
	arriving:Destroy()
end

-- ReplicatedFirst runs before `Players.LocalPlayer` is populated, so this is a
-- real wait rather than a formality, and PlayerGui may not exist even after it.
while not Players.LocalPlayer do
	task.wait()
end
screen.gui.Parent = Players.LocalPlayer:WaitForChild "PlayerGui"

-- ONLY AFTER OURS IS UP. Removing the default screen first leaves a gap of
-- unobscured game between the two, which is the exact frame this file exists
-- to prevent.
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- Idempotent, because the two ways down can both happen: the failsafe fires
-- while the fade from a normal dismissal is still running.
local going = false

const function take_down()
	if going then
		return
	end
	going = true
	screen.fade(false)
	-- Destroyed rather than left faded out: a GroupTransparency of 1 still
	-- renders, still sinks input, and still runs the bar's RenderStepped loop
	-- for the rest of the session.
	task.delay(TRANSITION.FADE_SECONDS, screen.destroy)
end

-- READ, THEN LISTEN. The boot script is not supposed to be able to beat this
-- one -- ReplicatedFirst is first by definition -- but "supposed to" is not a
-- guarantee worth a permanently black screen, and checking the current value
-- before connecting costs one line and closes the race either way.
const DISMISS = TRANSITION.DISMISS_ATTRIBUTE

if ReplicatedFirst:GetAttribute(DISMISS) then
	take_down()
else
	local watch: RBXScriptConnection
	watch = ReplicatedFirst:GetAttributeChangedSignal(DISMISS):Connect(function()
		if ReplicatedFirst:GetAttribute(DISMISS) then
			watch:Disconnect()
			take_down()
		end
	end)
end

task.delay(TRANSITION.FAILSAFE_SECONDS, take_down)
