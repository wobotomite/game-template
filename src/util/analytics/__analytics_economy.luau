const AnalyticsService = game:GetService "AnalyticsService"
const RunService = game:GetService "RunService"

export type TransactionType = "IAP" | "Shop" | "Gameplay" | "ContextualPurchase" | "TimedReward" | "Onboarding"

const FLOW_TYPES = {
	source = Enum.AnalyticsEconomyFlowType.Source,
	sink = Enum.AnalyticsEconomyFlowType.Sink,
}

function log(
	flow: "source" | "sink",
	player: Player,
	currency: string,
	amount: number,
	ending_balance: number,
	transaction: TransactionType,
	sku: string?
)
	assert(RunService:IsServer(), "economy analytics are server only!")
	pcall(function()
		AnalyticsService:LogEconomyEvent(player, FLOW_TYPES[flow], currency, amount, ending_balance, transaction, sku)
	end)
end

function source(
	player: Player,
	currency: string,
	amount: number,
	ending_balance: number,
	transaction: TransactionType,
	sku: string?
)
	log("source", player, currency, amount, ending_balance, transaction, sku)
end

function sink(
	player: Player,
	currency: string,
	amount: number,
	ending_balance: number,
	transaction: TransactionType,
	sku: string?
)
	log("sink", player, currency, amount, ending_balance, transaction, sku)
end

return table.freeze {
	source = source,
	sink = sink,
}
