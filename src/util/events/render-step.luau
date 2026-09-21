const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const extend_object = require(ReplicatedStorage.Util.tables["extend-object"])
const pseudo_signal = require(script.Parent["pseudo-signal"])
const step_stats = require(script.Parent["step-stats"])
const profile = require(ReplicatedStorage.Util.debug.profile)

-- `fire` calls each listener in place under a `pcall` (see pseudo-signal), so a
-- listener here MUST NOT YIELD: one that waits parks the whole frame's fan-out
-- behind it. A throwing listener costs only itself and is reported once.
const signals = {}
-- Scratch list of the signals that fire THIS frame. Dispatch is two passes --
-- decide, then fire -- because a listener is allowed to create or destroy a step
-- signal, and that writes `signals` while the first loop would still be walking
-- it with `next`: undefined in Lua, and in practice a skipped signal or an
-- "invalid key to 'next'" on exactly the busy frames. Module-level and reused,
-- so the second pass allocates nothing.
const due: { any } = {}
-- Banked frame times never sum to the period exactly: sixty 1/60 s frames reach
-- 0.99999..., and a bare `>=` then sits out one more whole frame -- a 1 s
-- listener quietly running at 61 frames. Far below any real frame time.
const EPSILON = 1e-9
RunService.RenderStepped:Connect(function(a0: number)
	-- Timed so a captured frame hitch can say whether this dispatch was the
	-- cause; see step-stats. Two clock reads a frame.
	const began = os.clock()
	-- A MicroProfiler scope around the whole fan-out, so a frame captured with
	-- Ctrl+F6 says how much of it was this dispatch -- the same number
	-- `step-stats` reports, but placed next to the engine's own work instead of
	-- in a console line you have to go and read. ~52 ns for the pair, once a
	-- frame. `begin`/`close` rather than the closure form: this is per-frame,
	-- and the closure form allocates.
	profile.begin "render-step"
	local count = 0
	for signal, data in signals do
		data.counter += a0
		data.elapsed += a0

		const rate = data.rate
		local fires = false
		-- `first` fires a rate-limited listener on its FIRST tick instead of
		-- making it sit out one whole period. A listener created mid-session --
		-- a HUD element mounting, an effect spawned on a hit -- otherwise shows
		-- nothing until its first period has banked, which on SLOW reads as a
		-- stall rather than as a rate.
		--
		-- This used to be spelled `counter = rate or 0` at creation, which also
		-- fired on tick one but handed the listener `c = rate + a0`: a
		-- fabricated delta one whole period too large. Anything INTEGRATING
		-- that delta -- a tween's elapsed, an exponential approach -- jumped a
		-- period forward on its very first step. Starting the counter at zero
		-- and flagging the first tick separately fires just as early and
		-- reports the time that actually passed.
		if not rate or data.first then
			data.counter = 0
			fires = true
		elseif data.counter + EPSILON >= rate then
			-- KEEP THE REMAINDER. Zeroing the counter threw away whatever had
			-- banked past the period, so a "0.1 s" listener at 60 fps really ran
			-- every 0.1167 s (seven frames, never six) and every rate in the game
			-- was slow by up to a frame. Subtracting the period keeps the long-run
			-- rate honest. More than two periods behind is a hitch, not drift:
			-- drop the debt rather than firing on consecutive frames to repay it.
			data.counter = if data.counter > rate * 2 then 0 else data.counter - rate
			fires = true
		end
		if fires then
			-- The listener is handed the time that ACTUALLY passed since its last
			-- fire -- `elapsed`, not `counter`, which now carries a remainder and
			-- is no longer a delta. Anything integrating the argument stays exact.
			data.due = data.elapsed
			data.elapsed = 0
			data.first = false
			count += 1
			due[count] = signal
		end
	end
	for index = 1, count do
		const signal = due[index]
		due[index] = nil
		-- Destroyed by an earlier listener in this same frame.
		const data = signals[signal]
		if data then
			signal:fire(data.due)
		end
	end
	profile.close()
	step_stats.record("render", os.clock() - began)
end)

return function(rate: number?)
	const ns = pseudo_signal.new<<number>>()
	signals[ns] = { rate = rate, counter = 0, elapsed = 0, first = true, due = 0 }

	return extend_object(ns, {
		destroy = function(self)
			signals[getmetatable(self).__index] = nil
		end,
	})
end
