-- Pick a uniformly random element that is NOT the one you already have.
--
--   const next = pick_other(playlist, now_playing)
--
-- The "don't repeat the last one" draw, which is easy to write ALMOST right.
-- The tempting version draws again on a collision:
--
--     local pick = live[math.random(#live)]
--     if pick == current then
--         pick = live[math.random(#live)]   -- one retry, then give up
--     end
--
-- That looks like a fair trade -- retry once, and never risk looping on an
-- unlucky draw. It is a false dilemma. With two tracks it still repeats a
-- quarter of the time, and the fix costs nothing: draw from the n-1 OTHERS and
-- step over the current one's slot. Exactly uniform, `current` impossible, O(1),
-- and no loop to bound.
--
-- THE RNG IS INJECTABLE, matching `util/numbers/weighted-random`: a spec passes
-- a seeded `Random` so a distribution assertion is repeatable rather than
-- flaky-by-construction.
--
-- DUPLICATES ARE EXCLUDED BY SLOT, NOT BY VALUE. `table.find` locates the first
-- occurrence, so if `items` contains `current` twice, the second copy stays in
-- the draw and can come back. That is the right behaviour for a weighted list
-- written as repeats, and the wrong one if you expected set semantics -- so it
-- is written down rather than left to be discovered.
--
-- Edge cases, all deliberate:
--   * empty list      -> nil, because there is nothing to play.
--   * one element     -> that element, EVEN IF it is `current`. A one-track
--                        playlist repeating is not a bug; returning nil would
--                        stop the music instead.
--   * `current` absent -> an ordinary uniform draw over everything.

const rng = Random.new()

return function<T>(items: { T }, current: T?, random: Random?): T?
	const n = #items
	if n == 0 then
		return nil
	end
	if n == 1 then
		return items[1]
	end

	const source = random or rng
	const at = if current ~= nil then table.find(items :: { any }, current) else nil
	if not at then
		return items[source:NextInteger(1, n)]
	end

	local index = source:NextInteger(1, n - 1)
	if index >= at then
		index += 1
	end
	return items[index]
end
