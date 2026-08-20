local ReplicatedStorage = game:GetService "ReplicatedStorage"

local greentea = require(ReplicatedStorage.Packages.greentea)

return greentea.build(greentea.struct {
	currency = greentea.struct {
		coins = greentea.number(),
	},
})
