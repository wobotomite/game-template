export type Cleanup = () -> ()

export type PlaybackContext = {
	speed: number,
	folder: Folder,
	fire_marker: (marker: string, value: string) -> (),
}

export type SetSpeed = (speed: number) -> ()

export type TrackPlayer<Clip> = {
	start: (clip: Clip, ctx: PlaybackContext) -> (Cleanup?, SetSpeed?),
	update: ((clip: Clip, ctx: PlaybackContext, elapsed: number) -> ())?,
}

export type Clip = {
	kind: string,
	start: number,
	duration: number?,
}

export type Cutscene = {
	clips: { Clip },
	length: number,
	next: Cutscene?,
}

return table.freeze {}
