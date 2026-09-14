--!nocheck
-- The three util additions that are pure enough to pin headlessly:
-- `numbers/approach`, `strings/escape-rich-text` and `numbers/weighted-random`'s
-- new `index_at`. Run with:
--   lune run tests/util-additions.spec.luau
--
-- WHY THESE THREE AND NOT THE REST. Most of what landed alongside them is about
-- Instances, connections or the vide graph, and a Lune process has none of
-- those -- pinning them here would mean pinning a fake. These three are
-- arithmetic and string work with no engine surface at all, so what this spec
-- checks is exactly what ships.
--
-- And all three share a failure mode that makes them worth a spec rather than a
-- read-through: THEY RETURN A PLAUSIBLE ANSWER WHEN THEY ARE WRONG. A decay
-- with the sign flipped still moves the value. An escape with the `&` pass in
-- the wrong place still returns an escaped-looking string. A weighted pick with
-- the comparison off by one still returns a valid index. Nothing throws, so the
-- only way to notice is to compare against the closed form.

local h = require "./harness"
local env = require "./roblox-env"

h.title "util additions:"

local approach = env.load "ReplicatedStorage.Util.numbers.approach"
local escape_rich_text = env.load "ReplicatedStorage.Util.strings.escape-rich-text"
local weighted = env.load "ReplicatedStorage.Util.numbers.weighted-random"

-- ============================== approach ==================================

do
	-- Convergence, stepped at a fixed 60fps delta. Each step must move toward
	-- the target and never past it: overshoot is what a lerp with a
	-- badly-scaled alpha does, and it is the thing an eyeball test forgives
	-- because the value still ends up roughly right.
	local DT = 1 / 60
	local RATE = 8
	local value = 0
	local monotonic = true
	local overshot = false
	for _ = 1, 120 do
		local next_value = approach.number(value, 100, RATE, DT)
		if next_value < value then
			monotonic = false
		end
		if next_value > 100 then
			overshot = true
		end
		value = next_value
	end
	h.check("approach.number moves toward the target on every step", monotonic)
	h.check("approach.number never overshoots", not overshot)
	h.check(
		`two seconds at rate 8 lands within 0.01 of the target (got {string.format("%.4f", value)})`,
		math.abs(value - 100) < 0.01
	)

	-- It converges but does NOT arrive -- the module says so in its header, and
	-- a call site that waits for equality would spin forever. Pinned so that
	-- claim cannot quietly stop being true.
	h.check("...without ever reaching it exactly", value ~= 100)
end

do
	-- FRAMERATE INDEPENDENCE is the entire reason this function exists rather
	-- than a lerp. Two half-steps must land where one full step does; a
	-- per-call fraction would land somewhere else, and only on the machines
	-- that happen to run at the other framerate.
	local one_step = approach.number(0, 1, 5, 1 / 60)
	local half = approach.number(0, 1, 5, 1 / 120)
	local two_steps = approach.number(half, 1, 5, 1 / 120)
	h.check(
		`one 60fps step == two 120fps steps ({string.format("%.9f", one_step)} vs {string.format("%.9f", two_steps)})`,
		math.abs(one_step - two_steps) < 1e-9
	)
end

do
	-- `most_of_gap` has to stay the same curve as the two appliers, because its
	-- whole purpose is to let a caller do the blend itself (a CFrame:Lerp, a
	-- Color3) without the two drifting apart. Compared against the closed form
	-- rather than against a recorded number so this still means something if
	-- the implementation is rewritten.
	local worst = 0
	for _, rate in { 0.5, 1, 5, 12, 30 } do
		for _, dt in { 1 / 240, 1 / 120, 1 / 60, 1 / 30, 0.5 } do
			worst = math.max(worst, math.abs(approach.most_of_gap(rate, dt) - (1 - math.exp(-rate * dt))))
		end
	end
	h.check(`most_of_gap matches 1 - exp(-rate * dt) across 25 pairs (worst {worst})`, worst < 1e-12)

	-- And it is the SAME fraction the appliers use: blending by hand must give
	-- the same answer as calling `approach.number`.
	local by_hand = 0 + (100 - 0) * approach.most_of_gap(9, 1 / 60)
	h.check(
		"blending by most_of_gap agrees with approach.number",
		math.abs(by_hand - approach.number(0, 100, 9, 1 / 60)) < 1e-9
	)
end

do
	-- A clock that went backwards must do NOTHING, not diverge. `exp` of a
	-- positive exponent grows without bound, so an unclamped negative delta
	-- throws the value away from the target instead of leaving it alone -- the
	-- single worst response available.
	h.equals("a negative dt leaves the value where it is", approach.number(7, 100, 5, -1), 7)
	h.equals("a zero dt leaves the value where it is", approach.number(7, 100, 5, 0), 7)
	h.equals("most_of_gap of a negative dt is zero", approach.most_of_gap(5, -1), 0)
end

-- =========================== escape-rich-text =============================

do
	h.equals("& becomes &amp;", escape_rich_text "fish & chips", "fish &amp; chips")
	h.equals("< becomes &lt;", escape_rich_text "<b>", "&lt;b&gt;")
	h.equals("> becomes &gt;", escape_rich_text "a > b", "a &gt; b")
	h.equals('" becomes &quot;', escape_rich_text 'say "hi"', "say &quot;hi&quot;")
	h.equals("' becomes &apos;", escape_rich_text "it's", "it&apos;s")

	-- THE ORDERING CHECK. `&` has to be escaped FIRST, or the `&` of the `&lt;`
	-- this function just produced gets escaped in turn and the label renders
	-- the literal text "&lt;b&gt;" instead of showing "<b>". Reordering the
	-- gsub chain is a harmless-looking edit that no other case here catches,
	-- because every other input contains at most one special character.
	h.equals("a name containing markup escapes once, not twice", escape_rich_text "<b>", "&lt;b&gt;")
	h.equals("an already-escaped entity is escaped again, not left alone", escape_rich_text "&lt;", "&amp;lt;")

	-- Plain text must come back byte-identical: this runs on every display name
	-- in the game, and the overwhelming majority contain nothing to escape.
	local plain = "Player1 collected 12 coins (nice)"
	h.equals("plain text is returned unchanged", escape_rich_text(plain), plain)
	h.equals("an empty string is returned unchanged", escape_rich_text "", "")

	-- One return value, not two. `gsub` hands back a replacement COUNT as its
	-- second result, and without the parentheses in the implementation that
	-- count leaks into whatever the call site expands into -- a table
	-- constructor, an argument list, a `..` chain's neighbour.
	h.equals("returns exactly one value", select("#", escape_rich_text "a & b"), 1)
end

-- ============================== index_at ==================================

do
	-- 10 / 30 / 60 over a roll in [0, 1). Boundaries are the whole point: a
	-- `<=` where the implementation has `<`, or a missing final `return
	-- #weights`, shows up here and nowhere else, because the interiors of the
	-- buckets are forgiving.
	local weights = { 10, 30, 60 }
	h.equals("a roll of 0 lands on the first entry", weighted.index_at(weights, 0), 1)
	h.equals("just inside the first bucket", weighted.index_at(weights, 0.099), 1)
	-- Exactly on a boundary belongs to the NEXT bucket: the running total hits
	-- zero, and the test is `at < 0`. Pinned because it is the one case where
	-- "which side does the edge fall on" has to be decided rather than derived.
	h.equals("exactly on the 10% boundary lands on the second entry", weighted.index_at(weights, 0.1), 2)
	h.equals("inside the second bucket", weighted.index_at(weights, 0.3), 2)
	h.equals("exactly on the 40% boundary lands on the third entry", weighted.index_at(weights, 0.4), 3)
	h.equals("a roll just under 1 lands on the last entry", weighted.index_at(weights, 0.999), 3)
	-- A roll of exactly 1 is out of the half-open range every generator
	-- produces, but float accumulation can reach it -- the trailing
	-- `return #weights` is what stops that returning nil.
	h.equals("a roll of exactly 1 still lands on the last entry", weighted.index_at(weights, 1), 3)

	-- A zero weight must be unreachable, not merely unlikely. A drop table
	-- filtered down by "what is already alive" is mostly zeroes, and an
	-- off-by-one comparison hands back an entry the caller has just excluded.
	h.equals("a leading zero weight is skipped", weighted.index_at({ 0, 5, 0 }, 0), 2)
	h.equals("a trailing zero weight is skipped", weighted.index_at({ 5, 0 }, 0.999), 1)

	-- Degenerate tables return an index rather than nil, which is what lets the
	-- call site index straight into its own array without a guard.
	h.equals("a single entry always wins", weighted.index_at({ 3 }, 0.5), 1)
	h.equals("all-zero weights land on the last index", weighted.index_at({ 0, 0, 0 }, 0.5), 3)

	-- The distribution itself, coarsely: 25 evenly-spaced rolls over 1/3-1/3-1/3
	-- must split evenly. This is the check that the scan is over the weights and
	-- not over something that happens to correlate with them.
	local counts = { 0, 0, 0 }
	for i = 0, 29 do
		local index = weighted.index_at({ 1, 1, 1 }, i / 30)
		counts[index] += 1
	end
	h.check(
		`evenly-spaced rolls split evenly ({counts[1]}/{counts[2]}/{counts[3]})`,
		counts[1] == 10 and counts[2] == 10 and counts[3] == 10
	)
end

h.done()
