const SoundService = game:GetService "SoundService"

const sound_groups = require(script.Parent["sound-groups"])

-- Fire-and-forget 2D sound: play it, clean it up, never leak it. For cues that
-- belong to the PLAYER rather than to a place in the world -- a pickup chime, a
-- UI tick, a stinger. Anything positional parents its own Sound to a part
-- instead and does not come through here.
--
-- REQUIRE THIS AS `play_sound`, NEVER `play_sound_at`. It takes
-- (id, volume, speed) and has nowhere to put a position, so a caller who
-- believed the second name would have their position land silently in `speed`
-- and play the cue at a garbage pitch. Ten files once aliased it that way.
--
-- Being 2D is deliberate. A Sound is 3D only when its parent is a BasePart or
-- an Attachment; parenting to SoundService or a SoundGroup is 2D no matter what
-- else is set. And for the ones that ARE positional, set RollOffMinDistance:
-- Roblox attenuates by Min/distance with Min defaulting to 10, and MaxDistance
-- alone only says where a sound is CULLED, not how it falls off.
--
-- THIS OR THE CUE BUS? This one plays what it is given, immediately, with no
-- policy at all -- which is right for a sound with no competition, and for a
-- caller that must not be second-guessed. `Client.audio.cue` is the same job
-- with a voice budget, priorities, cooldowns and distance culling on top, and
-- is what anything fired by gameplay should use: cues in bursts are the case
-- this file has no answer for. Both sweep a dead id the same way, below.

-- Cues live in a folder INSIDE SoundService rather than directly under it.
-- Playback is identical: a Sound is 2D unless its parent is a BasePart or an
-- Attachment, and SoundGroup routing is a property rather than a parent. But
-- parenting straight into the service measured 24us against 9.6us into a
-- folder one level down -- the service does extra per-child bookkeeping -- so
-- this is ~14us back on every cue, and cues arrive in bursts during a fight.
const container = Instance.new "Folder"
container.Name = "PlaySound"
container.Parent = SoundService

-- Every 2D cue comes through here, so this is where they join the mix. Without
-- the group they are the one family of sound with no bus at all: music and
-- ambience can be balanced against each other and against nothing, because the
-- cues they most need to sit under go straight to the master.
const sfx_group = sound_groups.get(sound_groups.SFX)

return function(sound_id: string, volume: number?, speed: number?)
	const sound = Instance.new "Sound"
	sound.SoundId = sound_id
	sound.Volume = volume or 0.5
	sound.PlaybackSpeed = speed or 1
	sound.SoundGroup = sfx_group
	sound.Parent = container
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)

	-- `Ended` never fires for an asset that failed to load, so without a sweep
	-- a bad id leaks a Sound per play. The obvious sweep -- a bare
	-- `task.delay(4, sound.Destroy, sound)` -- ALSO cuts off every cue longer
	-- than four seconds, and the long ones are exactly the ones you notice,
	-- because sound length is a tail. Measured in one live session, nine of
	-- twenty-one 2D cues ran past 4s (worst 6.8s); each lost its decay
	-- mid-air, which reads as the audio glitching rather than as a timer.
	--
	-- TimeLength is the tell, and it is the ONLY one. `IsPlaying` looks like
	-- the natural question and is not: measured against a deliberately dead
	-- id, a Sound that will never load reports Playing=true AND IsPlaying=true
	-- indefinitely, identically to one that is genuinely mid-playback. What it
	-- cannot fake is a duration -- an asset that never arrived stays at 0.
	task.delay(4, function()
		if not sound.Parent then
			return
		end
		if sound.TimeLength <= 0 then
			-- Never arrived. (A real asset still loading at four seconds is
			-- swept too -- but a cue that late has already missed the moment it
			-- was for, and preloading at boot is the fix for that, not a
			-- longer timer here.)
			sound:Destroy()
			return
		end
		-- It loaded, and it is longer than the old cap. Let it finish, and
		-- still take it afterwards in case Ended never comes.
		-- DIVIDED BY PlaybackSpeed. TimeLength is the ASSET's length; a Sound
		-- played at 0.5 runs for twice that. Sweeping on the raw length cut
		-- seven live call sites -- the worst played 8.84s and was destroyed at
		-- 5.42s. Worth flagging as a shape: this was the SECOND fix to the same
		-- bug. Keying off TimeLength removed the flat 4s cap and left a
		-- speed-dependent one behind it, which looked like a fix and was half of
		-- one.
		const speed = math.max(sound.PlaybackSpeed, 0.05)
		task.delay(sound.TimeLength / speed + 1, function()
			if sound.Parent then
				sound:Destroy()
			end
		end)
	end)
end
