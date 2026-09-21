const ReplicatedStorage = game:GetService "ReplicatedStorage"
const Debris = game:GetService "Debris"

const make_part = require(ReplicatedStorage.Util.instances["make-display-part"])
const tween = require(ReplicatedStorage.Util.tween)
const FX = require(ReplicatedStorage.Shared.settings).effects.ring

-- A BAND THAT GROWS OUTWARDS AND FADES. The shape of "something happened HERE,
-- and it reaches this far": an impact, a landing, a shockwave, the edge of an
-- area attack arriving.
--
-- HOW IT IS DRAWN, because it is not obvious from the outside: there is no ring
-- mesh and no ring texture. It is `settings.effects.ring.SEGMENTS` straight
-- Neon boxes arranged end to end around a circle, re-sized and re-placed every
-- frame as the radius grows. A polygon, pretending. That approach is worth
-- knowing about for two reasons -- the cost of a ring is a part count, not a
-- texture, and the ring is only as round as SEGMENTS makes it.
--
-- IT DRAWS ON A PLANE, not on the ground. `frame` is the plane's CFrame and the
-- circle is swept in that frame's XY, so the ring lies flat when the frame is
-- rotated flat and stands up when it is not. For a ring on the floor under
-- something, get the point from `effects.shared.floor` and build the frame from
-- it -- this module does not probe, because half the moments that want a ring
-- are in mid-air.
--
-- THE CALLER DOES NOT CLEAN UP and the caller does not make a sound. The folder
-- is on a `Debris` timer of exactly the ring's own duration, and audio belongs
-- to whoever decided the moment happened. See the README.

-- `frame`    plane and origin; the ring is swept in its XY.
-- `from`/`to` studs, the radius at the start and at the end. `to` smaller than
--            `from` is a legal ring that collapses inwards.
-- `width`    studs, how thick the band reads.
-- `seconds`  how long the whole expansion takes.
-- `color`    the band's colour; it is Neon, so this is what it glows.
-- `arc`      radians, for a WEDGE instead of a full circle -- a cone attack, a
--            direction. Defaults to the whole turn.
-- `fade_to`  a second colour to cross into as it expands, for a ring that cools
--            or heats on the way out. Off by default: most rings want one
--            colour and a fade to nothing, which the transparency curve already
--            does.
return function(
	frame: CFrame,
	from: number,
	to: number,
	width: number,
	seconds: number,
	color: Color3,
	arc: number?,
	fade_to: Color3?
): Folder
	const folder = Instance.new "Folder"
	folder.Name = "Ring"
	folder.Parent = workspace

	const segments: { Part } = {}
	const sweep = arc or math.pi * 2
	for _ = 1, FX.SEGMENTS do
		table.insert(
			segments,
			make_part {
				Name = "Segment",
				Material = Enum.Material.Neon,
				Color = color,
				CanTouch = false,
				-- FULLY TRANSPARENT UNTIL THE FIRST STEP. The parts are built at
				-- the default position -- the world origin, all on top of each
				-- other -- and the tween callback is what first gives them a
				-- size and a place. Visible here is one frame of a bright blob
				-- at 0,0,0 for every ring the game ever plays.
				Transparency = 1,
				Parent = folder,
			}
		)
	end

	-- Quad/Out, so the ring covers most of its distance immediately and eases
	-- into the final radius. That is the shape of an impact -- fast, then
	-- spending itself -- and it also means the ring reaches its useful size
	-- within the first few frames, which matters when it is telling a player
	-- where not to stand.
	tween(folder, seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(alpha)
		-- The tween outlives the folder if Debris wins the race on the last
		-- frame, or if the caller destroyed it early.
		if not folder.Parent then
			return
		end

		const radius = math.lerp(from, to, alpha)
		const faded = math.lerp(FX.TRANSPARENCY, 1, alpha ^ FX.FADE_POWER)
		const tint = if fade_to then color:Lerp(fade_to, alpha) else nil

		for index, part in segments do
			-- The two ends of this segment's slice of the sweep, as points on
			-- the circle in the plane's own space.
			const a = (index - 1) / FX.SEGMENTS * sweep
			const b = index / FX.SEGMENTS * sweep
			const p = frame:PointToWorldSpace(Vector3.new(math.cos(a), math.sin(a), 0) * radius)
			const q = frame:PointToWorldSpace(Vector3.new(math.cos(b), math.sin(b), 0) * radius)
			-- Length is the chord PLUS one width, and the extra is what closes
			-- the gaps: each box is aimed down its own chord, so consecutive
			-- boxes meet at an angle and leave a notch on the outside of every
			-- joint. Overlapping them by half a width at each end hides it, and
			-- costs nothing because they are all the same colour.
			part.Size = Vector3.new(width, width * FX.THICKNESS, (q - p).Magnitude + width)
			part.CFrame = CFrame.lookAt((p + q) / 2, q)
			part.Transparency = faded
			if tint then
				part.Color = tint
			end
		end
	end, 0, 1)

	Debris:AddItem(folder, seconds)
	return folder
end
