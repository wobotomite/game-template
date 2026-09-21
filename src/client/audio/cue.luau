const ReplicatedStorage = game:GetService "ReplicatedStorage"
const SoundService = game:GetService "SoundService"
const TweenService = game:GetService "TweenService"

const sound_profile = require(script.Parent["sound-profile"])
const sound_groups = require(script.Parent["sound-groups"])
const CUE = require(ReplicatedStorage.Shared.settings).audio.cue

-- The cue bus: one place every non-music sound in the game asks to be heard,
-- and the policy that decides whether it is.
--
--   const cue = require(ReplicatedStorage.Client.audio.cue)
--
--   cue.fire(specs.PICKUP)                    -- 2D, at the player
--   cue.fire(specs.DOOR, door_part)           -- positional, follows the part
--   cue.fire(specs.IMPACT, hit_position)      -- positional, at a point
--   cue.at_player(specs.HURT, player)         -- positional, on their head
--   cue.hold(specs.ENGINE, throttle, vehicle) -- a looping bed at a level
--
-- WHY A BUS AND NOT `play-sound` EVERYWHERE. `Client.audio.play-sound` plays
-- one sound and cleans it up; it is the right tool for a cue with no
-- competition. What it has no opinion about is what happens when TWENTY cues
-- want the same half second, which is the normal state of a fight, a crowd or
-- a physics pile-up. Unbudgeted, the engine plays all of them: the mix turns
-- to mud, the one line the player needed is buried under twelve footsteps, and
-- the frame that spawned them all pays for every Sound. This module exists for
-- the policy, not the playing:
--
--   a voice budget       at most `MAX_VOICES` cues at once
--   priorities           a cue past the budget takes a QUIETER one's slot, or
--                        is dropped -- it never takes a louder one's
--   per-cue cooldowns    the same cue from the same source cannot retrigger
--                        inside `min_interval`
--   distance culling     a cue further away than its own radius never starts
--   beds                 a looping sound held at a level, which fades itself
--                        out when nobody re-states it
--
-- A SPEC IS DATA, AND THAT IS THE POINT. Each cue is one frozen table, written
-- once where the game's cues are listed, and every call site names it. So "the
-- pickup chime is too loud" is one number in one place rather than a grep for
-- an id, and two call sites cannot drift into playing the same sound at
-- different volumes.

-- ================================ the numbers ==============================

const MAX_VOICES = CUE.MAX_VOICES
const NEAR_FRACTION = CUE.NEAR_FRACTION
const FAR_PITCH = CUE.FAR_PITCH
const JITTER = CUE.JITTER
const BED_FADE_IN = CUE.BED_FADE_IN
const HOLD_GRACE = CUE.HOLD_GRACE
const HOLD_FLOOR = CUE.HOLD_FLOOR
const SWEEP_INTERVAL = CUE.SWEEP_INTERVAL
const SWEEP_DECAY = CUE.SWEEP_DECAY
const LOAD_DEADLINE = CUE.LOAD_DEADLINE
const SWEEP_SLACK = CUE.SWEEP_SLACK

-- SPACED BY TEN so a game can slot its own levels between these without
-- renumbering the ones it did not write -- a "combat" tier at 25 sits above
-- routine and below important, and nothing else has to know.
--
-- What the levels mean is a question about ATTENTION, not about loudness:
--
--   BACKGROUND  texture. Footsteps, ambience, a UI hover. Losing one costs
--               nothing, and there are always more coming.
--   ROUTINE     the game answering an action the player took.
--   IMPORTANT   something the player needs to notice: a hit landing, a
--               purchase going through, a timer running out.
--   URGENT      something the player must act on. These are rare by
--               construction -- a tier everything claims is not a tier.
const PRIORITY = table.freeze {
	BACKGROUND = 10,
	ROUTINE = 20,
	IMPORTANT = 30,
	URGENT = 40,
}

export type Spec = {
	-- The asset. `""` is the unset sentinel from `assets.sounds`; a spec on one
	-- is skipped with a single warn rather than playing silence forever.
	id: string,
	-- Optional variants, drawn from at random. Footsteps, impacts, anything
	-- that fires often enough for one sample to become a texture the ear picks
	-- out. `id` is the fallback when this is absent or empty.
	ids: { string }?,
	-- In the mix, before the asset's own `sound-profile` gain.
	volume: number,
	pitch: number,
	-- Random pitch spread, +/- this fraction. Absent means `settings`' default.
	-- Repeats of an identical sample fuse into one long noise; a little spread
	-- is what keeps five of them sounding like five events.
	jitter: number?,
	-- One of `PRIORITY`.
	priority: number,
	-- Seconds before this cue may retrigger FROM THE SAME SOURCE. The most
	-- load-bearing number in a spec: without it, anything driven by a
	-- per-frame condition fires sixty times a second.
	min_interval: number,
	-- Studs. `0` means 2D -- heard everywhere at full volume, which is what a
	-- UI click and a cue about the local player want. Anything above 0 makes
	-- the cue positional and is also the distance past which it is not played
	-- at all.
	radius: number,
	-- Which bus. Defaults to SFX for one-shots, AMBIENCE for beds.
	bus: string?,
	-- Where attenuation STARTS, if not `radius * NEAR_FRACTION`. Raise it for a
	-- cue that should stay at full volume across a room.
	near_radius: number?,
	-- Diagnostics only: what to call this cue in a warning. Unset ids and dead
	-- assets are reported by name when a spec carries one, because "a sound
	-- failed to load" without a name is a grep through every spec in the game.
	name: string?,
}

type Voice = {
	sound: Sound,
	spec: Spec,
	-- os.clock at the moment it started. The tiebreak when two voices of the
	-- same priority are both candidates for eviction.
	started: number,
	-- The Attachment created to hold a bare-Vector3 position, if any. Owned by
	-- the voice and destroyed with it.
	anchor: Attachment?,
	-- Retirement is racy -- four different signals can reach it (see
	-- `arm_sweep`) -- and destroying an already-destroyed Sound or shuffling
	-- the voice list twice is how a double-fire turns into a wrong eviction.
	retired: boolean?,
}

type Bed = {
	sound: Sound,
	spec: Spec,
	-- The last time a caller re-stated this bed. A bed is not turned off; it is
	-- ALLOWED TO DECAY once nobody is asking for it any more (see `sweep`).
	stated: number,
	-- When it started, so the fade-in tween is not fought by a direct write.
	opened: number,
	-- Its current target volume, tracked here rather than read back off the
	-- Sound: the tween is writing that property, so reading it mid-fade gives
	-- a number that is on its way somewhere.
	gain: number,
}

-- ================================ the state ================================

-- The key for a cue with no source of its own. A unique frozen table rather
-- than a string or `nil`: `nil` cannot be a table key at all, and any string
-- could collide with a key a caller passed.
const GLOBAL_KEY = table.freeze {}

const voices: { Voice } = {}
const beds: { [Spec]: { [any]: Bed } } = {}
-- Per spec, per source: when it last fired. See `stamps_of` for the weakness.
const last_fired: { [Spec]: { [any]: number } } = {}

-- Ids already complained about, so a broken asset costs one line rather than
-- one line per play.
const warned: { [string]: true } = {}

-- A folder inside SoundService rather than the service itself: parenting
-- straight into the service measured 24us against 9.6us one level down (the
-- service does extra per-child bookkeeping), and cues arrive in bursts.
const container = Instance.new "Folder"
container.Name = "Cues"
container.Parent = SoundService

local sweeping = false

function listener_position(): Vector3?
	-- The CAMERA, not the character: the camera is where the engine listens
	-- from by default, so culling against anything else would cull cues the
	-- player can hear and keep ones they cannot.
	const camera = workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- Cooldowns are PER SOURCE, not per cue. Ten crates breaking in the same
-- moment are ten events and should sound like ten; the same crate breaking ten
-- times in a frame is one. A global stamp cannot tell those apart, and gets
-- the first case wrong -- which is the one that matters, because it is the one
-- that sounds broken.
function source_key(where: (Vector3 | BasePart)?, key: any?): any
	if key ~= nil then
		return key
	end
	-- A Vector3 is a value, not an identity: two calls at the same point are
	-- not the same source and would not be equal keys anyway. Only a part
	-- identifies itself.
	if where ~= nil and typeof(where) ~= "Vector3" then
		return where
	end
	return GLOBAL_KEY
end

-- WEAK KEYS. The keys here are whatever the caller used as a source -- usually
-- a BasePart, sometimes a player or an arbitrary table -- and this map is
-- never cleaned up by hand. A strong map would hold every part that ever
-- played a cue alive for the session, which is a leak proportional to how much
-- of the world has ever made a noise.
function stamps_of(spec: Spec): { [any]: number }
	local map = last_fired[spec]
	if map == nil then
		map = (setmetatable({}, { __mode = "k" }) :: any) :: { [any]: number }
		last_fired[spec] = map
	end
	return map
end

-- ============================== the decisions ==============================
--
-- The three functions below are the whole policy, and they are separated out
-- because they are the part worth reading and pinning: no instances, no
-- engine, just the arithmetic. Everything else in this file is plumbing around
-- them.

-- May this cue sound? `last` is when it last fired from this source (nil if
-- never), `distance` the distance from the listener (nil for a 2D cue).
function gate(spec: Spec, now: number, last: number?, distance: number?): boolean
	if last ~= nil and now - last < spec.min_interval then
		return false
	end
	-- Culled rather than played quietly. The engine would attenuate it to
	-- nothing anyway -- the saving is the VOICE, which an inaudible cue would
	-- otherwise hold for its whole length while an audible one is dropped for
	-- lack of a slot.
	if distance ~= nil and distance > spec.radius then
		return false
	end
	return true
end

-- Which voice a cue of this priority may take the slot of, or nil when it must
-- be dropped instead.
--
-- STRICTLY LOWER, never equal. A cue must not be able to silence something the
-- game rated as important as itself, and `>=` would let a burst of one kind of
-- cue eat its own tail -- each new one retiring the one before it, so twelve
-- sounds produce one.
--
-- Among equals the OLDEST goes. It is the one furthest through its own
-- playback, so it has the least left to lose, and it is the one the player has
-- already heard.
function weakest(list: { Voice }, priority: number): Voice?
	local worst: Voice? = nil
	for _, voice in list do
		if voice.spec.priority >= priority then
			continue
		end
		if worst == nil then
			worst = voice
			continue
		end
		if voice.spec.priority < worst.spec.priority then
			worst = voice
		elseif voice.spec.priority == worst.spec.priority and voice.started < worst.started then
			worst = voice
		end
	end
	return worst
end

-- One step of a bed's fade-out: its next gain, or nil when it has faded far
-- enough to be destroyed. `volume` is the bed's spec volume, so the floor is
-- relative to how loud this bed ever was.
--
-- A HALVING, not a subtraction. A bed's volume is heard logarithmically, so
-- a fixed step per sweep is a fast fade at the top and an eternity at the
-- bottom; halving sounds like a constant rate. It also never reaches zero,
-- which is exactly why there is a floor.
function decay(gain: number, volume: number): number?
	const faded = gain * SWEEP_DECAY
	if faded < volume * HOLD_FLOOR then
		return nil
	end
	return faded
end

-- ================================ the voices ===============================

function retire(voice: Voice)
	if voice.retired then
		return
	end
	voice.retired = true
	voice.sound:Destroy()
	if voice.anchor then
		voice.anchor:Destroy()
	end
	const index = table.find(voices, voice)
	if index then
		-- Swap-remove: order in this list carries no meaning (`started` is what
		-- orders voices), and `table.remove` from the middle of a list that
		-- turns over several times a second is a copy each time.
		voices[index] = voices[#voices]
		voices[#voices] = nil
	end
end

-- A voice whose Sound has been taken out of the world by something else -- the
-- part it was parented to was destroyed, a model was despawned. It will never
-- end, so nothing else will ever retire it, and it would hold a slot in the
-- budget for the rest of the session.
function stale(voice: Voice): boolean
	const sound = voice.sound
	return sound.Parent == nil or not sound:IsDescendantOf(game)
end

function make_room(priority: number): boolean
	if #voices < MAX_VOICES then
		return true
	end
	-- Sweep the dead FIRST, and only when the budget is actually full. A full
	-- budget is the one moment this is worth walking the list for, and it is
	-- also the moment where a list full of ghosts would drop a live cue for no
	-- reason. Backwards, because retiring swap-removes.
	for index = #voices, 1, -1 do
		const voice = voices[index]
		if stale(voice) then
			retire(voice)
		end
	end
	if #voices < MAX_VOICES then
		return true
	end
	const worst = weakest(voices, priority)
	if worst == nil then
		return false
	end
	retire(worst)
	return true
end

-- Four ways a voice ends, because in practice all four happen:
--
--   Ended             the normal one.
--   Destroying        something else destroyed the Sound -- most often the
--                     part it was parented to going away.
--   AncestryChanged   the part was reparented out of the world rather than
--                     destroyed, which raises no other signal here.
--   the deadline      ENDED NEVER FIRES FOR AN ASSET THAT FAILED TO LOAD. This
--                     is the case with no event at all, and without it a
--                     moderated or mistyped id permanently spends a slot in
--                     the budget every time it is played.
--
-- The deadline's test is `TimeLength`, and it is the only one that works: a
-- Sound on a dead id reports Playing and IsPlaying true indefinitely,
-- identically to one genuinely mid-playback. What it cannot fake is a
-- duration -- an asset that never arrived stays at 0.
function arm_sweep(voice: Voice)
	const sound = voice.sound
	sound.Ended:Once(function()
		retire(voice)
	end)
	sound.Destroying:Once(function()
		retire(voice)
	end)
	sound.AncestryChanged:Connect(function()
		if stale(voice) then
			retire(voice)
		end
	end)
	task.delay(LOAD_DEADLINE, function()
		if stale(voice) then
			retire(voice)
			return
		end
		if sound.TimeLength <= 0 then
			const id = sound.SoundId
			if not warned[id] then
				warned[id] = true
				const name = voice.spec.name or "unnamed cue"
				warn(`[cue] {name}: '{id}' never loaded -- silent, and dropped after {LOAD_DEADLINE}s`)
			end
			retire(voice)
			return
		end
		-- It loaded and is still going. Let it finish, then take it anyway in
		-- case `Ended` never comes.
		--
		-- DIVIDED BY PlaybackSpeed: TimeLength is the ASSET's length, and a cue
		-- played at 0.5 runs for twice that. The slack on top is because taking
		-- a sound at exactly its length cuts its decay, which reads as the
		-- audio glitching rather than as a timer.
		const speed = math.max(sound.PlaybackSpeed, 0.05)
		task.delay(sound.TimeLength / speed + SWEEP_SLACK, function()
			retire(voice)
		end)
	end)
end

function pick_id(spec: Spec): string
	const ids = spec.ids
	if ids == nil or #ids == 0 then
		return spec.id
	end
	return ids[math.random(#ids)]
end

-- ================================== firing =================================

-- Play a cue. `where` is a part to follow, a point in the world, or nothing
-- for a 2D cue. `key` overrides what counts as the "source" for the cooldown,
-- for the case where the thing making the noise is not the thing it is
-- attached to.
--
-- Returns whether it actually started: false means the cooldown, the distance
-- cull, the voice budget or an unset id stopped it. Most callers ignore this;
-- it is there for the ones that want to know whether to also flash something.
function fire(spec: Spec, where: (Vector3 | BasePart)?, key: any?): boolean
	const positional = spec.radius > 0

	-- A 2D Sound IGNORES the position it was given and plays at full volume
	-- everywhere, so this mistake is inaudible rather than wrong-sounding: the
	-- caller believes they built a positional cue and shipped a global one. An
	-- assert because it is a fixed property of the spec and the call site, not
	-- of the data -- it fires on the first playtest or never.
	assert(
		where == nil or positional,
		`cue '{spec.name or spec.id}' has radius 0 (2D) and was given a position -- give the spec a radius or drop the argument`
	)

	const id = pick_id(spec)
	if id == "" then
		-- The unset sentinel from `assets.sounds`. A fresh game has every id
		-- unset, so this is the normal state of a template -- one warn naming
		-- the cue, then silence, rather than a Sound per play that can never
		-- make a noise.
		const name = spec.name or "unnamed cue"
		if not warned[name] then
			warned[name] = true
			warn(`[cue] {name} has no asset id in assets.sounds -- staying silent`)
		end
		return false
	end

	const now = os.clock()
	const stamps = stamps_of(spec)
	const source = source_key(where, key)

	local pitch = spec.pitch
	local at: Vector3? = nil
	local distance: number? = nil

	if where ~= nil then
		const point = if typeof(where) == "Vector3" then where else (where :: BasePart).Position
		at = point
		const ears = listener_position()
		if ears then
			distance = (point - ears).Magnitude
		end
	end

	if not gate(spec, now, stamps[source], distance) then
		return false
	end

	if distance ~= nil then
		-- Distance reads as DULLNESS as much as as quietness: a far cue that is
		-- only quieter sounds like a quiet cue nearby, which is a different
		-- event. Pitch is the cheapest approximation of that.
		pitch *= math.lerp(1, FAR_PITCH, distance / spec.radius)
	end

	pitch *= 1 + (math.random() * 2 - 1) * (spec.jitter or JITTER)

	-- LAST, after every cheaper reason to bail: make_room can EVICT a playing
	-- voice, so asking it before the cooldown and the distance cull would let a
	-- cue that is not going to play anyway silence one that is.
	if not make_room(spec.priority) then
		return false
	end

	local anchor: Attachment? = nil
	local parent: Instance = container
	if at ~= nil then
		if typeof(where) == "Vector3" then
			-- A Sound is 3D only when its parent is a BasePart or an
			-- Attachment. A bare point has neither, so it gets an Attachment of
			-- its own -- on Terrain, which is always present, never streamed
			-- out and never destroyed under us. Owned by the voice and
			-- destroyed with it.
			const made = Instance.new "Attachment"
			made.WorldPosition = at
			made.Parent = workspace.Terrain
			anchor = made
			parent = made
		else
			-- Parented to the part, so the cue FOLLOWS it. A moving source that
			-- plays from where it used to be is worse than a 2D cue.
			parent = where :: BasePart
		end
	end

	const sound = Instance.new "Sound"
	sound.SoundId = id
	sound.Volume = spec.volume * sound_profile.gain(id)
	sound.PlaybackSpeed = pitch
	sound.SoundGroup = sound_groups.get(spec.bus or sound_groups.SFX)
	if positional then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		-- SET EXPLICITLY. Roblox attenuates by Min/distance with Min defaulting
		-- to 10 studs, so a cue with a 200-stud radius and no Min is already
		-- near-silent at 30 -- and MaxDistance alone only says where a sound is
		-- CULLED, not how it falls off.
		sound.RollOffMinDistance = spec.near_radius or spec.radius * NEAR_FRACTION
		sound.RollOffMaxDistance = spec.radius
	end
	sound.Parent = parent
	sound_profile.apply(sound)
	sound:Play()

	const voice: Voice = { sound = sound, spec = spec, started = now, anchor = anchor }
	table.insert(voices, voice)
	stamps[source] = now
	arm_sweep(voice)
	return true
end

-- A cue on a player's body. The head rather than the root, because the head is
-- where a listener expects a voice to come from, with the root as the fallback
-- for a rig that has none.
function at_player(spec: Spec, player: Player, key: any?): boolean
	const character = player.Character
	if character == nil then
		return false
	end
	const head = character:FindFirstChild "Head"
	const part = if head and head:IsA "BasePart" then head :: BasePart else character.PrimaryPart
	if part == nil then
		return false
	end
	return fire(spec, part, key)
end

-- ================================== beds ===================================

-- A looping sound held at a level: an engine at throttle, a fire nearby, rain.
-- `level` is 0..1 and multiplies the spec's volume; 0 or less stops it now.
--
-- STATED, NOT SWITCHED ON. Callers drive beds from a condition they recompute
-- every frame ("am I near a fire, and how near"), and the frame where the
-- condition stops being true is routinely a frame where nothing runs at all --
-- the emitter was destroyed, the state machine left through another branch,
-- the player died. A bed that waits to be turned off is a bed that plays
-- forever. So calling this is a STATEMENT that the bed should be sounding now,
-- and one that stops being made fades out by itself (see `sweep`).
--
-- The cost of that choice is that a bed is re-stated at whatever rate the
-- caller runs at, which is why the volume write below is conditional rather
-- than a tween per call.
function hold(spec: Spec, level: number, part: BasePart?, key: any?)
	const source = source_key(part, key)
	local group = beds[spec]
	const existing = if group then group[source] else nil

	if level <= 0 then
		if existing and group then
			existing.sound:Destroy()
			group[source] = nil
		end
		return
	end

	if spec.id == "" then
		const name = spec.name or "unnamed bed"
		if not warned[name] then
			warned[name] = true
			warn(`[cue] {name} has no asset id in assets.sounds -- staying silent`)
		end
		return
	end

	const now = os.clock()
	const wanted = spec.volume * level * sound_profile.gain(spec.id)

	if existing then
		existing.stated = now
		existing.gain = wanted
		-- NOT DURING THE FADE-IN. The opening tween owns Volume for its first
		-- `BED_FADE_IN` seconds; a direct write in the middle of it is a step
		-- the tween immediately overwrites, and a caller re-stating every frame
		-- would turn the fade into a stutter.
		if now - existing.opened >= BED_FADE_IN and existing.sound.Volume ~= wanted then
			existing.sound.Volume = wanted
		end
		return
	end

	const sound = Instance.new "Sound"
	sound.SoundId = spec.id
	-- From silence: a bed that starts at its target volume is a click, and beds
	-- start on state changes that are already busy.
	sound.Volume = 0
	sound.PlaybackSpeed = spec.pitch
	sound.Looped = true
	-- Beds default to AMBIENCE rather than SFX: they are the layer a player
	-- turns down, and the one cues need to sit on top of.
	sound.SoundGroup = sound_groups.get(spec.bus or sound_groups.AMBIENCE)
	if spec.radius > 0 then
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = spec.near_radius or spec.radius * NEAR_FRACTION
		sound.RollOffMaxDistance = spec.radius
	end
	sound.Parent = if part then part else container
	sound_profile.apply(sound)
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(BED_FADE_IN), { Volume = wanted }):Play()

	if group == nil then
		group = {}
		beds[spec] = group
	end
	group[source] = { sound = sound, spec = spec, stated = now, opened = now, gain = wanted }
	ensure_sweeper()
end

-- One pass over every live bed. Returns how many are still alive, which is
-- what tells the sweeper whether to schedule itself again.
--
-- THE GRACE PERIOD is what makes "stated, not switched on" survive an ordinary
-- frame rate. A caller re-stating a bed every frame still misses one now and
-- then -- a hitch, a yield, a frame where their own source was busy -- and a
-- bed that began fading on every skipped frame would wobble constantly.
-- `HOLD_GRACE` is the window inside which a missed statement means nothing.
function sweep(now: number): number
	local live = 0
	for spec, group in beds do
		local remaining = 0
		for source, bed in group do
			if now - bed.stated <= HOLD_GRACE then
				live += 1
				remaining += 1
				continue
			end
			const faded = decay(bed.gain, spec.volume)
			if faded == nil then
				bed.sound:Destroy()
				group[source] = nil
			else
				bed.gain = faded
				bed.sound.Volume = faded
				live += 1
				remaining += 1
			end
		end
		-- Drop the empty group too, so a spec that is not sounding anywhere
		-- stops being walked at all.
		if remaining == 0 then
			beds[spec] = nil
		end
	end
	return live
end

-- The sweeper reschedules itself only while there is something to sweep, so a
-- game with no beds running has no timer at all -- and one that stops holding
-- them stops paying for them a quarter second later. `sweeping` is the guard
-- against two sweepers, which every `hold` of a new bed would otherwise start.
function ensure_sweeper()
	if sweeping then
		return
	end
	sweeping = true
	task.delay(SWEEP_INTERVAL, function()
		sweeping = false
		if sweep(os.clock()) > 0 then
			ensure_sweeper()
		end
	end)
end

return table.freeze {
	PRIORITY = PRIORITY,
	fire = fire,
	at_player = at_player,
	hold = hold,
	sweep = sweep,
	-- The three decisions, exported for the spec that pins them and for a game
	-- that wants to ask the same questions without playing anything.
	gate = gate,
	weakest = weakest,
	decay = decay,
}
