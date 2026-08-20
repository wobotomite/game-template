const types = require(script.Parent.Parent.types)

export type AnimationClip = types.Clip & {
	target: Animator | Humanoid | AnimationController,
	animation: Animation,
	markers: { string },
	fade_time: number?,
}

function new_animation_clip(opts: {
	start: number,
	duration: number?,
	target: Animator | Humanoid | AnimationController,
	animation: Animation,
	markers: { string }?,
	fade_time: number?,
}): AnimationClip
	return table.freeze {
		kind = "animation",
		start = opts.start,
		duration = opts.duration,
		target = opts.target,
		animation = opts.animation,
		markers = opts.markers or {},
		fade_time = opts.fade_time,
	}
end

function get_animator(target: Animator | Humanoid | AnimationController): Animator
	if target:IsA "Animator" then
		return target
	end
	return target:FindFirstChildOfClass "Animator" or Instance.new("Animator", target)
end

function start(clip: AnimationClip, ctx: types.PlaybackContext): (types.Cleanup, types.SetSpeed)
	const animator = get_animator(clip.target)
	const track = animator:LoadAnimation(clip.animation)
	track:Play(clip.fade_time)
	track:AdjustSpeed(ctx.speed)

	const disconnects = {}
	for _, marker in clip.markers do
		table.insert(
			disconnects,
			track:GetMarkerReachedSignal(marker):Connect(function(value: string)
				ctx.fire_marker(marker, value)
			end)
		)
	end

	local function cleanup()
		for _, disconnect in disconnects do
			disconnect:Disconnect()
		end
		track:Stop()
	end

	local function set_speed(speed: number)
		track:AdjustSpeed(speed)
	end

	return cleanup, set_speed
end

return table.freeze {
	new = new_animation_clip,
	player = table.freeze {
		start = start,
		update = nil,
	},
}
