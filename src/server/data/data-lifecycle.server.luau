const ReplicatedStorage = game:GetService "ReplicatedStorage"

const player_data = require(ReplicatedStorage.Shared.services["player-data"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

const datastore = require(script.Parent.datastore)

observe_players(function(player: Player): () -> ()
	datastore:load(player):catch(function(err)
		-- Playing without loaded data means nothing saves — silent progress
		-- loss. Log it and kick honestly instead (lyra already retried).
		warn(`[data] load failed for {player.Name}: {tostring(err)}`)
		if player.Parent then
			pcall(player.Kick, player, "Your save data couldn't be loaded. Please rejoin!")
		end
	end)
	return function()
		player_data.clear(player)
		-- May already be unloaded (save-before-teleport releases the session).
		datastore:unload(player):catch(function() end)
	end
end)

game:BindToClose(function()
	pcall(function()
		datastore:closeAsync()
	end)
end)
