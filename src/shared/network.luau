const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

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
	daily = table.freeze {
		-- "Claim today's reward." NO PAYLOAD, deliberately: which day is being
		-- claimed is decided by the server from the player's own save, so there
		-- is nothing for a modified client to lie about. A `day` field here
		-- would be a field the server has to ignore, which is a field somebody
		-- later trusts.
		--
		-- The answer comes back as the save itself -- `data.daily` replicates
		-- through `player-data` -- plus an alert saying which verdict it was.
		claim = sendbufs.event(),
	},

	-- STUDIO ONLY, and `nil` everywhere else, so the remote that runs debug
	-- commands does not exist in a published place at all. A `RunService:IsStudio()`
	-- check inside the handler is a check somebody can forget or a payload
	-- somebody can reach; an event that was never declared cannot be fired.
	--
	-- Both realms evaluate this line, and in any one session they agree --
	-- Studio Play is Studio on both sides, a live server is neither. It is
	-- declared LAST for the ordering note above: a group that is sometimes
	-- absent must not sit in front of events whose ids would then shift with it.
	--
	-- Handled by `src/server/debug-commands.server.luau`.
	debug = if RunService:IsStudio()
		then table.freeze {
			command = sendbufs.event(sendbufs.schema.struct {
				name = sendbufs.schema.str,
				-- One number and one string, whatever the command wants them to
				-- mean: `f64` rather than an integer type because a command may
				-- want a fraction, and the handler checks the value is finite
				-- before any command sees it.
				value = sendbufs.schema.f64,
				text = sendbufs.schema.str,
			}),
		}
		else nil,
}

table.freeze(REMOTES)

return REMOTES
