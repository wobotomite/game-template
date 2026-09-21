const ReplicatedStorage = game:GetService "ReplicatedStorage"

const sounds = require(ReplicatedStorage.Shared.assets).sounds
const profiles = require(ReplicatedStorage.Shared.settings).audio.profiles

-- Per-asset corrections, applied to every Sound the cue engine builds.
--
-- WHAT THIS IS FOR. Sound libraries are not mastered to each other. One sample
-- arrives six times louder than the rest; another carries two seconds of room
-- tone before the hit, so the cue fires on the frame it was asked for and is
-- heard a beat later. Both are properties of the ASSET, not of the moment it
-- plays -- so they are fixed once here rather than in every spec that uses it,
-- and a re-upload that fixes the sample is one line deleted.
--
-- A profile, in `settings.audio.profiles`, keyed by the same name the id has
-- in `assets.sounds`:
--
--   BIG_DOOR = { gain = 0.4 },                       -- it is simply too loud
--   AMBIENT_HUM = { gain = 1, start = 1.8, finish = 9.2 },  -- trim the silence
--
--   gain            multiplies the spec's volume. A spec says how loud this
--                   cue is IN THE MIX; gain says how loud this recording is.
--                   Keeping them apart is what lets a sample be swapped
--                   without re-balancing every cue that plays it.
--   start, finish   seconds. Both or neither -- a region with one end is not a
--                   region, so a half-written profile is ignored rather than
--                   guessed at.
--
-- EMPTY IS THE RIGHT DEFAULT and a fresh game should stay that way. Every
-- entry here is a correction for one specific upload; a profile written before
-- anyone has heard the asset in place is a guess that outlives the reason for
-- it.
type Profile = { gain: number, start: number?, finish: number? }

-- Keyed by ID rather than by name, because that is what a Sound carries. The
-- map is built ONCE at require time: the settings are frozen, so there is
-- nothing to invalidate, and the lookup is then one hash per cue on a path
-- that runs in bursts.
const by_id: { [string]: Profile } = {}

for name, profile in profiles do
	const id = (sounds :: { [string]: string })[name]
	-- A profile naming a cue that has no id is a typo in one of the two data
	-- files. Warned rather than indexed: `by_id[nil]` throws, and this module
	-- is required at boot, so the typo would take the whole audio stack down
	-- instead of costing one correction.
	if id == nil then
		warn(`[sound-profile] '{name}' has no id in assets.sounds -- profile ignored`)
		continue
	end
	-- The unset sentinel is shared by every id nobody has filled in yet, so a
	-- profile attached to one would silently apply to ALL of them.
	if id == "" then
		warn(`[sound-profile] '{name}' is unset ("") in assets.sounds -- profile ignored`)
		continue
	end
	by_id[id] = profile
end

-- The asset's own level correction, 1 when it has no profile. Separate from
-- `apply` because a bed's volume is computed before its Sound exists.
function gain(id: string): number
	const profile = by_id[id]
	return if profile then profile.gain else 1
end

-- The rest of the correction, once the Sound exists.
function apply(sound: Sound)
	const profile = by_id[sound.SoundId]
	if profile and profile.start and profile.finish then
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(profile.start, profile.finish)
		-- A looped Sound loops the WHOLE asset unless told otherwise, so
		-- trimming the lead-in without this gives a bed that is clean the first
		-- time round and drags the dead air back in on every repeat.
		if sound.Looped then
			sound.LoopRegion = sound.PlaybackRegion
		end
		-- PlaybackRegion sets the bounds; TimePosition is where the playhead
		-- actually starts. A Sound left at 0 with a region starting at 1.8
		-- begins outside its own region.
		sound.TimePosition = profile.start
	end
end

return table.freeze {
	gain = gain,
	apply = apply,
}
