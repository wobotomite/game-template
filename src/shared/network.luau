const ReplicatedStorage = game:GetService "ReplicatedStorage"

const sendbufs = require(ReplicatedStorage.Packages.sendbufs)
const REMOTES = {
	charm = table.freeze {
		sync = sendbufs.event(sendbufs.schema.ref),
	},
	core = table.freeze {
		send_alert = sendbufs.event(sendbufs.schema.struct {
			message = sendbufs.schema.str,
			sound = sendbufs.schema.maybe(sendbufs.schema.str),
		}),
	},
}

table.freeze(REMOTES)

return REMOTES
