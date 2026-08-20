const ReplicatedStorage = game:GetService "ReplicatedStorage"

const sendbufs = require(ReplicatedStorage.Packages.sendbufs)
const REMOTES = {
	charm = table.freeze {
		sync = sendbufs.event(sendbufs.schema.ref),
	},
}

table.freeze(REMOTES)

return REMOTES
