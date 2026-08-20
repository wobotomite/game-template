const types = require(script.Parent.Parent.types)

export type SoundClip = types.Clip & {
	sound: Sound,
	volume: number?,
}

function new_sound_clip(opts: { start: number, duration: number?, sound: Sound, volume: number? }): SoundClip
	return table.freeze {
		kind = "sound",
		start = opts.start,
		duration = opts.duration,
		sound = opts.sound,
		volume = opts.volume,
	}
end

function start(clip: SoundClip, ctx: types.PlaybackContext): types.Cleanup
	const original_volume = clip.sound.Volume
	if clip.volume then
		clip.sound.Volume = clip.volume
	end
	clip.sound.PlaybackSpeed = ctx.speed
	clip.sound:Play()

	return function()
		clip.sound:Stop()
		clip.sound.Volume = original_volume
	end
end

return table.freeze {
	new = new_sound_clip,
	player = table.freeze {
		start = start,
		update = nil,
	},
}
