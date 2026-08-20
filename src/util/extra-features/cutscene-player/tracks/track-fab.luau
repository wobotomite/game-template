const types = require(script.Parent.Parent.types)

export type FabClip = types.Clip & {
	instance: Instance,
}

function fab(opts: { start: number, duration: number?, instance: Instance }): FabClip
	return table.freeze {
		kind = "fab",
		start = opts.start,
		duration = opts.duration,
		instance = opts.instance,
	}
end

function start(clip: FabClip, ctx: types.PlaybackContext): types.Cleanup
	const original_parent = clip.instance.Parent
	clip.instance.Parent = ctx.folder
	return function()
		clip.instance.Parent = original_parent
	end
end

return table.freeze {
	new = fab,
	player = table.freeze {
		start = start,
		update = nil,
	},
}
