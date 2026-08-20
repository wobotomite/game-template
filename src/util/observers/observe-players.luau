const Players = game:GetService "Players"

const __create_observer = require(script.Parent["__create-observer"])

@native
function observe_players(callback: (Player) -> __create_observer.Cleanup): __create_observer.Cleanup
	return __create_observer(function(observer: __create_observer.Observer<Player>)
		local playerAdded = Players.PlayerAdded:Connect(function(player)
			observer.add(player, callback, player)
		end)
		local playerRemoving = Players.PlayerRemoving:Connect(function(player)
			observer.remove(player)
		end)
		for _, player in Players:GetPlayers() do
			observer.add(player, callback, player)
		end
		return function()
			playerAdded:Disconnect()
			playerRemoving:Disconnect()
		end
	end)
end

return observe_players
