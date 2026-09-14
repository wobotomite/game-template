const ReplicatedStorage = game:GetService "ReplicatedStorage"

const Ripple = require(ReplicatedStorage.Packages.ripple)
const Vide = require(ReplicatedStorage.Packages.vide)
const use_motion = require(script.Parent["use-motion"])

-- A vide source driven by a ripple motion that is pre-wired to the TWEEN
-- solver: fixed duration, an easing curve, a definite end.
--
--   const alpha, tween = use_tween(0)
--   tween.to(1, { time = 0.25, style = Enum.EasingStyle.Quad })
--
-- Use `use-motion` instead when the caller wants to pick the solver per call
-- (spring for anything interruptible, linear for anything that must not
-- overshoot). Use this one when the answer is always "tween", so the call site
-- reads as a duration rather than as a solver choice.
--
-- ------------------------------------------------------------------------
-- THIS FILE WAS BROKEN FROM THE DAY IT SHIPPED, and it is worth saying how,
-- because the shape recurs.
--
-- It called `Ripple.createTween(...)`, then `tween:onChange`, `tween:start`,
-- `tween:stop`. Ripple 0.6 exports `createMotion`, `config`, `immediate`,
-- `linear`, `spring` and `tween` — there is no `createTween`, and no
-- `Ripple.Tween`, `Ripple.TweenOptions` or `Ripple.Animatable` types either.
-- The whole module was written against a different version's API.
--
-- Nothing said so. A missing table key is `nil`, not a type error; the module
-- was a byte-for-byte duplicate of `use-motion` (same internal function name and
-- all) with one call changed, so it read as obviously fine; and it had no
-- callers, so it never ran. `luau-lsp` did report
-- `Key 'createTween' not found in table` — one line, in a baseline of hundreds,
-- which is why "audit the baseline once, separately" is a rule and not advice.
--
-- `tests/package-api.spec.luau` catches exactly this class by reading a
-- package's real export table — but only for packages that can be required
-- headlessly, and ripple cannot. So the bug lived in the one blind spot that
-- check declares. That is the argument for declaring blind spots by name
-- rather than letting them be implicit.
-- ------------------------------------------------------------------------

export type TweenParams = {
	time: number?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	repeatCount: number?,
	reverses: boolean?,
	delayTime: number?,
}

export type TweenHandle<T> = {
	-- Animate toward `goal`. Calling again retargets, which is the whole point
	-- of holding a motion rather than starting a fresh TweenService tween.
	to: (goal: T, params: TweenParams?) -> (),
	-- Jump there with no animation.
	set: (value: T) -> (),
	motion: Ripple.Motion<T>,
}

local function use_tween<T>(initial: T, params: TweenParams?): (() -> T, TweenHandle<T>)
	-- Built ON `use-motion` rather than beside it. The two files were byte-for-byte
	-- duplicates apart from one call (see the note above), and that duplication is
	-- what let this one drift onto a nonexistent API without anybody noticing: a
	-- second copy of the wiring reads as correct precisely because it looks like
	-- the first. There is now ONE place that knows how a ripple motion is attached
	-- to a vide source and torn down.
	--
	-- `use_motion` already registers a cleanup that disconnects the onChange and
	-- stops the motion, and vide runs cleanups in reverse order, so this extra
	-- one -- registered after -- runs FIRST. That ordering is the reason `destroy`
	-- can live here at all: destroying a motion that is still started and still
	-- has a live onChange would be tearing the object out from under its own
	-- listener. Do not "simplify" by moving the destroy into `use-motion`: that
	-- hook hands the raw motion back to callers who may well outlive the scope.
	const value, motion = use_motion(initial)

	Vide.cleanup(function()
		motion:destroy()
	end)

	const handle: TweenHandle<T> = {
		to = function(goal: T, override: TweenParams?)
			motion:tween(goal :: any, (override or params) :: any)
		end,
		set = function(next_value: T)
			motion:set(next_value :: any)
		end,
		motion = motion,
	}

	return value, handle
end

return use_tween
