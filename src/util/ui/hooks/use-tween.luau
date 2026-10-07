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
--
-- AND THE FIX WAS NEVER RUN EITHER. Rebuilding this file on `use-motion` moved
-- it onto a hook with the other half of the same bug: `use-motion` called
-- `motion:onChange`, which ripple 0.6 does not have (its listeners are `onStep`
-- and `onComplete`), so this hook went on throwing for every caller after it
-- was "fixed". Nobody mounted one, so nothing said so. A rework that is not
-- rendered once is a second draft, not a fix.
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
	-- `use_motion` already registers a cleanup that disconnects its `onStep`
	-- listener and stops the motion. vide 0.4 flushes a scope's cleanups in
	-- REGISTRATION order (`flush_cleanups` walks the list forwards), so that one
	-- runs first and this one -- registered after -- runs second, against a
	-- motion that is already stopped and has no live listener. This comment used
	-- to claim the reverse order. Either order is in fact harmless: `destroy`
	-- clears the listener tables, and a late disconnect only nils a key in an
	-- empty one. Do not "simplify" by moving the destroy into `use-motion`: that
	-- hook hands the raw motion back to callers who may well outlive the scope.
	const value, motion = use_motion(initial)

	Vide.cleanup(function()
		motion:destroy()
	end)

	const handle: TweenHandle<T> = {
		to = function(goal: T, override: TweenParams?)
			motion:tween(goal :: any, (override or params) :: any)
		end,
		-- `to(immediate(v))`, NOT `motion:set(v)`, even though `set` is the method
		-- whose name says "jump there". Ripple 0.6's `set` writes `state.value` and
		-- marks the state incomplete, but it leaves the SOLVER and its goal in
		-- place, so the next heartbeat hands the old solver a state it thinks is
		-- still running and it drives the value back to the old goal. MEASURED on
		-- the real package with the spring solver: spring to 1, let it settle,
		-- `set(0.5)`, and the next five steps read 0.5726 0.6892 0.7908 0.8652
		-- 0.9156, incomplete throughout. `set` was never a jump; it was a one-frame
		-- flicker on the way back to the old goal.
		--
		-- READ FROM THE SOURCE, not measured -- the tween solver builds a real
		-- TweenService tween on a NumberValue, so it cannot be run headlessly --
		-- the tween path is worse and instant. That solver keeps `complete` and
		-- `state.destructor` as upvalues; a finished tween leaves `complete` true
		-- and `set` resets neither, so the very next step takes the `if complete`
		-- branch and assigns `state.value = goal` outright. Called mid-tween
		-- instead, the tween is still running and still owned, and the next step
		-- reads `value.Value` straight back out of it.
		--
		-- `immediate` is a real solver that assigns the goal and marks the state
		-- COMPLETE, and routing through `to` is what makes the difference: `to`
		-- runs the outgoing `state.destructor` first -- destroying a still-running
		-- TweenService tween that `set` would have left driving the value -- and
		-- then installs `immediate` in the old solver's place, so nothing is left
		-- to animate the value away again. A `set` before any goal was ever set is
		-- fixed as a side effect: it used to leave the motion permanently
		-- incomplete.
		set = function(next_value: T)
			motion:to(Ripple.immediate(next_value :: any))
		end,
		motion = motion,
	}

	return value, handle
end

return use_tween
