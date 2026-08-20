const ReplicatedStorage = game:GetService "ReplicatedStorage"

const tween = require(ReplicatedStorage.Util.tween)
const types = require(script.Parent.Parent.types)

export type TweenClip = types.Clip & {
	instance: Instance,
	duration: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	from: number,
	to: number,
	apply: (value: number) -> (),
}

function new_tween_clip(opts: {
	start: number,
	instance: Instance,
	duration: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	from: number,
	to: number,
	apply: (value: number) -> (),
}): TweenClip
	return table.freeze {
		kind = "tween",
		start = opts.start,
		duration = opts.duration,
		instance = opts.instance,
		style = opts.style or Enum.EasingStyle.Linear,
		direction = opts.direction or Enum.EasingDirection.InOut,
		from = opts.from,
		to = opts.to,
		apply = opts.apply,
	}
end

function start(clip: TweenClip, ctx: types.PlaybackContext): types.Cleanup
	const running =
		tween(clip.instance, clip.duration / ctx.speed, clip.style, clip.direction, clip.apply, clip.from, clip.to)
	return function()
		running:cancel()
	end
end

return table.freeze {
	new = new_tween_clip,
	player = table.freeze {
		start = start,
		update = nil,
	},
}
