const ContentProvider = game:GetService "ContentProvider"
const SoundService = game:GetService "SoundService"

-- Warm every asset the place can reach, and say how far along it is.
--
-- WHY BOTHER. A Sound whose asset is not resident does not play when you call
-- `:Play()`. It starts streaming, and plays whenever it arrives -- which is
-- some other moment than the one it was for. The same is true of a texture on
-- the first model of its kind to appear. Neither shows up as an error; both
-- read as the game feeling loose.
--
-- USAGE. Hand it a plan and start it, then drive a loading screen off
-- `progress()` and `finished()`:
--
--   const preload = require(ReplicatedStorage.Client.boot.preload)
--   preload.start {
--       content = image_ids,              -- textures, decals
--       sounds = one_shot_ids,            -- cues that must land on a frame
--       instances = prefab_models,        -- authored trees, warmed as one batch
--       heavy_sounds = music_and_ambience, -- megabyte streams, warmed LAST
--   }
--   while not preload.finished() do
--       const done, total = preload.progress()
--       ...
--   end
--
-- ORDER IS THE POINT of splitting `sounds` from `heavy_sounds`. If a loading
-- screen has a skip button -- and it should -- then a skip halfway through must
-- still leave the player with everything that has to arrive on cue. Music and
-- ambience beds are megabytes, fade in over seconds, and are exactly what a
-- mid-bar skip is allowed to leave behind.

-- Preload in chunks with a yield between them. PreloadAsync blocks until the
-- whole array resolves, so handing it a hundred ids in one call is a single
-- uninterruptible stall -- and chunking is also what makes a progress counter
-- move instead of jumping 0 -> done.
const CHUNK = 24

local done_count = 0
local total_count = 0
local finished_flag = false
local started = false

-- ============================== sounds ====================================

-- Every sound id gets a STATIC Sound instance, parented and kept for the whole
-- session. Nothing ever plays them; existing in the DataModel with SoundId set
-- is what makes Roblox fetch and hold the audio.
--
-- THE INSTANCES BEING IN THE DATAMODEL IS THE WHOLE THING. The obvious version
-- of this file creates probe Sounds, passes them to PreloadAsync and destroys
-- them immediately, on the reasoning that the global content cache is what
-- matters. Measured in a running session, that version is a NO-OP:
--
--   unparented probes   PreloadAsync yields ~0.5s, the probes report unloaded,
--                       and fresh Sounds on those ids 100ms later are STILL
--                       unloaded -- identical to a never-preloaded control.
--   parented probes     fresh Sounds on those ids resolve immediately; the
--                       never-preloaded control does not.
--
-- So it spent the time and bought nothing, while the late-cue problem it was
-- written to fix stayed live. Silently doing nothing SLOWLY is the hardest
-- kind of broken to notice.
--
-- The CONTROL GROUP is what makes that measurement mean anything. Reading
-- `IsLoaded` off the probe only ever proves the property does not populate --
-- a warmed cache with a broken readback looks the same. Testing an id nothing
-- has touched is what separates them.
--
-- Keeping the instances also removes a bet: a live Sound holds a reference to
-- its asset, so the cache cannot quietly evict it mid-session and reintroduce
-- the late first cue. A couple hundred silent Sounds in a folder cost
-- effectively nothing.
--
-- Images get no static instances -- the problem above is Sound-specific
-- streaming semantics, and PreloadAsync on raw content-id strings is the
-- documented warm-up path for textures.
local sound_holder: Folder? = nil
-- One static instance per id even when an id appears in more than one list.
const held_ids: { [string]: true } = {}

local function warm_sounds(ids: { string })
	local holder = sound_holder
	if not holder then
		holder = Instance.new "Folder"
		-- A Folder under SoundService rather than the service itself: the
		-- service does extra per-child bookkeeping, and these are silent 2D
		-- Sounds nothing will ever play.
		holder.Name = "PreloadedSounds"
		holder.Parent = SoundService
		sound_holder = holder
	end
	for first = 1, #ids, CHUNK do
		const chunk = {}
		for offset = 0, CHUNK - 1 do
			const id = ids[first + offset]
			if not id then
				break
			end
			if held_ids[id] then
				-- Already held; still counted, so the denominator adds up.
				done_count += 1
				continue
			end
			held_ids[id] = true
			const sound = Instance.new "Sound"
			sound.SoundId = id
			sound.Parent = holder
			table.insert(chunk, sound)
		end
		-- The parented instances above already start the fetch; PreloadAsync is
		-- what makes this pass WAIT for the chunk to arrive, so the progress
		-- counter and the loading gate mean something.
		--
		-- pcall, because ONE delisted or moderated id makes PreloadAsync throw.
		-- Without the pcall a single dead sample costs the rest of the pass;
		-- without the chunking it costs the entire warm-up.
		pcall(ContentProvider.PreloadAsync, ContentProvider, chunk)
		done_count += #chunk
		task.wait()
	end
end

-- Raw content ids: images, decals, anything addressed by string.
local function warm_ids(ids: { string })
	for first = 1, #ids, CHUNK do
		const chunk = table.move(ids, first, math.min(first + CHUNK - 1, #ids), 1, {})
		pcall(ContentProvider.PreloadAsync, ContentProvider, chunk)
		done_count += #chunk
		task.wait()
	end
end

-- Live instance trees, all in ONE PreloadAsync: every model resolves as a
-- single batch rather than trickling through one at a time. PreloadAsync walks
-- each instance's descendants itself, including any Sounds a prefab carries --
-- which are already static parented instances, exactly what warm_sounds builds
-- by hand for the id lists.
local function warm_instances(instances: { Instance })
	if #instances == 0 then
		return
	end
	pcall(ContentProvider.PreloadAsync, ContentProvider, instances)
	done_count += #instances
end

-- =============================== the pass =================================

export type Plan = {
	-- Textures, decals, anything addressed by a content-id string.
	content: { string }?,
	-- Sound ids that must land on the frame they are asked for.
	sounds: { string }?,
	-- Authored trees (prefabs, models shipped in the place file).
	instances: { Instance }?,
	-- Long streams -- music, ambience beds. Warmed LAST; see the note above.
	heavy_sounds: { string }?,
}

local function run(plan: Plan)
	const content = plan.content or {}
	const punctual = plan.sounds or {}
	const instances = plan.instances or {}
	const heavy = plan.heavy_sounds or {}

	-- The total is published BEFORE any warming, so a loading screen can show a
	-- real denominator from its first frame rather than a bar that appears to
	-- finish instantly and then restart.
	total_count = #content + #punctual + #instances + #heavy

	warm_ids(content)
	warm_sounds(punctual)
	warm_instances(instances)
	warm_sounds(heavy)
end

-- Begins the pass on its own thread and returns immediately.
function start(plan: Plan)
	if started then
		return
	end
	started = true
	task.spawn(function()
		const ok, err = pcall(run, plan)
		if not ok then
			warn(`[preload] pass failed partway: {err}`)
		end
		-- WHATEVER HAPPENED, THE GATE OPENS. A broken preload must degrade to
		-- "assets stream on demand" -- the behaviour with no preloading at all
		-- -- and never to a loading screen that will not open.
		done_count = total_count
		finished_flag = true
		-- sound_holder is deliberately NOT destroyed: the static Sound
		-- instances living in it for the rest of the session are what keeps
		-- every id loaded.
	end)
end

return table.freeze {
	start = start,
	-- (done, total). `total` is 0 until start() has tallied the plan.
	progress = function(): (number, number)
		return done_count, total_count
	end,
	finished = function(): boolean
		return finished_flag
	end,
}
