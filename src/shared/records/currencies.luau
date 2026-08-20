local ReplicatedStorage = game:GetService "ReplicatedStorage"

local const = require(ReplicatedStorage.Util.tables["const-record"])

export type CurrencyInfo = {
	name: string,
	color: Color3,
}

return const {
	coins = { name = "Coins", color = Color3.fromRGB(255, 200, 0) } :: CurrencyInfo,
}
