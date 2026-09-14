-- Exponential approach: move a value a FRACTION of the way to its target each
-- step, rather than a fixed amount.
--
--   position = approach.vector3(position, goal, 12, dt)
--
-- WHY `math.exp(-rate * dt)` AND NOT A LERP. The obvious form,
-- `math.lerp(current, target, 0.2)`, is wrong for anything driven off a frame
-- delta: the fraction is per CALL, so the same code converges twice as fast at
-- 120fps as at 60, and a hitched frame under-corrects instead of catching up.
-- Decaying by `exp(-rate * dt)` is the closed-form solution of the same pull,
-- so two 8ms steps land exactly where one 16ms step does. `rate` is in
-- reciprocal seconds -- the gap left after one second is `exp(-rate)`, so rate
-- 1 leaves 37%, rate 5 leaves 0.7%, and NOTHING ever reaches the target
-- exactly. Snap when you need equality.
--
-- `dt` is clamped at zero because a negative delta would make the exponential
-- DIVERGE away from the target rather than do nothing, which is the worst
-- possible response to a clock that went backwards.

@native
function number(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * math.max(dt, 0))
end

@native
function vector3(current: Vector3, target: Vector3, rate: number, dt: number): Vector3
	return target + (current - target) * math.exp(-rate * math.max(dt, 0))
end

-- The fraction of the remaining gap that `number`/`vector3` cover in `dt`, for
-- call sites that have to do the blend themselves -- a CFrame:Lerp, a Color3,
-- a TweenService alpha. Same curve, handed back as an alpha in [0, 1) instead
-- of applied, so the two can never drift apart.
@native
function most_of_gap(rate: number, dt: number): number
	return 1 - math.exp(-rate * math.max(dt, 0))
end

return table.freeze {
	number = number,
	vector3 = vector3,
	most_of_gap = most_of_gap,
}
