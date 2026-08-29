local ReplicatedStorage = game:GetService "ReplicatedStorage"

local alert = require(ReplicatedStorage.Shared.services.alert)
local px = require(ReplicatedStorage.Util.ui.hooks.px)
local use_atom = require(ReplicatedStorage.Util.ui.hooks["use-atom"])
local vide = require(ReplicatedStorage.Packages.vide)

local ALERT_LIFESPAN = 3
local ANIMATION_TIME = 0.2

local function alert_label(info: alert.alert_type, remove: () -> ())
	local visible = vide.source(0)
	local scale = vide.spring(visible, 0.2, 0.7)

	visible(1)
	task.delay(ALERT_LIFESPAN - ANIMATION_TIME, function()
		visible(0)
	end)
	task.delay(ALERT_LIFESPAN, remove)

	return vide.create "TextLabel" {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Text = info.message,
		RichText = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = px(22),

		vide.create "UIScale" {
			Scale = scale,
		},
	}
end

return function()
	local alerts = vide.source({} :: { [number]: alert.alert_type })
	local next_id = 0
	local current_alert = use_atom(alert.alert_atom)

	vide.effect(function()
		local atm = current_alert()
		if atm == nil then
			return
		end

		next_id += 1
		local id = next_id

		local new = table.clone(alerts())
		new[id] = atm
		alerts(new)
	end)

	return vide.create "ScreenGui" {
		Name = "Alerts",
		DisplayOrder = 900000,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,

		vide.create "Frame" {
			Size = UDim2.fromScale(0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,

			vide.create "UIListLayout" {
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			},

			vide.indexes(alerts, function(value, id)
				return alert_label(value(), function()
					local res = table.clone(alerts())
					res[id] = nil
					alerts(res)
				end)
			end),
		},
	}
end
