const AnalyticsService = game:GetService "AnalyticsService"

const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"
const ServerScriptService = game:GetService "ServerScriptService"

const generate_id = require(script.Parent.Parent.strings["generate-id"])

const INIT_STEP = "PlayerJoined"

-- SESSIONS AND FUNNEL STEPS:
const ID_SIZE = 24
function new_id()
	return generate_id(ID_SIZE)
end

function array<T>(...: T | ""): { T | "" | typeof(INIT_STEP) }
	return { INIT_STEP, ... }
end

const SESSIONS = {
	ShopSession = new_id(),
	ShopCurrencySession = new_id(),
	ShopAbilitySession = new_id(),
	InviteFriendSession = new_id(),
}
const FUNNEL_STEPS = {
	ShopSession = array("OpenShop", "ClickShopItem", "PurchaseShopItem"),
	ShopCurrencySession = array("OpenShop", "ClickCurrencyTab", "PurchaseCurrency"),
	InviteFriendSession = array("PressInviteButton", "FriendInvited"),
	ShopAbilitySession = array("OpenShop", "ClickAbilityTab", "PurchaseAbility"),
}
table.freeze(SESSIONS)
table.freeze(FUNNEL_STEPS)

function session_id(key: keyof<typeof(SESSIONS)>): string
	assert(RunService:IsClient(), "sessions are client only!")
	return assert((SESSIONS :: any)[key], `INVALID SESSION {key}`)
end

function log<T>(session: T & keyof<typeof(SESSIONS)>, step: index<index<typeof(FUNNEL_STEPS), T>, number> | "")
	assert(RunService:IsClient(), "logging is client only!")

	-- RESOLVE THE STEP FIRST, and return quietly when it is not one of this
	-- session's. It used to be `assert(table.find(...), "INVALID STEP")` inline
	-- in the payload, which throws out of whatever gameplay code logged it --
	-- so a step renamed in FUNNEL_STEPS and missed at one call site took down a
	-- purchase flow, over a telemetry line. Analytics is the least important
	-- thing in any function that calls it and must never be the thing that
	-- breaks it.
	--
	-- The TYPES still catch this at the call site; what changes is the
	-- behaviour of the case the types could not see (an `any`, a string built
	-- at runtime) once it is live in front of players.
	const at_step = table.find((FUNNEL_STEPS :: any)[session], step)
	if at_step == nil then
		return
	end
	-- Was ReplicatedStorage.Client.network / ServerScriptService.Server.network
	-- below: neither path has ever existed. The modules are named
	-- client-network and server-network.
	const network = require(ReplicatedStorage.Client.net["client-network"])
	network.analytics.log_funnel:fire {
		session_id = session_id(session),
		session_name = session,
		step = at_step,
	}
end

function log_async<T>(session: T & keyof<typeof(SESSIONS)>, step: index<index<typeof(FUNNEL_STEPS), T>, number> | "")
	task.defer(log, session :: never, step)
end

if RunService:IsServer() then
	const network = require(ServerScriptService.Server.net["server-network"])
	const validate = require(ServerScriptService.Server.net.validate)

	-- A client can fire this as fast as it likes, so the handler is rate
	-- limited and REJECTS SILENTLY rather than asserting. sendbufs guarantees
	-- the payload's shape, not its values, and an assert on a remote handler
	-- is a client-triggerable server error: free log spam, and an exception
	-- thrown out of a shared dispatch costs whatever runs after it.
	const WINDOW_SECONDS = 5
	const MAX_LOGS_PER_WINDOW = 10
	-- Ceilings for the two free-form fields, so the checks below run on
	-- something bounded. A session name longer than any real one cannot match
	-- FUNNEL_STEPS anyway; the point is that it is rejected before it is used
	-- as a table key or reaches AnalyticsService.
	const NAME_MAX_CHARS = 64
	const STEP_CEILING = 255
	-- THE SHARED LIMITER, not a window table of this handler's own. The old
	-- one here was a tumbling window -- a client could land the full ten just
	-- before the reset and ten more just after -- and it needed its own
	-- PlayerRemoving connection to avoid holding a table entry per player who
	-- ever logged. `validate.limiter` is a true sliding window and clears
	-- departed players from every limiter at once.
	const log_limiter = validate.limiter(MAX_LOGS_PER_WINDOW, WINDOW_SECONDS)

	network.analytics.log_funnel:connect(function(player, data)
		if not log_limiter(player) then
			return
		end

		-- Through `validate` rather than read straight off `data`. The schema
		-- fixes the TYPES; these fix the values -- `data.step` is a number by
		-- the schema, and `nil`, a fraction and 1e18 are all numbers.
		const id = validate.text(data.session_id, ID_SIZE)
		const session_name = validate.text(data.session_name, NAME_MAX_CHARS)
		const step = validate.count(data.step, STEP_CEILING)
		if id == nil or session_name == nil or step == nil then
			return
		end
		-- Length AND alphabet. generate-id emits uppercase hex only, so any
		-- other character is a hand-crafted id -- a client polluting the funnel
		-- with ids the game never issued. (The VALUE is still the client's own
		-- random roll either way; this only pins the shape.)
		if #id ~= ID_SIZE or string.match(id, "^[0-9A-F]+$") == nil then
			return
		end
		const funnel_steps = (FUNNEL_STEPS :: never)[session_name] :: { string }?
		if not funnel_steps then
			return
		end
		const at_step = funnel_steps[step]
		if not at_step then
			return
		end
		AnalyticsService:LogFunnelStepEvent(player, session_name, id, step, at_step)
	end)
elseif RunService:IsClient() then
	-- DEFERRED, one per session. `log` requires client-network on its first
	-- call, and building the client wire waits on instances the server has to
	-- replicate first -- so calling it from this module's own body makes
	-- requiring this module yield until they arrive, and every client module
	-- that requires analytics waits behind it. `task.defer` hands the wait to
	-- the scheduler instead, and the module finishes loading immediately.
	for session in SESSIONS :: { [any]: any } do
		log_async(session :: never, INIT_STEP :: never)
	end
end

return table.freeze {
	log = log,
	log_async = log_async,
}
