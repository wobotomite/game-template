const ReplicatedStorage = game:GetService "ReplicatedStorage"

const sendbufs = require(ReplicatedStorage.Packages.sendbufs)
const network = require(ReplicatedStorage.Shared.network)
return sendbufs.create_server(network, 4096)
