--!nocheck
-- The cue bus decides three things with arithmetic: whether a cue is allowed
-- to sound, which voice it may take the slot of, and how a held bed fades.
-- Run with:
--   lune run tests/cue-policy.spec.luau
--
-- Only those three are pinned. The rest of `client/audio/cue` builds Sounds
-- and reads the camera, and under Lune the engine is a stub -- but the three
-- below are the part that is wrong PLAUSIBLY. A preemption rule that evicts an
-- equal still plays a sound; a cooldown compared the wrong way round still
-- lets most cues through; a decay without a floor still fades. Each failure
-- sounds like "the audio is a bit off in fights", which is not a bug anyone
-- can file.

local h = require "./harness"
local env = require "./roblox-env"

h.title "cue policy:"

local cue = env.load "ReplicatedStorage.Client.audio.cue"

local function spec(fields)
	fields.id = fields.id or "rbxassetid://1"
	fields.volume = fields.volume or 1
	fields.pitch = fields.pitch or 1
	fields.priority = fields.priority or cue.PRIORITY.ROUTINE
	fields.min_interval = fields.min_interval or 0
	fields.radius = fields.radius or 0
	return fields
end

-- ================================ the gate =================================

-- A cue that has never fired from this source has no stamp, and a 2D cue has
-- no distance. Both absent is the common case and must pass.
do
	local s = spec { min_interval = 0.5 }
	h.check("a first fire is never gated", cue.gate(s, 100, nil, nil))
end

do
	local s = spec { min_interval = 0.5 }
	h.check("inside the cooldown is refused", not cue.gate(s, 100.4, 100, nil))
	-- Exactly at the interval passes: the test is `now - last < min_interval`,
	-- and a cue driven by a timer at its own interval must not be refused
	-- every other time by a floating-point hair.
	h.check("at the cooldown is allowed", cue.gate(s, 100.5, 100, nil))
	h.check("past the cooldown is allowed", cue.gate(s, 101, 100, nil))
end

-- min_interval 0 means "no cooldown", not "one per frame".
do
	local s = spec { min_interval = 0 }
	h.check("a zero interval never gates", cue.gate(s, 100, 100, nil))
end

do
	local s = spec { radius = 40 }
	h.check("inside the radius is allowed", cue.gate(s, 100, nil, 39.9))
	h.check("at the radius is allowed", cue.gate(s, 100, nil, 40))
	h.check("past the radius is culled", not cue.gate(s, 100, nil, 40.1))
end

-- Either reason alone is enough; neither cancels the other.
do
	local s = spec { min_interval = 1, radius = 40 }
	h.check("cooldown still applies in range", not cue.gate(s, 100.5, 100, 10))
	h.check("distance still applies off cooldown", not cue.gate(s, 200, 100, 999))
end

-- =============================== preemption ================================

local function voice(priority, started)
	return { sound = nil, spec = spec { priority = priority }, started = started }
end

-- THE ONE THAT MATTERS. An equal priority is not a victim: a burst of cues of
-- one kind would otherwise evict its own predecessor every time, so twelve
-- sounds arrive and one is heard.
do
	local list = { voice(cue.PRIORITY.ROUTINE, 1), voice(cue.PRIORITY.ROUTINE, 2) }
	h.check("an equal priority is never preempted", cue.weakest(list, cue.PRIORITY.ROUTINE) == nil)
	h.check("a higher priority is never preempted", cue.weakest(list, cue.PRIORITY.BACKGROUND) == nil)
end

do
	local quiet = voice(cue.PRIORITY.BACKGROUND, 5)
	local list = { voice(cue.PRIORITY.IMPORTANT, 1), quiet, voice(cue.PRIORITY.ROUTINE, 2) }
	h.check("the lowest priority is the victim", cue.weakest(list, cue.PRIORITY.URGENT) == quiet)
end

-- Started LAST is not the victim; started first is. The oldest voice is the
-- one furthest through its own playback and the one already heard.
do
	local oldest = voice(cue.PRIORITY.BACKGROUND, 1)
	local list = { voice(cue.PRIORITY.BACKGROUND, 3), oldest, voice(cue.PRIORITY.BACKGROUND, 2) }
	h.check("among equals the oldest goes", cue.weakest(list, cue.PRIORITY.ROUTINE) == oldest)
end

-- Age does not beat priority: a fresh BACKGROUND voice goes before an ancient
-- IMPORTANT one.
do
	local fresh_background = voice(cue.PRIORITY.BACKGROUND, 999)
	local list = { voice(cue.PRIORITY.IMPORTANT, 1), fresh_background }
	h.check("priority outranks age", cue.weakest(list, cue.PRIORITY.URGENT) == fresh_background)
end

do
	h.check("an empty list has no victim", cue.weakest({}, cue.PRIORITY.URGENT) == nil)
end

-- ================================ bed decay ================================

-- Halving, so the fade sounds like a constant rate rather than a cliff
-- followed by a long tail.
do
	h.equals("a sweep halves the gain", cue.decay(0.8, 1), 0.4)
	h.equals("and halves it again", cue.decay(0.4, 1), 0.2)
end

-- THE FLOOR IS RELATIVE. A halving never reaches zero, so without a floor
-- every bed ever started stays alive forever at an inaudible volume, holding
-- its Sound and keeping the sweeper scheduled.
do
	h.check("a bed at the floor is destroyed", cue.decay(0.01, 1) == nil)
end

-- A quiet bed and a loud one must die at the same point in their OWN fade. An
-- absolute floor would keep the loud one alive for several more sweeps and
-- take the quiet one out immediately -- which is the same bug twice.
do
	local loud = 1
	local quiet = 0.05
	local steps = function(volume)
		local gain, count = volume, 0
		while gain ~= nil do
			gain = cue.decay(gain, volume)
			count += 1
		end
		return count
	end
	h.equals("a quiet bed fades in as many steps as a loud one", steps(quiet), steps(loud))
end

h.done()
