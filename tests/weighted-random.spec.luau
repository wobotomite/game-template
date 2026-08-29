--!nocheck
-- util/numbers/weighted-random: does the sampler actually respect the weights?
-- Run with:
--   lune run tests/weighted-random.spec.luau
--
-- WHY THIS EXISTS. `build` implements the alias method: it normalises the
-- weights, then pairs the light entries with the heavy ones into a prob/alias
-- pair of arrays so a sample costs one integer roll and one float roll. It is a
-- genuinely clever algorithm, and its failure mode is that **it still returns
-- plausible values**. Get the stack juggling slightly wrong and you do not get
-- an error or a nil — you get a loot table that is quietly 15% off, forever, in
-- a direction nobody notices until someone counts.
--
-- Nothing else in the toolchain has an opinion about a distribution. So the
-- test is empirical: sample a lot, and compare against the weights.
--
-- THE RNG IS INJECTED, not seeded globally. `sample` takes a Random as its
-- third argument precisely so a spec can hand it a repeatable one — otherwise
-- this file would be the kind of test that fails once a fortnight and teaches
-- people to re-run it rather than read it.

local h = require "./harness"
local env = require "./roblox-env"

h.title "weighted-random:"

local weighted = env.load "ReplicatedStorage.Util.numbers.weighted-random"

-- A deterministic stand-in with the two methods `sample` calls. Written here
-- rather than reaching for the environment's Random so this spec does not
-- depend on how that is implemented.
local function fake_random(seed: number)
	local state = seed
	local function step()
		state = (state * 1103515245 + 12345) % 2147483648
		return state
	end
	return {
		NextNumber = function(_self)
			return step() / 2147483648
		end,
		-- HIGH bits, never `% n`: see the note in roblox-env. An LCG's low bits
		-- have a period as short as 2, so `state % 4` can emit two of four
		-- values forever -- which this very spec reported as a broken
		-- distribution before the RNG was the suspect.
		NextInteger = function(_self, min: number, max: number)
			return min + math.floor(step() / 2147483648 * (max - min + 1))
		end,
	}
end

local SAMPLES = 60000

local function distribution(weights, luck: number?, seed: number?)
	local table_ = weighted.build(weights)
	local rng = fake_random(seed or 1)
	local counts: { [any]: number } = {}
	for _ = 1, SAMPLES do
		local key = weighted.sample(table_, luck, rng :: any)
		counts[key] = (counts[key] or 0) + 1
	end
	return counts
end

-- =========================== respects the weights =========================

do
	-- 10 / 30 / 60. Deliberately uneven, and deliberately including an entry
	-- light enough to end up on the "small" stack.
	local counts = distribution { common = 60, uncommon = 30, rare = 10 }
	local total = counts.common + counts.uncommon + counts.rare
	h.equals("every sample landed on a real key", total, SAMPLES)

	local function share(key: string): number
		return counts[key] / SAMPLES * 100
	end

	-- 2 points of slack at 60k samples. Sampling error alone would be ~0.2pt;
	-- the rest is the LCG above, which has visible structure and lands about a
	-- point off on this table. Deterministic, so it cannot flake -- but the
	-- budget is sized so a later innocuous change cannot creep over it either.
	--
	-- Still far tighter than what it is guarding against: a mis-built alias
	-- table moves a share by TENS of points, not by ones.
	for key, want in { common = 60, uncommon = 30, rare = 10 } do
		local got = share(key)
		h.check(
			`{key} lands {want}% of the time (got {string.format("%.1f", got)}%)`,
			math.abs(got - want) < 2,
			`expected {want}% +/- 2`
		)
	end
end

do
	-- A single entry is the degenerate case the alias construction is most
	-- likely to get wrong, because neither stack ever has a partner.
	local counts = distribution { only = 5 }
	h.equals("a one-entry table always returns that entry", counts.only, SAMPLES)
end

do
	-- Equal weights must not drift. If the prob/alias pairing were biased, this
	-- is where it shows with no ambiguity about what "correct" means.
	local counts = distribution { a = 1, b = 1, c = 1, d = 1 }
	local worst = 0
	for _, key in { "a", "b", "c", "d" } do
		worst = math.max(worst, math.abs(counts[key] / SAMPLES * 100 - 25))
	end
	h.check(`four equal weights stay within 2pt of 25% (worst {string.format("%.1f", worst)})`, worst < 2)
end

-- ============================== determinism ===============================

do
	local weights = { a = 50, b = 30, c = 20 }
	local first = distribution(weights, nil, 7)
	local second = distribution(weights, nil, 7)
	local same = first.a == second.a and first.b == second.b and first.c == second.c
	h.check("the same seed produces the same distribution", same)

	local other = distribution(weights, nil, 99)
	h.check("a different seed produces a different one", first.a ~= other.a)
end

-- ================================= luck ===================================

-- `adjusted = weight ^ (1 / luck)`, so luck > 1 COMPRESSES the differences
-- between weights (a square root of 60 and of 10 are much closer together than
-- 60 and 10) and luck < 1 exaggerates them.
--
-- The direction is the thing worth pinning. Inverting that exponent is a
-- one-character mistake that still produces a working, plausible distribution —
-- it just makes luck do the opposite of what every call site believes, and no
-- test of "does it return a valid key" would notice.

do
	local weights = { common = 60, uncommon = 30, rare = 10 }
	local base = distribution(weights, nil, 3)
	local lucky = distribution(weights, 3, 3)
	local unlucky = distribution(weights, 0.4, 3)

	h.check(`luck > 1 makes the rare entry MORE likely ({base.rare} -> {lucky.rare})`, lucky.rare > base.rare)
	h.check(`luck > 1 makes the common entry less likely ({base.common} -> {lucky.common})`, lucky.common < base.common)
	h.check(`luck < 1 makes the rare entry LESS likely ({base.rare} -> {unlucky.rare})`, unlucky.rare < base.rare)
	h.check("luck = 1 is the unmodified path", distribution(weights, 1, 3).rare == base.rare)
end

h.done()
