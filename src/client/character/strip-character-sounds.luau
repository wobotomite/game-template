const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const observe_character = require(ReplicatedStorage.Util.observers["observe-character"])

-- Silence Roblox's stock character sounds. OPT-IN:
--
--   require(ReplicatedStorage.Client.character["strip-character-sounds"]).init()
--
-- A module with an `init` rather than a script that runs itself, because a
-- template that silenced the default footsteps on boot and shipped no
-- replacement would just be a quiet game. Call it once you have your own.
--
-- The engine's RbxCharacterSounds CoreScript builds a set of Sounds under
-- every HumanoidRootPart -- Running, Jumping, Landing, and the rest -- and
-- they are the same generic set every default Roblox experience ships with.
-- Two reasons they have to go, and the first one is not cosmetic:
--
--  1. The moment you play your OWN per-material footsteps, the stock Running
--     loop is a second footstep system running out of phase with yours, on a
--     recording of a completely different floor. That is not "extra
--     footsteps", it is a flam on every stride.
--  2. Everything else in the set is a cue a game usually wants to stage
--     itself. `Died` in particular tends to fire underneath whatever death
--     sequence you have written.
--
-- EVERY character, not just the local player's: another player's stock Running
-- loop is just as audible from here as your own.
--
-- Alternative considered: shadowing the CoreScript by putting an empty script
-- named RbxCharacterSounds in StarterPlayerScripts. That stops the Sounds
-- being created at all, which is tidier, but it depends on name-shadowing
-- behaviour this project has not verified and it means a new StarterPlayer
-- branch in the Rojo tree. This works regardless of how or when the engine
-- decides to build them.

-- The stock set, by name. Listed explicitly rather than clearing every Sound
-- under the root: positional audio is normally parented to root parts --
-- footsteps do exactly that -- so a blanket sweep would eat your own cues
-- along with the engine's.
const STOCK: { [string]: true } = table.freeze {
	Climbing = true,
	Died = true,
	FreeFalling = true,
	GettingUp = true,
	Jumping = true,
	Landing = true,
	Running = true,
	Splash = true,
	Swimming = true,
}

function silence(child: Instance)
	if not child:IsA "Sound" or not STOCK[child.Name] then
		return
	end
	-- Muted and stopped rather than destroyed. The CoreScript holds references
	-- to these and drives them by name; destroying them out from under it
	-- risks an error inside code this game does not own and cannot patch,
	-- whereas a zero volume is something it never reads back. The instances
	-- are inert and cost nothing.
	const sound = child :: Sound
	sound.Volume = 0
	sound.Playing = false
	-- The CoreScript sets Volume once at setup, so ordering matters: if this
	-- ran first, its write would be overwritten. Re-asserting on change makes
	-- the order irrelevant and also covers any future cue it decides to fade.
	sound:GetPropertyChangedSignal("Volume"):Connect(function()
		if sound.Volume ~= 0 then
			sound.Volume = 0
		end
	end)
end

function watch(character: Model): (() -> ())?
	-- Present on spawn for a character that streamed in already set up...
	const root = character:FindFirstChild "HumanoidRootPart"
	if root then
		for _, child in root:GetChildren() do
			silence(child)
		end
	end
	-- ...and the usual case, where the CoreScript builds them a beat after the
	-- character arrives. Watching the CHARACTER rather than the root part
	-- means this does not have to race the root existing either.
	const added = character.DescendantAdded:Connect(silence)
	for _, descendant in character:GetDescendants() do
		silence(descendant)
	end
	return function()
		added:Disconnect()
	end
end

local started = false
function init()
	if started then
		return
	end
	started = true
	observe_players(function(player: Player)
		return observe_character(player, watch)
	end)
end

return table.freeze {
	init = init,
}
