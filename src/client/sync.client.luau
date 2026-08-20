const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm_sync = require(ReplicatedStorage.Packages["charm-sync"])
const client_network = require(script.Parent["client-network"])

task.wait(1)
client_network.charm.sync:connect(function(a0)
	charm_sync.client.patch(a0 :: any)
end)
