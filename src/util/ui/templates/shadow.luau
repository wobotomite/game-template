--!nocheck
local ReplicatedStorage = game:GetService "ReplicatedStorage"

local px = require(ReplicatedStorage.Util.ui.hooks.px)
local ui_types = require(ReplicatedStorage.Util.ui["ui-types"])
local vide = require(ReplicatedStorage.Packages.vide)

-- UIShadow is a recent class. Probed ONCE, at require time, and the probe sets
-- the properties this actually writes -- not just the class name.
--
-- That distinction is the whole point: `vide.create "UIShadow" {}` succeeds on a
-- client where the class exists but `BlurRadius` rejects the value being passed,
-- so a class-only probe reports "supported" and the real call still throws. And
-- because this is built inside a vide tree, that throw does not fail one shadow
-- -- it takes the whole mount down, and the screen it was decorating with it.
--
-- BlurRadius is a **UDim**, not a number. Passing a number is the mistake this
-- probe catches on a client that has the class.
--
-- The probe instance is destroyed: it is parented nowhere, but it was created
-- outside any vide scope, so nothing else would ever collect it.
const SHADOW_SUPPORTED = pcall(function()
	const probe = vide.create "UIShadow" { BlurRadius = UDim.new(0, 16), Transparency = 0.3 }
	probe:Destroy()
end)

-- Returns nil where UIShadow is unavailable. vide skips a nil child, so a call
-- site can drop this straight into a children list and get no shadow rather
-- than no screen.
return function(props: { [any]: any, Transparency: ui_types.UsedAs<number>?, ZIndex: number? }): UIShadow?
	if not SHADOW_SUPPORTED then
		return nil
	end
	return vide.create "UIShadow" {
		BlurRadius = props.BlurRadius or px.udim(0, 16),
		ZIndex = props.ZIndex or -1,
		Transparency = props.Transparency or 0.3,
	}
end
