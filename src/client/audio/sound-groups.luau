const SoundService = game:GetService "SoundService"

-- Named SoundGroups, created on first ask.
--
-- Without these every sound in the game is on one fader: the music sits at
-- whatever volume each track was mastered at, the ambience bed sits under it
-- at whatever volume it was recorded at, and the only way to make a capture
-- chime audible over both is to keep pushing the chime up. Grouping is what
-- makes "duck the music while the boss is talking" or a settings slider a
-- property write instead of a sweep of every call site.
--
-- Group volumes MULTIPLY with the per-sound Volume, so every group starts at 1
-- and the mix stays where the call sites put it until something deliberately
-- moves a group.

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
	group.Volume = 1
	group.Parent = SoundService
	groups[name] = group
	return group
end

return table.freeze {
	get = get,
	-- The three buses. Named as constants so a typo is a nil index at require
	-- time rather than a silent fourth group nothing else routes to.
	MUSIC = "Music",
	AMBIENCE = "Ambience",
	SFX = "SFX",
}
