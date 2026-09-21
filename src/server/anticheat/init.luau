const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const physics_step = require(ReplicatedStorage.Util.events["physics-step"])
const settings = require(ReplicatedStorage.Shared.settings)

const heuristics = require(script.heuristics)

-- Passive autofarm/exploit watch: a movement sampler plus whatever intent
-- streams the game chooses to tap, scored as DECAYING STRIKES so it only ever
-- kicks on sustained evidence.
--
-- Wire it up at boot and feed it the game's own input events:
--
--   const anticheat = require(ServerScriptService.Server.anticheat)
--   anticheat.init()
--   server_network.combat.punch:connect(function(player)
--       anticheat.note_intent(player, "punch")
--   end)
--   -- for a held input, only the off->on edge is a press:
--   server_network.combat.beam:connect(function(player, data)
--       anticheat.note_hold(player, "beam", data.active)
--   end)
--
-- sendbufs events take multiple listeners, so tapping a stream this way leaves
-- the real handler untouched.
--
-- Three signals:
--   speed      horizontal speed above the server's own WalkSpeed (x1.6 slack)
--              for 3 consecutive samples. THE LIMIT TRACKS Humanoid.WalkSpeed
--              rather than a constant, so every legitimate speed change the
--              game makes -- a slow effect, a buff, a catch-up boost, a debug
--              command -- stays inside it by construction instead of needing a
--              new exception each time.
--   blink      a single-sample teleport. Server-side teleports call forgive()
--              to re-anchor first; see the contract below.
--   metronome  intent cadence with inhumanly low variance. Only PRESS-shaped
--              events count. A timer-driven resend (an aim update, a held-input
--              heartbeat) is metronomic BY DESIGN and would flag every honest
--              player, which is what note_hold exists to prevent.
--
-- THE forgive() CONTRACT. Every server-initiated position change -- a spawn, an
-- out-of-bounds rescue, a checkpoint, a debug jump -- must call forgive(player)
-- or it reads as a blink. Miss one and the anticheat kicks players for a thing
-- the server did to them. Grep for every place that writes a character's CFrame
-- and check each one; there is no way to detect this from inside.

const SAMPLE_INTERVAL = 0.5 -- seconds between movement samples
const SPEED_LIMIT_SLACK = 1.6 -- multiplier over server WalkSpeed (jump arcs, shoves)
-- studs/s; below this the speed heuristic never flags, whatever WalkSpeed says.
--
-- DERIVED from the game's own top speed rather than written here. The floor
-- exists for movement the server does not spell out as `Humanoid.WalkSpeed` --
-- a vehicle, a launcher, a conveyor, a swim multiplier -- and a literal here
-- has no way to know about any of it. A game that adds a fast loadout and
-- forgets this number kicks its own players for using it; one that removes a
-- fast loadout leaves the floor above everything, and the speed heuristic
-- quietly stops detecting anything at all.
--
-- settings.character.TOP_SPEED x SLACK is 45 as shipped, which is exactly the
-- constant this replaced -- so nothing changes until a game raises it.
const SPEED_LIMIT_FLOOR = math.ceil(settings.character.TOP_SPEED * SPEED_LIMIT_SLACK)
const SPEED_SUSTAIN_SAMPLES = 3 -- consecutive hot samples before a strike
const BLINK_DISTANCE = 120 -- studs in one sample = teleport, not movement

-- What `observed_speed` keeps of the previous sample: half, so an old reading
-- is worth a quarter two samples later and nothing within a second. Sampling
-- is every SAMPLE_INTERVAL, and without the memory a reader that happens to
-- ask between two samples sees whatever the last one measured with no sense of
-- how stale it is; with it, a stale reading decays toward 0 instead.
const SPEED_MEMORY = 0.5

const METRONOME: heuristics.MetronomeConfig = table.freeze {
	min_events = 20,
	max_cv = 0.02,
	min_mean = 0.1, -- faster is the rate limiter's problem
	max_mean = 20, -- slower isn't farming
}
const METRONOME_RESET_GAP = 4 -- a human-length pause clears the window
const INTENT_BUFFER_CAP = 24

const STRIKE_DECAY_INTERVAL = 20 -- seconds per strike forgiven
const WARN_STRIKES = 2 -- server-side log + entry.suspect (never a Player attribute)
const KICK_STRIKES = 6

type Entry = {
	strikes: number,
	last_decay: number,
	last_position: Vector3?, -- nil re-anchors the next sample (forgive)
	hot_samples: number,
	observed_speed: number, -- decayed studs/s, server-measured; see observed_speed()
	-- Latch per held input, so only the off->on edge counts as a press.
	holds: { [string]: boolean },
	intents: { [string]: { number } },
	suspect: boolean,
}

const entries: { [Player]: Entry } = {}

function flag(player: Player, entry: Entry, amount: number, reason: string)
	entry.strikes += amount
	warn(`[anticheat] {player.Name}: {reason} (strikes {entry.strikes})`)
	-- SUSPICION STAYS ON THE SERVER. An earlier version also set an
	-- "AnticheatSuspect" attribute on the Player. Attributes REPLICATE, to
	-- every client including the suspected one, and nothing ever read it -- so
	-- its entire effect was to hand a cheater the one fact worth hiding: how
	-- many strikes they have, and how many are left before a kick. Back off,
	-- wait out STRIKE_DECAY_INTERVAL, resume. It broadcast the accusation to
	-- everyone else in the server too. If tooling needs this, read
	-- entry.suspect from a server script; never attribute it onto a player.
	if entry.strikes >= WARN_STRIKES and not entry.suspect then
		entry.suspect = true
		warn(`[anticheat] SUSPECT {player.Name} ({player.UserId}) crossed {WARN_STRIKES} strikes`)
	end
	if entry.strikes >= KICK_STRIKES then
		warn(`[anticheat] kicking {player.Name} ({player.UserId}): {reason}`)
		player:Kick "Suspicious automated activity detected."
	end
end

-- Ascending arrival timestamps per intent kind; a human-length pause resets
-- the window so only uninterrupted machine cadence ever fills it.
function note_intent(player: Player, kind: string)
	const entry = entries[player]
	if not entry then
		return
	end
	const now = os.clock()
	local times = entry.intents[kind]
	if not times then
		times = {}
		entry.intents[kind] = times
	end
	const last = times[#times]
	if last and now - last > METRONOME_RESET_GAP then
		table.clear(times)
	end
	table.insert(times, now)
	if #times > INTENT_BUFFER_CAP then
		table.remove(times, 1)
	end
	if heuristics.is_metronomic(times, METRONOME) then
		-- Keep only the newest timestamp: the next verdict needs a whole
		-- fresh window of continued perfect cadence.
		const newest = times[#times]
		table.clear(times)
		times[1] = newest
		flag(player, entry, 1, `metronomic "{kind}" cadence`)
	end
end

-- A held input (a beam, a sprint). Only the off->on EDGE is a press: the
-- stream itself is usually a timer-driven resend, and scoring every message
-- would flag every honest player as a metronome.
function note_hold(player: Player, kind: string, active: boolean)
	const entry = entries[player]
	if not entry then
		return
	end
	if active and not entry.holds[kind] then
		note_intent(player, kind)
	end
	entry.holds[kind] = active
end

-- How fast the SERVER last saw this player actually move, in studs/s, decayed
-- toward 0 between samples. 0 for a player with no living character, and 0 for
-- one this never sampled.
--
-- WHY ANYTHING WOULD ASK. The obvious source of a player's speed is
-- `root.AssemblyLinearVelocity`, and on a character the server does not own it
-- is the last value that player's client replicated -- which is 0 for an
-- assembly that has gone to sleep, and 0 for a client that simply has not sent
-- one recently. A server rule written against it ("a thrown object may not
-- outrun its thrower by more than X") therefore punishes a moving player at
-- random. This is measured from position deltas the server took itself, so it
-- cannot be stalled by withholding replication, and it is a FLOOR to be taken
-- alongside the velocity rather than a replacement for it: it lags a real
-- change by up to a sample.
--
-- Unlike the speed heuristic below this is the full 3D magnitude. The
-- heuristic drops Y because falling is not cheating; a caller asking how fast
-- a body is moving wants the speed it is really moving at.
function observed_speed(player: Player): number
	const entry = entries[player]
	return if entry then entry.observed_speed else 0
end

-- Call after ANY server-initiated position change -- spawn, respawn,
-- out-of-bounds rescue, checkpoint, cutscene, debug jump -- so the jump does
-- not read as a blink. See the contract note at the top: a missed call kicks
-- players for something the server did to them.
function forgive(player: Player)
	const entry = entries[player]
	if entry then
		entry.last_position = nil
		entry.hot_samples = 0
	end
end

function sample_movement(entry: Entry, player: Player, dt: number)
	const character = player.Character
	const root = character and character:FindFirstChild "HumanoidRootPart" :: BasePart?
	const humanoid = character and character:FindFirstChildOfClass "Humanoid"
	if not root or not humanoid or humanoid.Health <= 0 then
		-- Dead characters ragdoll and get flung; don't score them.
		entry.last_position = nil
		entry.hot_samples = 0
		-- Straight to 0, not decayed: with no living body there is nothing
		-- moving, and a reader that gates on speed would otherwise keep seeing
		-- the corpse's last flung reading for the next second.
		entry.observed_speed = 0
		return
	end
	const position = root.Position
	const last = entry.last_position
	entry.last_position = position
	if not last then
		return
	end
	const offset = position - last
	const flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	-- max(measured, decayed) rather than a plain assignment: a player who is
	-- moving steadily reads the same either way, and the difference is the
	-- sample where they stop dead -- a rule reading this mid-stop should still
	-- see the speed they were carrying a moment ago, not 0.
	entry.observed_speed = math.max(offset.Magnitude / dt, entry.observed_speed * SPEED_MEMORY)
	const limit = math.max(SPEED_LIMIT_FLOOR, humanoid.WalkSpeed * SPEED_LIMIT_SLACK)
	-- Blink is the FLAT jump against a threshold that scales with the sample.
	-- Two false-positive classes forced both halves of that sentence:
	--   * dt here is physics-step's ACCUMULATED time, not a fixed 0.5s -- a
	--     backgrounded Studio server ticks at ~19% duty, so dt reaches ~2.6s,
	--     where a legal 45 studs/s covers 117 of a flat 120-stud threshold;
	--     `limit * dt * 2` keeps the allowance in the same units as the speed
	--     check instead of racing it.
	--   * the full 3D magnitude counted FREE-FALL: an out-of-bounds drop passes
	--     120 studs/sample after ~1.1s of falling, and a rescue loop polling at
	--     1Hz forgives it too late, so an unlucky phase cost 2 strikes for
	--     falling in a hole.
	-- Neither costs detection that matters: a teleport-to-target hop is
	-- horizontal and far past the floor, and a vertical-only teleport under
	-- BLINK_DISTANCE was never detectable here to begin with.
	if flat > math.max(BLINK_DISTANCE, limit * dt * 2) then
		entry.hot_samples = 0
		flag(player, entry, 2, `blink: {math.floor(flat)} studs in {string.format("%.2f", dt)}s`)
		return
	end
	if flat / dt > limit then
		entry.hot_samples += 1
		if entry.hot_samples >= SPEED_SUSTAIN_SAMPLES then
			entry.hot_samples = 0
			flag(player, entry, 2, `sustained speed {math.floor(flat / dt)} studs/s (limit {math.floor(limit)})`)
		end
	else
		entry.hot_samples = 0
	end
end

local started = false
function init()
	if started then
		return
	end
	started = true

	observe_players(function(player: Player): () -> ()
		entries[player] = {
			strikes = 0,
			last_decay = os.clock(),
			last_position = nil :: Vector3?,
			hot_samples = 0,
			observed_speed = 0,
			holds = {},
			intents = {},
			suspect = false,
		}
		return function()
			entries[player] = nil
		end
	end)

	physics_step(SAMPLE_INTERVAL):connect(function(dt: number)
		const now = os.clock()
		for player, entry in entries do
			sample_movement(entry, player, dt)
			if entry.strikes > 0 and now - entry.last_decay >= STRIKE_DECAY_INTERVAL then
				entry.last_decay = now
				entry.strikes -= 1
			elseif entry.strikes == 0 then
				entry.last_decay = now
			end
		end
	end)
end

return table.freeze {
	init = init,
	note_intent = note_intent,
	note_hold = note_hold,
	observed_speed = observed_speed,
	forgive = forgive,
}
