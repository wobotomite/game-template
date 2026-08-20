local ReplicatedStorage = game:GetService "ReplicatedStorage"

local ui_types = require(ReplicatedStorage.Util.ui["ui-types"])
local vide = require(ReplicatedStorage.Packages.vide)

return function(props: ui_types.VideProperties<"ScreenGui">)
	local screen = vide.create "ScreenGui" {
		Name = props.Name or "BaseScreen",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	}

	vide.apply(screen)(props)
	return screen
end
