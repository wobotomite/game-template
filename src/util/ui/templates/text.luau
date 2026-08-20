local ReplicatedStorage = game:GetService "ReplicatedStorage"

local px = require(ReplicatedStorage.Util.ui.hooks.px)
local ui_settings = require(ReplicatedStorage.Util.ui["ui-settings"])
local ui_types = require(ReplicatedStorage.Util.ui["ui-types"])
local vide = require(ReplicatedStorage.Packages.vide)

export type TextProps = ui_types.VideProperties<"TextLabel"> & { Stroke: ui_types.UsedAs<number>? }

return function(props: TextProps)
	return vide.create "TextLabel" {
		Name = props.Name or "BaseText",
		AutomaticSize = props.AutomaticSize,
		ZIndex = props.ZIndex,
		TextWrapped = props.TextWrapped,
		LayoutOrder = props.LayoutOrder,
		TextXAlignment = props.TextXAlignment,
		TextYAlignment = props.TextYAlignment,
		TextScaled = props.TextScaled,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Visible = props.Visible,
		TextTruncate = props.TextTruncate,
		Interactable = false,
		Selectable = false,
		BackgroundTransparency = 1,
		FontFace = props.FontFace or ui_settings.FONTS.DEFAULT,
		TextColor3 = props.TextColor3 or ui_settings.COLORS.WHITE,
		Text = props.Text,
		TextSize = props.TextSize or px(ui_settings.NUMBERS.FONT_LARGE),
		TextTransparency = props.TextTransparency or 0,
		RichText = props.RichText,

		if props.Stroke
			then vide.create "UIStroke" {
				LineJoinMode = Enum.LineJoinMode.Miter,
				Thickness = props.Stroke,
				Transparency = props.TextTransparency or 0,
			}
			else nil,

		table.unpack(props),
	}
end
