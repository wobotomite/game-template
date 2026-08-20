local Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const use_event_listener = require(script.Parent["use-event-listener"])

local function use_character(): () -> Model?
	local character = vide.source(Players.LocalPlayer.Character)
	use_event_listener(Players.LocalPlayer.CharacterAdded, function(model: Model)
		character(model)
	end)
	use_event_listener(Players.LocalPlayer.CharacterRemoving, function()
		character(nil)
	end)
	return character
end

return use_character
