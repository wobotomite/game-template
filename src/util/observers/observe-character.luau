const __create_observer = require(script.Parent["__create-observer"])

@native
function observe_character(player: Player, callback: (Model) -> __create_observer.Cleanup?): __create_observer.Cleanup
	return __create_observer(function(observer: __create_observer.Observer<"character">)
		local characterAdded = player.CharacterAdded:Connect(function(character)
			observer.add("character", callback, character)
		end)

		local characterRemoving = player.CharacterRemoving:Connect(function()
			observer.remove "character"
		end)

		if player.Character then
			observer.add("character", callback, player.Character)
		end

		return function()
			characterAdded:Disconnect()
			characterRemoving:Disconnect()
		end
	end)
end

return observe_character
