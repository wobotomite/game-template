const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const render_step = require(ReplicatedStorage.Util.events["render-step"])
const pseudo_signal = require(ReplicatedStorage.Util.events["pseudo-signal"])

const types = require(script.types)
const fab_track = require(script.tracks.fab)
const tween_track = require(script.tracks.tween)
const animation_track = require(script.tracks.animation)
const sound_track = require(script.tracks.sound)
const custom_track = require(script.tracks.custom)

assert(RunService:IsClient(), "CAN ONLY BE RUN ON THE CLIENT!")

export type Cutscene = types.Cutscene
export type Clip = types.Clip

const tracks = table.freeze {
	fab = fab_track.new,
	tween = tween_track.new,
	animation = animation_track.new,
	sound = sound_track.new,
	custom = custom_track.new,
}

const players_by_kind: { [string]: types.TrackPlayer<any> } = {
	fab = fab_track.player,
	tween = tween_track.player,
	animation = animation_track.player,
	sound = sound_track.player,
	custom = custom_track.player,
}

type MarkerEvent = { marker: string, value: string }
const marker_bus = pseudo_signal.new<<MarkerEvent>>()

type ActiveEntry = {
	clip: types.Clip,
	player: types.TrackPlayer<any>,
	ctx: types.PlaybackContext,
	cleanup: types.Cleanup?,
	set_speed: types.SetSpeed?,
}

type Current = {
	cutscene: types.Cutscene,
	elapsed: number,
	speed: number,
	paused: boolean,
	pending: { types.Clip },
	active: { [types.Clip]: ActiveEntry },
	folder: Folder,
}
local current: Current? = nil

function get_folder(): Folder
	local folder = workspace:FindFirstChild "Cutscenes" :: Folder?
	if not folder then
		folder = Instance.new "Folder"
		folder.Name = "Cutscenes"
		folder.Parent = workspace
	end
	return folder :: Folder
end

function fire_marker(marker: string, value: string)
	marker_bus:fire { marker = marker, value = value }
end

function build_ctx(): types.PlaybackContext
	const state = current :: Current
	return {
		speed = state.speed,
		folder = state.folder,
		fire_marker = fire_marker,
	}
end

function start_clip(clip: types.Clip)
	const state = current :: Current
	const player = players_by_kind[clip.kind]
	const ctx = build_ctx()
	const cleanup, adjust_speed = player.start(clip, ctx)
	state.active[clip] = {
		clip = clip,
		player = player,
		ctx = ctx,
		cleanup = cleanup,
		set_speed = adjust_speed,
	}
end

function stop_clip(clip: types.Clip)
	const state = current :: Current
	const entry = state.active[clip]
	if not entry then
		return
	end
	state.active[clip] = nil
	if entry.cleanup then
		entry.cleanup()
	end
end

function finish()
	const state = current :: Current
	const def = state.cutscene
	const next_def = def.next
	const speed = state.speed
	stop()
	if next_def then
		play(next_def)
		set_speed(speed)
	end
end

function step(dt: number)
	if not current or current.paused then
		return
	end
	current.elapsed += dt * current.speed

	local i = 1
	while i <= #current.pending do
		const clip = current.pending[i]
		if current.elapsed >= clip.start then
			table.remove(current.pending, i)
			start_clip(clip)
		else
			break
		end
	end

	for clip, entry in current.active do
		if entry.player.update then
			entry.player.update(clip, entry.ctx, current.elapsed)
		end
		if clip.duration and current.elapsed >= clip.start + clip.duration then
			stop_clip(clip)
		end
	end

	if current.elapsed >= current.cutscene.length and #current.pending == 0 then
		finish()
	end
end

render_step():connect(step)

function create(clips: { types.Clip }, options: { length: number? }?): types.Cutscene
	const sorted = table.clone(clips)
	table.sort(sorted, function(a, b)
		return a.start < b.start
	end)

	local length = options and options.length
	if not length then
		length = 0
		for _, clip in sorted do
			length = math.max(length, clip.start + (clip.duration or 0))
		end
	end

	return table.freeze {
		clips = table.freeze(sorted),
		length = length,
		next = nil,
	}
end

function chain(cutscenes: { types.Cutscene }): types.Cutscene
	assert(#cutscenes > 0, "chain requires at least one cutscene")

	local next_clone: types.Cutscene? = nil
	for i = #cutscenes, 1, -1 do
		const clone = table.clone(cutscenes[i])
		clone.next = next_clone
		next_clone = table.freeze(clone)
	end

	return next_clone :: types.Cutscene
end

function play(cutscene: types.Cutscene?)
	if not cutscene then
		if current and current.paused then
			current.paused = false
			for _, entry in current.active do
				if entry.set_speed then
					entry.set_speed(current.speed)
				end
			end
		end
		return
	end

	if current then
		stop()
	end

	current = {
		cutscene = cutscene,
		elapsed = 0,
		speed = 1,
		paused = false,
		pending = table.clone(cutscene.clips),
		active = {},
		folder = get_folder(),
	}
end

function pause()
	if not current or current.paused then
		return
	end
	current.paused = true
	for _, entry in current.active do
		if entry.set_speed then
			entry.set_speed(0)
		end
	end
end

function stop()
	if not current then
		return
	end
	for clip in current.active do
		stop_clip(clip)
	end
	current = nil
end

function set_speed(n: number)
	if not current then
		return
	end
	current.speed = n
	if not current.paused then
		for _, entry in current.active do
			if entry.set_speed then
				entry.set_speed(n)
			end
		end
	end
end

function on_marker(fn: (marker: string, value: string) -> ()): () -> ()
	return marker_bus:connect(function(event: MarkerEvent)
		fn(event.marker, event.value)
	end)
end

-- local intro = create({
-- 	tracks.fab { start = 0, instance = local_character_dummy },
-- 	tracks.fab { start = 0, instance = map },
-- 	tracks.tween {
-- 		start = 0,
-- 		duration = 2,
-- 		instance = workspace.CurrentCamera,
-- 		from = 0,
-- 		to = 1,
-- 		apply = function(t) end,
-- 	},
-- 	tracks.animation {
-- 		start = 0.5,
-- 		target = local_character_dummy.Humanoid,
-- 		animation = char_dummy_animation_init,
-- 		markers = { "look_at_item" },
-- 	},
-- }, { length = 5 })
--
-- local outro = create({ tracks.fab { start = 0, instance = credits_gui } }, { length = 3 })
--
-- const unsubscribe = on_marker(function(marker, value)
-- 	if marker == "look_at_item" then
-- 		const item = evil_item
-- 	end
-- end)
--
-- play(chain { intro, outro })

return table.freeze {
	tracks = tracks,
	create = create,
	chain = chain,
	play = play,
	pause = pause,
	stop = stop,
	set_speed = set_speed,
	on_marker = on_marker,
}
