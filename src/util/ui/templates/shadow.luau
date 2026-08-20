--!nocheck
local ReplicatedStorage = game:GetService "ReplicatedStorage"

local px = require(ReplicatedStorage.Util.ui.hooks.px)
local ui_types = require(ReplicatedStorage.Util.ui["ui-types"])
local vide = require(ReplicatedStorage.Packages.vide)

return function(props: { [any]: any, Transparency: ui_types.UsedAs<number>?, ZIndex: number? }): UIShadow
	return vide.create "UIShadow" {
		BlurRadius = props.BlurRadius or px.udim(0, 16),
		ZIndex = props.ZIndex or -1,
		Transparency = props.Transparency or 0.3,
	}
end
