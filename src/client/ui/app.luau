local ReplicatedStorage = game:GetService "ReplicatedStorage"

local alerts = require(script.Parent.pages.alerts)
local px = require(ReplicatedStorage.Util.ui.hooks.px)
local vide = require(ReplicatedStorage.Packages.vide)

local function app()
	px.usePx()

	return vide.create "ScreenGui" {
		Name = "App",
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,

		alerts(),
	}
end

return app
