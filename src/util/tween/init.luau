const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"
const TweenService = game:GetService "TweenService"

const render_step = require(ReplicatedStorage.Util.events["render-step"])
const on_shutdown = require(ReplicatedStorage.Util.game["on-shutdown"])

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

on_shutdown(render_step():connect(function(a0: number)
	for i, v in tweens do
		v.elapsed += a0
		if v.elapsed > v.time then
			end_tween(i)
			continue
		end
		const t = math.clamp(v.elapsed / v.time, 0, 1)
		const dt = TweenService:GetValue(t, v.style, v.direction)
		task.spawn(v.tween_fn, math.lerp(v.start_value, v.end_value, dt))
	end
end))

function end_tween(i: Instance)
	const obj = tweens[i]
	if not obj then
		return
	end
	task.spawn(obj.tween_fn, math.lerp(obj.start_value, obj.end_value, 1))
	tweens[i] = nil
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

	if tweens[i] then
		tweens[i]:cancel()
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
