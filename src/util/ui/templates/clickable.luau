local ReplicatedStorage = game:GetService "ReplicatedStorage"

local ui_types = require(ReplicatedStorage.Util.ui["ui-types"])
local vide = require(ReplicatedStorage.Packages.vide)

export type ClickableProps = {
	Enabled: ui_types.UsedAs<boolean>?,
	Hover: ((input: InputObject) -> ())?,
	Unhover: ((input: InputObject) -> ())?,
	ButtonDown: ((input: InputObject) -> ())?,
	ButtonUp: ((input: InputObject) -> ())?,
	OnClick: (() -> ())?,
	Selectable: boolean?,
}

return function(props: ClickableProps)
	return vide.create "TextButton" {
		Name = "Clickable",
		Transparency = 1,
		Size = UDim2.fromScale(1, 1),
		AutoButtonColor = false,
		Text = "",
		Interactable = props.Enabled,
		MouseEnter = props.Hover,
		MouseButton1Down = props.ButtonDown,
		MouseButton1Up = props.ButtonUp,
		MouseLeave = props.Unhover,
		MouseButton1Click = props.OnClick,
		Selectable = props.Selectable,
		ZIndex = 100,
	}
end
