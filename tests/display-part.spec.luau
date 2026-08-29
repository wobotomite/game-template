--!nocheck
-- util/instances/make-display-part: the four inert flags.
-- Run with:
--   lune run tests/display-part.spec.luau
--
-- WHY THIS ONE IS WORTH A SPEC when most builders are not. The four defaults
-- are the entire function -- everything else is `create-new` -- and the module's
-- own header records them drifting once already: a copied block where somebody
-- edited one copy left `CastShadow` on for a Neon disc lying flat on the floor.
--
-- `CanQuery` is the one that actually costs you. A cosmetic part that answers
-- raycasts blocks line-of-sight checks, stops floor probes and catches mouse
-- hits -- from something the player is not supposed to be able to touch. None
-- of that raises anything; it just makes an unrelated system behave oddly.

local h = require "./harness"
local env = require "./roblox-env"
local roblox = require "@lune/roblox"
local Vector3, Color3, CFrame, Enum = roblox.Vector3, roblox.Color3, roblox.CFrame, roblox.Enum

h.title "display part:"

local make_display_part = env.load "ReplicatedStorage.Util.instances.make-display-part"

do
	local part = make_display_part {
		Size = Vector3.new(1, 2, 3),
		Color = Color3.new(1, 0, 0),
	}

	h.check("anchored", part.Anchored == true)
	h.check("does not collide", part.CanCollide == false)
	h.check("does not answer raycasts", part.CanQuery == false)
	h.check("casts no shadow", part.CastShadow == false)

	h.check("size is what was asked for", part.Size == Vector3.new(1, 2, 3))
	h.check("colour is what was asked for", part.Color == Color3.new(1, 0, 0))
	h.equals("an unparented part stays unparented", part.Parent, nil)
end

do
	-- Real property names, straight through to `create-new`. There is no
	-- translation layer to keep in step with the Roblox API.
	local part = make_display_part {
		Size = Vector3.new(1, 1, 1),
		Color = Color3.new(0, 1, 0),
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(5, 6, 7),
		Transparency = 0.25,
		Name = "Telegraph",
	}
	h.check("material", part.Material == Enum.Material.Neon)
	h.check("shape", part.Shape == Enum.PartType.Cylinder)
	h.check("cframe", part.CFrame.Position == Vector3.new(5, 6, 7))
	h.equals("transparency", part.Transparency, 0.25)
	h.equals("name", part.Name, "Telegraph")
end

do
	-- Anything the module does not mention is just another property. The old
	-- signature needed an `extra` escape hatch for exactly this, which is the
	-- shape of an API that has to be kept in step with the engine's.
	local part = make_display_part {
		Size = Vector3.new(1, 1, 1),
		Color = Color3.new(0, 0, 1),
		Reflectance = 0.5,
	}
	h.equals("an unmentioned property is just a property", part.Reflectance, 0.5)
end

do
	-- The four are DEFAULTS, not a cage. A helper that refuses the one case
	-- somebody needs gets worked around, and the workaround is a hand-written
	-- block of four properties -- the thing this exists to prevent.
	local part = make_display_part {
		Size = Vector3.new(1, 1, 1),
		Color = Color3.new(1, 1, 1),
		CanCollide = true,
	}
	h.check("a caller can override a default by saying so", part.CanCollide == true)
	h.check("and the others still apply", part.CanQuery == false and part.Anchored == true)
end

do
	local holder = roblox.Instance.new "Folder"
	local part = make_display_part {
		Size = Vector3.new(1, 1, 1),
		Color = Color3.new(1, 1, 1),
		Parent = holder,
	}
	-- SYNCHRONOUSLY. `create-new` defers Parent, which is right for a long-lived
	-- instance and wrong for an effect part destroyed on a timer -- a Destroy
	-- landing first would leave the deferred write firing at a dead instance.
	-- This assigns it itself, last, so the parent is set when the call returns.
	h.equals("parents when asked, and before returning", part.Parent, holder)
end

h.done()
