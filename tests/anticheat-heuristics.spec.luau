--!nocheck
-- The anticheat's timing heuristics, exercised headless.
-- Run with:
--   lune run tests/anticheat-heuristics.spec.luau
--
-- THE POINT IS THE FALSE-POSITIVE BOUNDARY. A metronome detector that catches
-- macros and also catches people is worse than none at all: it kicks paying
-- players for being good at a rhythm game, and the report that reaches you is
-- "I got banned for no reason", which is indistinguishable from every false
-- report. So the cases below are mostly about humans NOT being flagged --
-- including a human mashing against a client-side cooldown gate, which
-- quantizes their intervals and is the closest a person gets to a timer.
--
-- Note how the module under test is loaded. It is a real require through
-- `roblox-env`, not a regex extraction: `src/server/anticheat/heuristics.luau`
-- deliberately touches no Roblox API precisely so it can be tested this way,
-- and keeping the pure timing maths in its own module is what makes that
-- possible. Do the same with anything whose correctness is arithmetic.

local h = require "./harness"
local env = require "./roblox-env"

h.title "anticheat heuristics:"

local heuristics = env.load "ServerScriptService.Server.anticheat.heuristics"

-- READ THE CONFIG FROM THE SOURCE, do not restate it. A spec that hardcodes
-- `max_cv = 0.02` keeps passing after somebody loosens the real threshold to
-- 0.2 -- it proves the numbers it made up are consistent with themselves, and
-- says nothing about the program. The parse is guarded below so it cannot fail
-- silently either.
local anticheat_source = h.strip(h.read "src/server/anticheat/init.luau")
local metronome_body = h.block_after(anticheat_source, "const METRONOME")
h.check("the METRONOME config was found in anticheat/init.luau", metronome_body ~= nil)

local METRONOME = {}
for key, value in (metronome_body or ""):gmatch "([%a_][%w_]*)%s*=%s*(-?[%d%.]+)" do
	METRONOME[key] = tonumber(value)
end

local parsed = 0
for _ in METRONOME do
	parsed += 1
end
h.saw("config keys parsed", parsed, 4)

-- Deterministic LCG, so the spec can never flake. A timing spec that fails one
-- run in fifty is a spec people learn to re-run rather than read.
local seed = 42
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function series(count: number, interval: number, jitter: number): { number }
	local times, at = {}, 0
	for _ = 1, count do
		at += interval + (rand() - 0.5) * 2 * jitter
		table.insert(times, at)
	end
	return times
end

-- ============================== the cases =================================

-- A macro: a fixed timer, plus the jitter its packets pick up on the way here.
h.check("a perfect timer is metronomic", heuristics.is_metronomic(series(30, 0.5, 0), METRONOME) == true)
h.check(
	"a timer with realistic network jitter is still metronomic",
	heuristics.is_metronomic(series(30, 0.5, 0.004), METRONOME) == true
)

-- A person. Human clicking bottoms out around cv 0.05 even when they are
-- trying to be regular.
h.check("a human rhythm is not metronomic", heuristics.is_metronomic(series(30, 0.5, 0.06), METRONOME) == false)
h.check("a human mashing is not metronomic", heuristics.is_metronomic(series(30, 0.18, 0.05), METRONOME) == false)

-- The nastiest false positive available: a client-side cooldown gate quantizes
-- a masher's intervals toward the cooldown itself, which is a timer.
local gated = {}
do
	local at, cooldown = 0, 0.4
	for _ = 1, 30 do
		-- They press early most of the time, so the gate decides -- but not
		-- every time, and that residual is what keeps a person a person.
		at += cooldown + math.max(0, (rand() - 0.7) * 0.25)
		table.insert(gated, at)
	end
end
h.check("a masher against a cooldown gate is not metronomic", heuristics.is_metronomic(gated, METRONOME) == false)

-- Verdicts must be impossible before there is evidence for one.
h.check(
	"too few events cannot be metronomic",
	heuristics.is_metronomic(series(METRONOME.min_events - 1, 0.5, 0), METRONOME) == false
)
h.check(
	"a cadence faster than min_mean is the rate limiter's problem, not this one",
	heuristics.is_metronomic(series(30, METRONOME.min_mean / 2, 0), METRONOME) == false
)
h.check(
	"a cadence slower than max_mean is not farming",
	heuristics.is_metronomic(series(30, METRONOME.max_mean * 2, 0), METRONOME) == false
)

-- Degenerate inputs, which arrive in practice the moment a buffer is cleared.
h.check("an empty series is not metronomic", heuristics.is_metronomic({}, METRONOME) == false)
h.check("a single event is not metronomic", heuristics.is_metronomic({ 1 }, METRONOME) == false)
h.check("interval_stats of one timestamp is nil", heuristics.interval_stats { 1 } == nil)

local stats = heuristics.interval_stats { 0, 1, 2, 3 }
h.check("interval_stats counts intervals, not events", stats ~= nil and stats.count == 3)
h.check("a constant series has zero variation", stats ~= nil and stats.cv == 0)

h.done()
