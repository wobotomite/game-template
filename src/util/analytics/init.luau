const __analytics_funnels = require(script.__analytics_funnels)
const __analytics_economy = require(script.__analytics_economy)

export type EconomyTransactionType = __analytics_economy.TransactionType

return table.freeze {
	funnels = __analytics_funnels,
	economy = __analytics_economy,
}
