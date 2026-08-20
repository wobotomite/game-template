const types = require(script.Parent.Parent.types)

export type CustomClip = types.Clip & {
	on_start: ((ctx: types.PlaybackContext) -> types.Cleanup?)?,
	on_update: ((elapsed_in_clip: number, ctx: types.PlaybackContext) -> ())?,
}

function new_custom_clip(opts: {
	start: number,
	duration: number?,
	on_start: ((ctx: types.PlaybackContext) -> types.Cleanup?)?,
	on_update: ((elapsed_in_clip: number, ctx: types.PlaybackContext) -> ())?,
}): CustomClip
	return table.freeze {
		kind = "custom",
		start = opts.start,
		duration = opts.duration,
		on_start = opts.on_start,
		on_update = opts.on_update,
	}
end

function start(clip: CustomClip, ctx: types.PlaybackContext): types.Cleanup?
	if not clip.on_start then
		return nil
	end
	return clip.on_start(ctx)
end

function update(clip: CustomClip, ctx: types.PlaybackContext, elapsed: number)
	if clip.on_update then
		clip.on_update(elapsed - clip.start, ctx)
	end
end

return table.freeze {
	new = new_custom_clip,
	player = table.freeze {
		start = start,
		update = update,
	},
}
