const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const debug_flags = require(ReplicatedStorage.Shared.records["debug-flags"])
const step_stats = require(ReplicatedStorage.Util.events["step-stats"])

-- Frame-hitch watchdog: warns, with context, on a frame long enough for a
-- player to feel it.
--
--   const frame_watch = require(ReplicatedStorage.Client.debug["frame-watch"])
--   frame_watch.start()
--   frame_watch.add_context(function()
--       return `level={current_level} enemies={enemy_count}`
--   end)
--
-- WHY BOTHER, given a profiler exists. A profiler tells you what a frame costs
-- while you are watching it. This tells you what was on screen during a hitch
-- that happened to somebody else, on a connection you do not have, in a
-- situation you cannot reproduce. In the game this came from, the client's own
-- Luau was profiled end to end and no path cost more than ~2ms in a frame:
-- server heartbeat clean, heap flat, allocation ~9 KB/s. The stutters players
-- reported did not reproduce in Studio at all -- a backgrounded Studio window
-- throttles to a hard 15fps, which masks everything. The only way left to catch
-- it was to record it in a real session.
--
-- ============================ THE ATTRIBUTION =============================
--
-- The reason a captured line is worth pasting into a bug report is `step=`. It
-- comes from util/events/step-stats, which times the dispatch of the shared
-- step signals:
--
--   step= is a FRACTION of the frame   the game's own per-frame Luau is not the
--                                      cause. No amount of optimising it will
--                                      help; look at rendering, streaming, or
--                                      the network.
--   step= is MOST of the frame         a listener on one of the shared step
--                                      signals is the culprit.
--
-- Without that number, "a 300ms frame happened in level 3" is another round of
-- guessing. With it, the same line rules out half the search space.
--
-- ========================= WHAT IS ALWAYS ON, AND WHY =====================
--
-- DETECTION is always on. It costs one clock read and one compare per frame,
-- and the whole point of a watchdog is to be present on the frame you needed
-- it: a diagnostic you have to remember to enable is not running when the thing
-- you cannot reproduce finally happens.
--
-- The PERIODIC DIGEST is behind `records/debug-flags`, because that one is for
-- someone actively looking. A live player does not need a console line every
-- two minutes; you, watching a session, do.
--
-- That split is deliberate rather than a compromise. Ask of any diagnostic:
-- would you rather have it running for everyone, or have it be quiet? The
-- answer differs for "something just went wrong" and "here is a periodic
-- summary", and gating both the same way gets one of them wrong.

-- A frame this long is a stutter a player actually feels (three dropped frames
-- at 60fps).
const WARN_FRAME = 0.1
-- Recorded silently: one dropped frame at 30fps.
const NOTE_FRAME = 0.033
-- One hitch usually arrives with friends, and a wall of identical warnings
-- buries the first (most useful) one.
const WARN_COOLDOWN = 5
const DIGEST_EVERY = 120

-- Extra context, supplied by the game. Called ONLY on a frame that is already
-- bad and already past the cooldown, so it can afford to be a little
-- expensive -- but it must not throw: a diagnostic that takes the frame down
-- is worse than the hitch it was reporting.
local context_providers: { () -> string } = {}

function add_context(provider: () -> string)
	table.insert(context_providers, provider)
end

function context(): string
	-- Parts and LOOSE (unanchored) parts, not workspace children: a whole level
	-- can be one child, so the child count is nearly meaningless. Parts are
	-- what the renderer and the physics solver actually see, and a hitch at
	-- parts=4000 reads very differently from the same hitch at parts=800.
	-- `loose` is the physics question specifically -- ragdolls, debris, and
	-- anything else still simulating.
	local parts, loose = 0, 0
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA "BasePart" then
			parts += 1
			if not descendant.Anchored then
				loose += 1
			end
		end
	end

	-- A nicety, and a diagnostic must never be the thing that throws: take the
	-- ping if the API is there, shrug if it is not.
	--
	-- `Players.LocalPlayer` READ HERE, not captured at module scope. A watchdog
	-- is required early by definition -- it wants to be running before the
	-- thing it watches -- and early enough, LocalPlayer is still nil. Captured
	-- once, it is nil for the rest of the session and every hitch line reports
	-- `ping=?` forever, which reads as an engine that will not answer rather
	-- than as this module asking too soon.
	local ping = "?"
	const ok_ping, seconds = pcall(function()
		return (Players.LocalPlayer :: any):GetNetworkPing()
	end)
	if ok_ping and type(seconds) == "number" then
		ping = tostring(math.floor(seconds * 1000))
	end

	const step_ms = string.format("%.1f", (step_stats.render + step_stats.physics) * 1000)
	const heap_kb = math.floor(gcinfo())
	local line = `parts={parts} loose={loose} heap={heap_kb}KB ping={ping}ms step={step_ms}ms`

	for _, provider in context_providers do
		const ok, extra = pcall(provider)
		if ok and type(extra) == "string" then
			line ..= ` {extra}`
		end
	end
	return line
end

-- ============================ THE HISTOGRAM ===============================
--
-- The warning above answers "what was on screen when it hitched". This answers
-- the other question, the one a hitch log cannot: WHAT DID THE LAST TWO
-- MINUTES ACTUALLY FEEL LIKE. A session with four warned frames and a session
-- that spent a third of its time at 20fps both produce a handful of warnings;
-- only one of them is a game nobody wants to play.
--
-- Buckets, not an average. An average of 55fps is produced equally by a
-- steady 55 and by alternating 110 and 30, and the second is the one players
-- describe as choppy. A distribution cannot hide that.
--
-- The edges sit BELOW their nominal rate (55 for 60, 28 for 30) because a
-- frame timed at exactly 1/60 is the exception on real hardware -- vsync
-- jitter puts a healthy 60fps client a hair either side, and an exact boundary
-- would scatter one steady rate across two buckets.
const BUCKET_60 = 1 / 55
const BUCKET_30 = 1 / 28
const BUCKET_20 = 1 / 18
const BUCKET_10 = 1 / 9

const buckets = { at_60 = 0, at_30 = 0, at_20 = 0, at_10 = 0, below_10 = 0 }

function record_frame(dt: number)
	if dt <= BUCKET_60 then
		buckets.at_60 += 1
	elseif dt <= BUCKET_30 then
		buckets.at_30 += 1
	elseif dt <= BUCKET_20 then
		buckets.at_20 += 1
	elseif dt <= BUCKET_10 then
		buckets.at_10 += 1
	else
		buckets.below_10 += 1
	end
end

local worst = 0
local noted = 0
local warned = 0
local frames = 0
local last_warn_at = 0
local last_digest_at = 0

local started = false
function start()
	if started or not RunService:IsClient() then
		return
	end
	started = true
	last_digest_at = os.clock()

	-- RAW RenderStepped rather than the render-step util, deliberately: this is
	-- a watchdog for the frame, and it must not ride the same shared dispatcher
	-- whose listeners it exists to catch misbehaving.
	RunService.RenderStepped:Connect(function(dt: number)
		frames += 1
		record_frame(dt)
		-- The clock read and the digest check sit OUTSIDE the slow-frame branch
		-- on purpose. They used to be behind an early return for fast frames,
		-- which meant the counters could only reset on a frame that was itself
		-- slow -- so a mostly healthy client accumulated until it happened to
		-- hit one, then reported an hour of frames under a "last 120s" heading.
		-- A diagnostic that misstates its own sample window is worse than none.
		const now = os.clock()
		if dt >= NOTE_FRAME then
			noted += 1
			if dt > worst then
				worst = dt
			end
			if dt >= WARN_FRAME and now - last_warn_at >= WARN_COOLDOWN then
				last_warn_at = now
				warned += 1
				warn(`[frame-watch] {math.floor(dt * 1000)}ms frame — {context()}`)
			end
		end

		if now - last_digest_at >= DIGEST_EVERY then
			last_digest_at = now
			-- Only when there was something to report, so a clean session stays
			-- silent rather than printing a line every two minutes forever.
			if noted > 0 and debug_flags.draw_enabled() then
				const note_ms = math.floor(NOTE_FRAME * 1000)
				const worst_ms = math.floor(worst * 1000)
				warn(
					`[frame-watch] last {DIGEST_EVERY}s: {noted}/{frames} frames over {note_ms}ms, `
						.. `worst {worst_ms}ms, {warned} warned`
				)
			end
			worst, noted, frames, warned = 0, 0, 0, 0
			-- The histogram rides the SAME window as the digest, so a reader
			-- who takes both gets one sample period rather than two that
			-- overlap by an unknown amount.
			buckets.at_60, buckets.at_30, buckets.at_20 = 0, 0, 0
			buckets.at_10, buckets.below_10 = 0, 0
		end
	end)
end

export type Histogram = {
	frames: number,
	worst: number,
	at_60: number,
	at_30: number,
	at_20: number,
	at_10: number,
	below_10: number,
}

-- The current window's distribution, for a debug readout or a session report.
-- A COPY: the live table is reset on the digest boundary, and a caller holding
-- the real one would watch its numbers go to zero underneath it.
function histogram(): Histogram
	return {
		frames = frames,
		worst = worst,
		at_60 = buckets.at_60,
		at_30 = buckets.at_30,
		at_20 = buckets.at_20,
		at_10 = buckets.at_10,
		below_10 = buckets.below_10,
	}
end

return table.freeze {
	start = start,
	add_context = add_context,
	context = context,
	histogram = histogram,
}
