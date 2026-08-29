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
	-- Was ReplicatedStorage.Client.network / ServerScriptService.Server.network
	-- below: neither path has ever existed. The modules are named
	-- client-network and server-network.
	const network = require(ReplicatedStorage.Client.net["client-network"])
	const current_session_id = session_id(session)
	network.analytics.log_funnel:fire {
		session_id = current_session_id,
		session_name = session,
		step = assert(table.find((FUNNEL_STEPS :: any)[session], step), "INVALID STEP"),
	}
end

function log_async<T>(session: T & keyof<typeof(SESSIONS)>, step: index<index<typeof(FUNNEL_STEPS), T>, number> | "")
	task.defer(log, session :: never, step)
end

if RunService:IsServer() then
	const network = require(ServerScriptService.Server.net["server-network"])

	-- A client can fire this as fast as it likes, so the handler is rate
	-- limited and REJECTS SILENTLY rather than asserting. sendbufs guarantees
	-- the payload's shape, not its values, and an assert on a remote handler
	-- is a client-triggerable server error: free log spam, and an exception
	-- thrown out of a shared dispatch costs whatever runs after it.
	const WINDOW_SECONDS = 5
	const MAX_LOGS_PER_WINDOW = 10
	const log_windows: { [Player]: { at: number, count: number } } = {}

	network.analytics.log_funnel:connect(function(player, data)
		local window = log_windows[player]
		if not window or os.clock() - window.at > WINDOW_SECONDS then
			window = { at = os.clock(), count = 0 }
			log_windows[player] = window
		end
		window.count += 1
		if window.count > MAX_LOGS_PER_WINDOW then
			return
		end
		-- Length AND alphabet. generate-id emits uppercase hex only, so any
		-- other character is a hand-crafted id -- a client polluting the funnel
		-- with ids the game never issued. (The VALUE is still the client's own
		-- random roll either way; this only pins the shape.)
		if #data.session_id ~= ID_SIZE or string.match(data.session_id, "^[0-9A-F]+$") == nil then
			return
		end
		const funnel_steps = (FUNNEL_STEPS :: never)[data.session_name] :: { string }?
		if not funnel_steps then
			return
		end
		const at_step = funnel_steps[data.step]
		if not at_step then
			return
		end
		AnalyticsService:LogFunnelStepEvent(player, data.session_name, data.session_id, data.step, at_step)
	end)

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		log_windows[player] = nil
	end)
elseif RunService:IsClient() then
	for i, v in SESSIONS :: { [any]: any } do
		log(i, INIT_STEP :: never)
	end
end

return table.freeze {
	log = log,
	log_async = log_async,
}
