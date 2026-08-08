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
	const network = require(ReplicatedStorage.Client.network)
	const generate_id = require(ReplicatedStorage.Util.strings["generate-id"])
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
	const network = require(ServerScriptService.Server.network)

	network.analytics.log_funnel:connect(function(player, data)
		assert(#data.session_id == ID_SIZE, "INVALID SESSION ID")
		const funnel_steps = assert((FUNNEL_STEPS :: never)[data.session_name], "INVALID SESSION!") :: { string }
		const at_step = assert(funnel_steps[data.step], "INVALID STEP!")
		AnalyticsService:LogFunnelStepEvent(player, data.session_name, data.session_id, data.step, at_step)
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
