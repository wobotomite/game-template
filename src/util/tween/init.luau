const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"
const TweenService = game:GetService "TweenService"

const render_step = require(ReplicatedStorage.Util.events["render-step"])

type TweenType = {
	i: Instance,
	time: number,
	direction: Enum.EasingDirection,
	style: Enum.EasingStyle,
	tween_fn: (i: number) -> (),
	start_value: number,
	end_value: number,
	elapsed: number,
	running: boolean,
}
local tweens: { [Instance]: TweenType } = {}

-- Callbacks run INLINE, not through task.spawn. Every tween_fn in the game is
-- a property setter -- it does not yield, and it has nothing to gain from its
-- own thread. Spawning one per running tween per frame meant a VFX-heavy
-- moment (a shield shattering into ten tweened shards, a boss barrage, a room
-- of ghosts flashing) paid hundreds of thread allocations a frame purely in
-- collector pressure, which is exactly when the frame budget is tightest.
-- This whole loop is itself already dispatched on its own thread by the
-- render-step signal, so a throwing tween_fn still cannot take the connection
-- down -- it costs the rest of that one frame's tweens and recovers on the
-- next.
--
-- Running them inline does mean a callback can now reach back into `tweens`
-- while it is being walked -- chaining a follow-up tween, or cancelling one --
-- and adding a key mid-traversal is undefined in Lua. So the keys are read out
-- into a scratch array FIRST and the callbacks are driven off that. The array
-- is reused, so this is one table fill per frame, not an allocation.
const active: { Instance } = {}

render_step():connect(function(a0: number)
	table.clear(active)
	for i in tweens do
		table.insert(active, i)
	end
	for _, i in active do
		const v = tweens[i]
		-- Cancelled or replaced by a callback earlier in this same frame.
		if not v then
			continue
		end
		v.elapsed += a0
		if v.elapsed > v.time then
			end_tween(i)
			continue
		end
		const t = math.clamp(v.elapsed / v.time, 0, 1)
		const dt = TweenService:GetValue(t, v.style, v.direction)
		v.tween_fn(math.lerp(v.start_value, v.end_value, dt))
	end
end)

function end_tween(i: Instance)
	const obj = tweens[i]
	if not obj then
		return
	end
	tweens[i] = nil
	obj.tween_fn(math.lerp(obj.start_value, obj.end_value, 1))
end

const mt = {}
mt.__index = mt

function mt.cancel(self)
	if not self.running then
		return
	end
	self.running = false
	tweens[self.i] = nil
	task.spawn(self.tween_fn, math.lerp(self.start_value, self.end_value, 0))
end

table.freeze(mt)

@native
function new(
	i: Instance,
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	tween_fn: (i: number) -> (),
	start_value: number?,
	end_value: number?
)
	assert(RunService:IsClient(), "RUNS ONLY ON THE CLIENT!")

	-- REPLACE the running tween, do not cancel it.
	--
	-- cancel() calls the outgoing tween_fn with alpha 0, which repaints the
	-- property to the OLD tween's START value -- and it does so through
	-- task.spawn, which resumes immediately, so that repaint lands before the
	-- replacement's first frame ever runs.
	--
	-- Every re-tween of one instance therefore flashed backwards for a frame.
	--
	-- IT BITES EXACTLY WHEN THE START VALUE IS CAPTURED RATHER THAN CONSTANT.
	-- A call site passing fixed endpoints -- damage-flash's SHOW_TRANSPARENCY
	-- -> 1, re-tweened on every qualifying hit -- repainted precisely what the
	-- replacement was about to paint anyway. Invisible by coincidence of its
	-- constants, and it would have become visible the moment somebody
	-- refactored it to "fade from wherever it is now".
	--
	-- The worst live case was the BOSS BAR. boss-bar captures
	-- `scale_from = fill.Size.X.Scale` per call and re-tweens the same `fill`
	-- on every hp change over 0.25s -- while a vacuum drains the boss on the
	-- sim tick (1/8s), so a replacement landing inside the previous tween is
	-- the NORMAL case in a fight rather than an edge. The outgoing closure at
	-- alpha 0 repainted fill.Size to the PREVIOUS call's captured scale, which
	-- during damage is strictly fuller: the bar jumped back up, refilling for
	-- a frame, on most damage ticks of every boss fight. Same shape on the
	-- trail and on the container's entry/exit.
	--
	-- The lobby's buttons are the same thing more cheaply: MouseEnter tweens
	-- `b` toward the highlight, MouseLeave re-tweens the SAME `b`, and the
	-- replacement snapped it to the colour hover STARTED from.
	--
	-- Replacement wants the old tween gone, not undone. Explicit :cancel()
	-- keeps its revert for the caller that asks for it by name --
	-- cutscene-player's track cleanup, which is resetting the property on
	-- purpose.
	const previous = tweens[i]
	if previous then
		previous.running = false
		tweens[i] = nil
	end

	const tween_object = setmetatable({
		running = true,
		elapsed = 0,
		i = i,
		time = time,
		direction = direction,
		style = style,
		tween_fn = tween_fn,
		start_value = start_value,
		end_value = end_value,
	}, mt)

	tweens[i] = tween_object

	return tween_object
end

return new
