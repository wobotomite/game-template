const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm = require(ReplicatedStorage.Packages.charm)
const vide = require(ReplicatedStorage.Packages.vide)
return function(fx: () -> ...charm.Cleanup?)
	const dispose = vide.untrack(function()
		return charm.effect(fx)
	end)
	vide.cleanup(dispose)
	return dispose
end
