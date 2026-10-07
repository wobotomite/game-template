const ReplicatedStorage = game:GetService "ReplicatedStorage"

const Ripple = require(ReplicatedStorage.Packages.ripple)
const Vide = require(ReplicatedStorage.Packages.vide)

-- A vide source driven by a ripple motion. The caller picks the solver per call:
--
--   const alpha, motion = use_motion(0)
--   motion:spring(1, { frequency = 6, damping = 1 })
--
-- THE OPTIONS TYPE IS DECLARED HERE because ripple 0.6 does not export one. Its
-- link file re-exports exactly `Motion`, `MotionState`, `MotionSolver` and
-- `MotionGoal`; the options type is internal and NOT generic. This signature
-- used to say `Ripple.MotionOptions<T> | any`, which resolved to nothing, and
-- the `Unknown type` diagnostic it produced was audited into the baseline as
-- link-file noise. It was not noise, and the real bug sat nine lines below it.
--
-- `Heartbeat` is structural on purpose, mirroring ripple's own: it accepts a
-- real `RBXScriptSignal` (pass `RunService.RenderStepped` to lose the frame of
-- latency the default Heartbeat costs UI) and a hand-rolled clock alike. An
-- `RBXScriptSignal` annotation is REJECTED at the `createMotion` boundary, where
-- the property has to match ripple's type exactly.
type Disconnectable = {
	Disconnect: (self: Disconnectable) -> (),
}

type Heartbeat = {
	Connect: (self: Heartbeat, callback: (deltaTime: number) -> ()) -> Disconnectable,
}

export type MotionOptions = {
	heartbeat: Heartbeat?,
	start: boolean?,
}

local function use_motion<T>(initialValue: T, initialOptions: MotionOptions?): (() -> T, Ripple.Motion<T>)
	local tween = Ripple.createMotion(initialValue, initialOptions)
	local value = Vide.source(initialValue)

	if not (initialOptions and initialOptions.start == false) then
		tween:start()
	end

	-- `onStep`, NOT `onChange`. A ripple 0.6 motion is a plain table with no
	-- metatable and exactly two listeners, `onStep` and `onComplete`; `onChange`
	-- belongs to a later ripple's API. This line called it from the day it
	-- shipped, so the hook threw "attempt to call a nil value" for EVERY caller,
	-- which made `use-tween` and the `carousel` template dead on arrival -- the
	-- same failure as `use-tween`'s `createTween`, one hook over, and it outlived
	-- that fix because nobody mounted either caller.
	--
	-- The analyzer cannot see this class here: under this tree's `nonstrict` a
	-- method that does not exist on a package's table is silent. Put the old line
	-- back under `--!strict` and it says `Key 'onChange' not found in table
	-- 'Motion<T>'` at once (checked both ways). Nonstrict plus no callers is how
	-- a hook that cannot run reads as finished.
	--
	-- A closure, never the bare source: the listener is called with
	-- `(value, deltaTime)`, and a source handed over bare takes whatever a caller
	-- happens to pass it.
	--
	-- TIMING. Ripple fires listeners through `task.spawn`, which RESUMES AT ONCE
	-- (`task.defer` is the deferred one), so this write lands synchronously
	-- inside `motion:step()` and before any `onComplete` listener for that step.
	-- What does trail is the goal: `spring`, `tween`, `linear` and `set` never
	-- notify, only `step` does, so the source holds its old value until the next
	-- heartbeat after a goal is set. Read it reactively; do not set a goal and
	-- then read the source on the next line expecting it to have moved.
	local disconnect = tween:onStep(function(next_value: T)
		value(next_value)
	end)

	Vide.cleanup(function()
		disconnect()
		tween:stop()
	end)

	return value, tween
end

return use_motion
