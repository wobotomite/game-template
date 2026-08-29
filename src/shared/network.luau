const ReplicatedStorage = game:GetService "ReplicatedStorage"

const sendbufs = require(ReplicatedStorage.Packages.sendbufs)
const REMOTES = {
	charm = table.freeze {
		sync = sendbufs.event(sendbufs.schema.ref),
		-- Fired by the client once its sync listeners are registered (and
		-- again whenever a feature module registers an atom later); the server
		-- answers with a full snapshot of every registered atom.
		--
		-- NOTE ON ORDER: sendbufs event ids are the DECLARATION ORDER of this
		-- table, so inserting an event in the middle renumbers every one after
		-- it. Append new events at the end of their group.
		request_sync = sendbufs.event(),
	},
	core = table.freeze {
		send_alert = sendbufs.event(sendbufs.schema.struct {
			message = sendbufs.schema.str,
			sound = sendbufs.schema.maybe(sendbufs.schema.str),
		}),
	},
	-- util/analytics/__analytics_funnels fires and handles this. It lived in
	-- that module without ever existing here, so requiring the analytics util
	-- indexed nil on both realms.
	analytics = table.freeze {
		log_funnel = sendbufs.event(sendbufs.schema.struct {
			session_id = sendbufs.schema.str,
			session_name = sendbufs.schema.str,
			step = sendbufs.schema.u8,
		}),
	},
}

table.freeze(REMOTES)

return REMOTES
