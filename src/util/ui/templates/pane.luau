const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const ui_types = require(ReplicatedStorage.Util.ui["ui-types"])

return function(props: ui_types.VideProperties<"Frame">)
	const frame = vide.create "Frame" {
		Name = props.Name or "Pane",
		BorderSizePixel = 0,
		Selectable = false,
		Transparency = 1,
		AutomaticSize = if props.Size then nil else Enum.AutomaticSize.XY,
	}

	vide.apply(frame, props)
	return frame
end
