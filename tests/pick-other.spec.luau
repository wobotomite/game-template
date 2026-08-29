--!nocheck
-- util/tables/pick-other: the "don't repeat the last one" draw.
-- Run with:
--   lune run tests/pick-other.spec.luau
--
-- WHY THIS EXISTS. The function it replaced was almost right, and almost right
-- is the hard case to notice: a retry-once draw repeats a quarter of the time
-- on a two-track playlist, which sounds like bad luck rather than a bug and
-- would never be reported. The properties below are the ones that separate
-- "usually does not repeat" from "cannot repeat".
--
-- THE OFF-BY-ONE IS THE WHOLE RISK. `if index >= at` written as `if index > at`
-- puts `current` back in the draw for exactly one slot, and drops the last
-- element entirely. Both the never-repeats check and the distribution check
-- below fail on it -- deliberately, since one assertion catching it could be a
-- coincidence.

local h = require "./harness"
local env = require "./roblox-env"

h.title "pick-other:"

local pick_other = env.load "ReplicatedStorage.Util.tables.pick-other"

-- A deterministic stand-in with the one method `pick_other` calls, written here
-- rather than reaching for the environment's Random so this spec does not
-- depend on how that is implemented -- the same choice weighted-random.spec
-- makes, and for the same reason.
local function fake_random(seed: number)
	local state = seed
	return {
		-- HIGH bits, never `% n`. An LCG's low bits have a period as short as
		-- 2, and a modulo here would hand this spec a rigged distribution to
		-- measure -- which is exactly how weighted-random.spec once reported a
		-- broken alias table that was a broken RNG.
		NextInteger = function(_self, min: number, max: number): number
			state = (state * 1103515245 + 12345) % 2147483648
			return min + math.floor(state / 2147483648 * (max - min + 1))
		end,
	}
end

-- ============================== edge cases ===============================

do
	h.equals("an empty list has nothing to pick", pick_other({}, "a"), nil)

	-- A one-track playlist repeating is not a bug. Returning nil would stop the
	-- music, which is worse than hearing the same track twice.
	h.equals("a single element is returned even when it IS current", pick_other({ "a" }, "a"), "a")
	h.equals("a single element is returned when current is absent", pick_other({ "a" }, "zzz"), "a")
	h.equals("nil current is an ordinary draw", pick_other({ "a" }, nil), "a")
end

-- ========================= it CANNOT return current =======================

do
	local items = { "a", "b", "c", "d" }
	local rng = fake_random(1234)
	local draws = 0
	local repeats = 0
	for i = 1, 4000 do
		-- rotate which element is "current" so no single slot is special
		local current = items[(i % 4) + 1]
		local got = pick_other(items, current, rng)
		draws += 1
		if got == current then
			repeats += 1
		end
	end
	h.saw("draws taken", draws, 4000)
	h.equals("never returns the element it was told to avoid", repeats, 0)
end

-- =========================== uniform over the rest ========================

do
	-- With `current` excluded, the other three must be equally likely. A missing
	-- or mis-shifted index shows up here as a zero bucket or a doubled one.
	local items = { "a", "b", "c", "d" }
	local rng = fake_random(99)
	local counts = { a = 0, b = 0, c = 0, d = 0 }
	local N = 9000
	for _ = 1, N do
		local got = pick_other(items, "a", rng)
		counts[got] = (counts[got] or 0) + 1
	end

	h.equals("the excluded element never appears", counts.a, 0)
	local expected = N / 3
	local tolerance = expected * 0.12
	for _, key in { "b", "c", "d" } do
		h.check(
			`{key} lands within 12% of an even share`,
			math.abs(counts[key] - expected) < tolerance,
			`{key}={counts[key]}, expected ~{math.floor(expected)}`
		)
	end
end

-- ================== current absent: every element reachable ===============

do
	-- Nothing to exclude, so this is a plain uniform draw and the LAST element
	-- must be reachable -- dropping it is the other half of the off-by-one.
	local items = { "a", "b", "c", "d" }
	local rng = fake_random(7)
	local seen = {}
	for _ = 1, 4000 do
		seen[pick_other(items, "not-in-the-list", rng)] = true
	end
	for _, key in { "a", "b", "c", "d" } do
		h.check(`{key} is reachable when current is absent`, seen[key] == true)
	end
end

-- ============================== duplicates ================================

do
	-- Documented behaviour: exclusion is by SLOT, so a second copy of `current`
	-- stays in the draw. Pinned because it is surprising, not because it is
	-- desirable -- if this ever changes, it should change deliberately.
	local items = { "a", "a", "b" }
	local rng = fake_random(5)
	local saw_duplicate = false
	for _ = 1, 2000 do
		if pick_other(items, "a", rng) == "a" then
			saw_duplicate = true
			break
		end
	end
	h.check("a duplicate of current can still be drawn (by-slot exclusion)", saw_duplicate)
end

-- ============================= repeatability ==============================

do
	local items = { "a", "b", "c", "d" }
	local first, second = {}, {}
	local r1 = fake_random(2024)
	local r2 = fake_random(2024)
	for i = 1, 50 do
		first[i] = pick_other(items, "a", r1)
		second[i] = pick_other(items, "a", r2)
	end
	local identical = true
	for i = 1, 50 do
		if first[i] ~= second[i] then
			identical = false
			break
		end
	end
	h.check("the same seed yields the same sequence", identical)
end

h.done()
