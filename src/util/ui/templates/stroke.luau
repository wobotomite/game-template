local ReplicatedStorage = game:GetService "ReplicatedStorage"

local ui_types = require(ReplicatedStorage.Util.ui["ui-types"])
local vide = require(ReplicatedStorage.Packages.vide)

return function(props: ui_types.VideProperties<"UIStroke">)
	return vide.create "UIStroke" {
		Color = props.Color,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Thickness = props.Thickness,
		LineJoinMode = props.LineJoinMode or Enum.LineJoinMode.Miter,
		Transparency = props.Transparency or 0,
		BorderStrokePosition = props.BorderStrokePosition or Enum.BorderStrokePosition.Outer,
	}
end
