const Debris = game:GetService "Debris"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const tween = require(ReplicatedStorage.Util.tween)
const sound_groups = require(script.Parent["sound-groups"])
const pick_other = require(ReplicatedStorage.Util.tables["pick-other"])

-- One music track at a time, crossfaded whenever the situation changes.
--
-- Deliberately a plain module with a `set` rather than something that watches
-- state itself. What "the situation" means differs per place and per game -- a
-- menu has no combat state to read, and requiring the module that holds it
-- would register sync atoms that place never writes. So each place ships its
-- own thin driver deciding WHICH playlist, and they all share this.
--
--   music_player.set(playlists.combat)   -- an array of asset ids
--   music_player.set {}                  -- fade to silence
--
-- The rules, in order of how often they bite:
--
--  * Setting the SAME playlist twice is a no-op. Drivers re-run on every state
--    change -- a counter ticking up, a door opening -- and almost none of those
--    change the music. Without this, moving through a level would restart the
--    track at every doorway.
--  * A track that survives into the new playlist KEEPS PLAYING. A driver that
--    recomputes an equivalent list must not restart what is already going.
--  * A finished track prefers not to pick ITSELF again: the draw is retried
--    once on a repeat, which is enough to make a two-track list mostly
--    alternate without ever being able to loop on an unlucky draw.
--  * A track that never LOADS is dropped and the next one starts. This is the
--    failure that would otherwise be silent and permanent -- Sound.Ended never
--    fires for an asset that failed to load, so without the watchdog below one
--    delisted or moderated id ends the score for the rest of the session and
--    leaks the Sound that was waiting on it. Every id here is somebody else's
--    upload on a library that can change under us, so this is a when, not an
--    if -- and Client/play-sound guards the same hazard for one-shots.

const FADE = 1.6
const VOLUME = 0.35
-- How long a track gets to load before it is written off. Generous: this is a
-- streamed multi-megabyte asset on a cold client, and giving up early on a
-- slow connection would skip through the whole playlist on join.
const LOAD_TIMEOUT = 20

-- Ids that failed to load, so the playlist stops offering them. Never cleared:
-- an asset that would not load once in this session will not load later in it,
-- and retrying is how a dead playlist turns into a stutter of one-second
-- attempts instead of silence.
const dead: { [string]: true } = {}

export type Playlist = { string }

local playlist: Playlist = {}
local playing: Sound? = nil
local playing_id: string? = nil
-- Bumped on every `set`. A fade-in that has been superseded checks this before
-- writing a volume, so a fast lobby -> run -> lobby cannot leave a ghost track
-- tweening up behind the one that should be playing.
local generation = 0

function fade_out(sound: Sound)
	tween(sound, FADE, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, function(volume)
		sound.Volume = volume
	end, sound.Volume, 0)
	-- Debris rather than a task.delay so a client leaving mid-fade does not
	-- leave the Sound parented to SoundService forever.
	Debris:AddItem(sound, FADE)
end

function next_track(): string?
	-- Rebuilt per call rather than cached: a playlist is at most three entries
	-- and this runs once per track change, so filtering here is cheaper than
	-- keeping a parallel live list in step with `dead`.
	const live = {}
	for _, id in playlist do
		if not dead[id] then
			table.insert(live, id)
		end
	end
	-- Empty, single-track and "current is not in the list any more" are all
	-- handled there, and the draw genuinely cannot return the track already
	-- playing -- the retry-once version this replaced repeated a quarter of the
	-- time on a two-track playlist.
	return pick_other(live, playing_id)
end

function start(id: string, mine: number)
	const sound = Instance.new "Sound"
	sound.Name = "Music"
	sound.SoundId = id
	sound.Volume = 0
	sound.SoundGroup = sound_groups.get(sound_groups.MUSIC)
	sound.Parent = sound_groups.get(sound_groups.MUSIC)
	playing = sound
	playing_id = id
	sound:Play()
	tween(sound, FADE, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, function(volume)
		if generation ~= mine then
			return
		end
		sound.Volume = volume
	end, 0, VOLUME)
	sound.Ended:Once(function()
		if generation ~= mine or playing ~= sound then
			return
		end
		playing = nil
		sound:Destroy()
		-- Straight into the next one at full volume: a gap between two tracks
		-- of the same bed reads as the music breaking, not as a track change.
		const following = next_track()
		if following then
			start(following, mine)
		end
	end)

	-- The watchdog. IsLoaded is the only thing that distinguishes "streaming
	-- in slowly" from "this id is never going to play", and the second one
	-- raises no event at all.
	task.delay(LOAD_TIMEOUT, function()
		if generation ~= mine or playing ~= sound or sound.IsLoaded then
			return
		end
		dead[id] = true
		playing = nil
		playing_id = nil
		sound:Destroy()
		const following = next_track()
		if following then
			start(following, mine)
		end
	end)
end

-- The whole API. `list` is an array of sound asset ids -- keep them in a record
-- so the same table identity comes back each time (see the first rule at the
-- top: `list == playlist` is what makes re-setting cheap). An empty list means
-- "fade to silence and stay there".
function set(list: Playlist)
	if list == playlist then
		return
	end
	playlist = list
	-- Already playing something this list still wants: leave it alone.
	if playing and playing_id and table.find(list, playing_id) then
		return
	end
	generation += 1
	const mine = generation
	const outgoing = playing
	playing = nil
	playing_id = nil
	if outgoing then
		fade_out(outgoing)
	end
	const id = next_track()
	if id then
		start(id, mine)
	end
end

return table.freeze {
	set = set,
}
