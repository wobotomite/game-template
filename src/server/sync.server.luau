const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm_sync = require(ReplicatedStorage.Packages["charm-sync"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const server_network = require(script.Parent["server-network"])

charm_sync.server.connect(function(player: Player, payload)
	server_network.charm.sync:fire(player, payload)
end)
charm_sync.config.validatePatches = false
observe_players(function(player: Player): () -> ()
	return function()
		charm_sync.server:removeClient()
	end
end)
