const ReplicatedStorage = game:GetService "ReplicatedStorage"

const FX = require(ReplicatedStorage.Shared.settings).effects.burst
const SQUARE = require(ReplicatedStorage.Shared.assets).textures.SQUARE

-- ONE-SHOT PARTICLES, described by the moment rather than by the emitter.
--
-- Every effect that wants a puff of something ends up writing the same fifteen
-- lines: make a ParticleEmitter, convert a Color3 into a ColorSequence and a
-- number into a NumberSequence, remember LightInfluence, remember that Rate has
-- to be zeroed or the "burst" emits forever, parent it, emit, and arrange for
-- something to destroy it. Getting any one of those wrong is invisible until
-- somebody looks at the right corner of the screen in the right lighting.
--
-- So the shape of the call here is the DESCRIPTION -- what colour, how many,
-- how fast, how long -- and every property that is always the same is always
-- the same. The options that are genuinely per-effect are all optional and all
-- fall back to `settings.effects.burst`.
--
-- WHAT THIS DELIBERATELY DOES NOT DO: it does not clean up after itself and it
-- does not make a sound. The caller owns both, because only the caller knows
-- how long the moment lasts. `Debris:AddItem(emitter, lifetime.Max + 0.1)` is
-- the usual ending -- the extra beat is so particles already in the air finish
-- their lives instead of vanishing with the emitter.

const DEFAULT_SPREAD_DEG = FX.DEFAULT_SPREAD_DEG
const DEFAULT_SIZE = FX.DEFAULT_SIZE
const FADE = FX.FADE

export type Options = {
	-- A Color3 for a flat colour, a ColorSequence to change over the particle's
	-- life. Taking both is the whole reason this wrapper is worth having: the
	-- flat case is most of them and `ColorSequence.new(c)` at every call site is
	-- noise.
	color: Color3 | ColorSequence,
	-- How many to emit right now. Zero is legal and means "do not emit" -- for a
	-- burst that will be driven by `rate`, or emitted by hand later.
	count: number,
	-- Studs per second, as a range so the particles do not travel as a wall.
	speed: NumberRange,
	-- Seconds, as a range for the same reason: a burst whose particles all die
	-- on the same frame reads as a light switching off.
	lifetime: NumberRange,
	-- Degrees of cone, both axes. Defaults to the settings value.
	spread: number?,
	-- Studs, flat or over life. Defaults to the settings value.
	size: (number | NumberSequence)?,
	-- Defaults to the engine's square particle. Override for art.
	texture: string?,
	-- Emit along the attachment's facing instead of out of every face. Only
	-- useful with an anchor built with a `facing` -- see `anchor` below.
	directional: boolean?,
	-- Constant force in studs/s^2. `Vector3.new(0, -50, 0)` for debris that
	-- falls, a positive Y for anything that rises.
	acceleration: Vector3?,
	-- How hard the air holds the particles back. Turns a spray into a puff that
	-- stops where it lands.
	drag: number?,
	-- 0..1, how much the particle glows in its own right. Above 0 for sparks and
	-- anything meant to read in a dark room.
	light_emission: number?,
	-- Overrides the fade curve entirely. For a burst that should NOT fade out --
	-- one cut short by its own lifetime, or one behind a separate fade.
	transparency: NumberSequence?,
	-- Random starting angle and spin. Matters for a textured particle and does
	-- nothing visible for a symmetrical one, which is why it is off by default.
	rotation: boolean?,
	-- Particles per second for a CONTINUOUS emitter. Left at 0 unless set, which
	-- is what makes the un-set case a one-shot.
	rate: number?,
}

-- A POSITION IN THE WORLD TO HANG AN EMITTER ON. ParticleEmitters need a
-- BasePart or an Attachment to live in, and most of the moments worth marking
-- happen at a point in space that no part occupies -- an impact in mid-air, the
-- spot a thing was standing before it stopped existing.
--
-- Parented to `workspace.Terrain` because Terrain is a BasePart that is always
-- present and never destroyed, so it costs nothing and cannot be the thing that
-- takes the effect down early. THE CALLER DESTROYS IT; an Attachment nobody
-- removes is a permanent child of Terrain.
function anchor(position: Vector3, facing: Vector3?): Attachment
	const made = Instance.new "Attachment"
	-- Orientation only matters to a `directional` emitter, and asking for the
	-- CFrame of a zero-length direction gives a NaN rotation that quietly
	-- corrupts everything parented to it -- hence the magnitude check rather
	-- than a plain `if facing`.
	if facing and facing.Magnitude > 1e-3 then
		made.WorldCFrame = CFrame.lookAt(position, position + facing.Unit)
	else
		made.WorldPosition = position
	end
	made.Parent = workspace.Terrain
	return made
end

function new(parent: Instance, options: Options): ParticleEmitter
	const emitter = Instance.new "ParticleEmitter"

	const spread = options.spread or DEFAULT_SPREAD_DEG
	emitter.SpreadAngle = Vector2.new(spread, spread)
	-- `Front` is the attachment's look vector, which is what `anchor(pos, dir)`
	-- aims. Left alone otherwise: the engine's default emission direction is Top,
	-- and a burst with a wide spread does not care.
	if options.directional then
		emitter.EmissionDirection = Enum.NormalId.Front
	end

	emitter.Speed = options.speed
	emitter.Lifetime = options.lifetime

	const size = options.size or DEFAULT_SIZE
	emitter.Size = if typeof(size) == "number" then NumberSequence.new(size) else size :: NumberSequence

	const color = options.color
	emitter.Color = if typeof(color) == "Color3" then ColorSequence.new(color) else color :: ColorSequence

	emitter.Transparency = options.transparency or FADE
	emitter.LightEmission = options.light_emission or 0
	-- ALWAYS ZERO, never an option. LightInfluence above 0 means the particle is
	-- lit by the scene, so the effect disappears in exactly the places an effect
	-- is most needed -- a dark room, a shadow, a night cycle. A burst carries its
	-- own colour; `light_emission` is the knob for how much it glows.
	emitter.LightInfluence = 0
	emitter.Texture = options.texture or SQUARE
	if options.acceleration then
		emitter.Acceleration = options.acceleration
	end
	if options.drag then
		emitter.Drag = options.drag
	end
	if options.rotation then
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-180, 180)
	end

	-- BEFORE THE PARENT, and zero unless asked for. A ParticleEmitter's default
	-- Rate is 20: set the parent first and a one-shot burst spends the frame
	-- between parenting and this line emitting particles nobody asked for, and a
	-- burst whose emitter is never destroyed becomes a permanent fountain.
	emitter.Rate = options.rate or 0
	emitter.Parent = parent
	if options.count > 0 then
		emitter:Emit(options.count)
	end
	return emitter
end

return table.freeze {
	anchor = anchor,
	new = new,
}
