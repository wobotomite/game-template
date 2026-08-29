const ReplicatedStorage = game:GetService "ReplicatedStorage"
const TweenService = game:GetService "TweenService"

const tween = require(ReplicatedStorage.Util.tween)
const effect_types = require(ReplicatedStorage.Effects["effect-types"])
const floor_util = require(ReplicatedStorage.Effects.shared.floor)
const make_display_part = require(ReplicatedStorage.Util.instances["make-display-part"])

-- Attack telegraph: a faint disc marks the FULL danger area from frame one (so
-- "am I inside it?" is answerable immediately), while a solid disc grows into
-- it over the windup, reaching full size right as the hit lands -- the timing
-- and the radius are both readable at a glance, no text needed.
--
--   effects.new("common/ground-telegraph", nil, {
--       position = landing, radius = 9, duration = 1.2, color = Color3.new(1, 0.3, 0.2),
--   })
--
-- Silent by design, and this is a rule worth keeping rather than an omission.
-- A telegraph is the WARNING half of an attack; the arriving half carries the
-- sound. A cue on the windup AND another on the hit reads as two events, and
-- players dodge the first one.
--
-- This ships as the template's one example entry. Read it for the shape of an
-- effect -- attr, cleanup, a returned teardown -- then write your own beside
-- it.
return function(cleanup: effect_types.Cleanup, _get: effect_types.InstanceGetter, attr: effect_types.AttributeGetter)
	const position = attr "position" :: Vector3
	const radius = attr "radius" :: number
	const duration = attr "duration" :: number
	const color = attr "color" :: Color3

	const floor = floor_util.below(position)

	-- Full-radius footprint, visible instantly. Sits a hair lower than the
	-- filling disc so the two never z-fight.
	const footprint = make_display_part {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(floor - Vector3.yAxis * 0.05) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.85,
		Parent = workspace,
	}
	task.delay(duration, function()
		-- Impact: the footprint pops bright for a beat, then dies with the fill.
		footprint.Transparency = 0.4
		tween(footprint, 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, function(alpha)
			footprint.Transparency = math.lerp(0.4, 1, alpha)
		end, 0, 1)
		task.delay(0.2, footprint.Destroy, footprint)
	end)

	const disc = make_display_part {
		Shape = Enum.PartType.Cylinder, -- height along local X; the CFrame rolls it flat
		Size = Vector3.new(0.25, 2, 2),
		CFrame = CFrame.new(floor) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		Parent = workspace,
	}
	-- Stays on TweenService: the grow tween ends exactly when the delayed fade
	-- starts, and the tween util's per-instance keying would cancel-snap the
	-- disc back to its 2-stud start size if the two overlap by a frame.
	TweenService:Create(disc, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = Vector3.new(0.25, radius * 2, radius * 2),
	}):Play()
	task.delay(duration, function()
		TweenService:Create(disc, TweenInfo.new(0.15), { Transparency = 1 }):Play()
		task.delay(0.18, disc.Destroy, disc)
	end)

	-- Ends itself once the fade is done, so the registry stops considering it
	-- running and the long-run warning never fires for a healthy telegraph.
	task.delay(duration + 0.2, cleanup)

	-- Early cleanup (the boss died mid-windup, the room unloaded) has to take
	-- the parts with it, or a cancelled attack leaves its warning painted on
	-- the floor. Destroying twice is safe, so this and the timers above can
	-- both fire.
	return function()
		footprint:Destroy()
		disc:Destroy()
	end
end
