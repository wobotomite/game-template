const ReplicatedStorage = game:GetService "ReplicatedStorage"

const create = require(ReplicatedStorage.Util.instances["create-new"])

-- A Part that is SEEN and never interacted with: viewport props, viewmodel
-- geometry, graybox placeholders, ground decals, telegraphs.
--
--   const disc = make_display_part {
--       Size = Vector3.new(0.25, 12, 12),
--       Color = palette.WARNING,
--       Material = Enum.Material.Neon,
--       Shape = Enum.PartType.Cylinder,
--       CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2),
--       Transparency = 0.5,
--       Parent = workspace,
--   }
--
-- Real property names, passed through `create-new`. There is no bespoke props
-- table to learn and no escape hatch to reach for, because anything this does
-- not mention is just another property.
--
-- ========================= WHAT THIS ADDS, AND ONLY ======================
--
-- Four defaults:
--
--     Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false
--
-- That is the entire function. It exists because those four get copy-pasted as
-- a block and then one copy drifts -- which already happened here once, leaving
-- `CastShadow` on for a Neon disc lying flat on the floor. Not a look anybody
-- chose; what a copied block looks like after somebody edits one of them.
--
-- `CanQuery` is the one that actually costs you. A cosmetic part that answers
-- raycasts blocks line-of-sight checks, stops floor probes and catches mouse
-- hits, from something the player is not supposed to be able to touch. Nothing
-- raises; an unrelated system just behaves oddly.
--
-- They are DEFAULTS, not a cage: pass `CanCollide = true` and you get it. A
-- helper that refuses the one case somebody needs gets worked around, and the
-- workaround is a hand-written block of four properties -- the thing this is
-- here to prevent.
--
-- ============ WHY NOT vide, AND WHY NOT ReflectionService ================
--
-- **vide** builds a reactive scope: sources, bindings, cleanup, and an expected
-- `root` above it. That is right for UI and wrong for static world geometry,
-- and it would pull a UI graph into effects and into anything server-side that
-- wanted a part. It also would not help with the actual problem -- vide has no
-- opinion about `CanQuery`, so every call site would still write the four
-- flags by hand.
--
-- **ReflectionService** is introspection: `GetPropertiesOfClass`,
-- `GetPropertyNames`. It can tell you a property exists; it cannot set one. It
-- could validate names at runtime, which is a different feature that costs more
-- than it saves here -- and it is a service regular scripts should not assume
-- they can reach.
--
-- ============================ NOT FOR DEBUG ==============================
--
-- Spawning a Part to see where a ray landed is the most common reason this gets
-- called and the wrong tool for it. `util/debug/gizmos` draws rays, casts,
-- bounds, CFrames and text, and clears itself every frame, so there is no
-- instance to name, parent, track or destroy. It is developer-only -- it draws
-- nothing unless the debug flag is on -- and this is for geometry a PLAYER
-- sees.

const INERT = table.freeze {
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CastShadow = false,
}

return function(properties: create.Properties<"Part">): Part
	-- The merge is plumbing, so it is typed as plumbing. `create.Properties`
	-- describes a fixed set of named properties and carries no string indexer,
	-- so writing `merged[key]` through a variable key is not something that type
	-- permits -- and it should not have to. The CALLER-facing type on the
	-- parameter above is where the checking belongs and where it still happens.
	const merged: { [string]: any } = {}
	for key, value in INERT do
		merged[key] = value
	end
	-- Caller wins: these are defaults, not a cage. Parent included -- `create`
	-- writes it last and synchronously now, so there is nothing to hold back.
	for key, value in properties :: any do
		merged[key] = value
	end
	return create("Part", merged :: any)
end
