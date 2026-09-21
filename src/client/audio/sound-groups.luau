const ReplicatedStorage = game:GetService "ReplicatedStorage"
const SoundService = game:GetService "SoundService"

const BUS_VOLUME = require(ReplicatedStorage.Shared.settings).audio.BUS_VOLUME

-- Named SoundGroups, created on first ask.
--
-- Without these every sound in the game is on one fader: the music sits at
-- whatever volume each track was mastered at, the ambience bed sits under it
-- at whatever volume it was recorded at, and the only way to make a capture
-- chime audible over both is to keep pushing the chime up. Grouping is what
-- makes "duck the music while the boss is talking" or a settings slider a
-- property write instead of a sweep of every call site.
--
-- Group volumes MULTIPLY with the per-sound Volume, so a group's starting
-- volume is the mix BETWEEN families of sound and the per-sound volume is the
-- mix within one. `settings.audio.BUS_VOLUME` holds the first half.
--
-- EVERY BUS AT 1 IS NOT A NEUTRAL DEFAULT, which is what it looks like. It puts
-- a continuous bed and a one-frame cue at the same level, and the only fix
-- available at a call site is to push the cue up -- which is then too loud the
-- moment the bed stops. The starting mix belongs here, once, in data.

const groups: { [string]: SoundGroup } = {}

function get(name: string): SoundGroup
	const existing = groups[name]
	if existing then
		return existing
	end
	-- Studio reloads and a second require from another script must not end up
	-- with two groups of the same name routing half the sounds each.
	const found = SoundService:FindFirstChild(name)
	if found and found:IsA "SoundGroup" then
		groups[name] = found
		return found
	end
	const group = Instance.new "SoundGroup"
	group.Name = name
	-- `or 1` rather than an assert: a bus a game invents for itself and never
	-- adds to the settings table should play at unity, not refuse to exist.
	group.Volume = BUS_VOLUME[name] or 1
	group.Parent = SoundService
	groups[name] = group
	return group
end

return table.freeze {
	get = get,
	-- The buses. Named as constants so a typo is a nil index at require time
	-- rather than a silent extra group nothing else routes to.
	MUSIC = "Music",
	AMBIENCE = "Ambience",
	SFX = "SFX",
	-- UI is its own bus rather than part of SFX because it is the one family
	-- that must stay audible when the world is ducked -- a menu opened during a
	-- boss fight still has to click.
	UI = "UI",
}
