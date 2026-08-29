const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const extend_object = require(ReplicatedStorage.Util.tables["extend-object"])
const pseudo_signal = require(script.Parent["pseudo-signal"])
const step_stats = require(script.Parent["step-stats"])
const profile = require(ReplicatedStorage.Util.debug.profile)

-- `fire` gives each listener its own thread, which costs ~0.74us apiece on
-- EVERY frame -- paid by every live per-effect listener, so it grows with the
-- VFX on screen. That is the price of error isolation: one listener that throws
-- now costs only itself, where the inline dispatcher this used to call took the
-- rest of that frame's listeners down with it.
const signals = {}
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
	for signal, data in signals do
		data.counter += a0
		if not data.rate or data.counter >= data.rate then
			const c = data.counter
			data.counter = 0
			signal:fire(c)
		end
	end
	profile.close()
	step_stats.record("render", os.clock() - began)
end)

return function(rate: number?)
	const ns = pseudo_signal.new<<number>>()
	signals[ns] = { rate = rate, counter = rate or 0 }

	return extend_object(ns, {
		destroy = function(self)
			signals[getmetatable(self).__index] = nil
		end,
	})
end
