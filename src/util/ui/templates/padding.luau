local ReplicatedStorage = game:GetService "ReplicatedStorage"

local px = require(ReplicatedStorage.Util.ui.hooks.px)
local ui_settings = require(ReplicatedStorage.Util.ui["ui-settings"])
local vide = require(ReplicatedStorage.Packages.vide)

return function(props: {
	PaddingTop: number?,
	PaddingLeft: number?,
	PaddingRight: number?,
	PaddingBottom: number?,
	Padding: number?,
})
	local function get_padding(n: number?): UDim | () -> UDim
		if n == 0 then
			return UDim.new(0, 0)
		end
		return px.udim(0, n or props.Padding or ui_settings.NUMBERS.PADDING)
	end

	return vide.create "UIPadding" {
		Name = "BasePadding",
		PaddingTop = get_padding(props.PaddingTop),
		PaddingLeft = get_padding(props.PaddingLeft),
		PaddingRight = get_padding(props.PaddingRight),
		PaddingBottom = get_padding(props.PaddingBottom),
	}
end
