const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm = require(ReplicatedStorage.Packages.charm)
const vide = require(ReplicatedStorage.Packages.vide)

return function<T>(atom: charm.Getter<T>)
	const val = vide.source(atom())
	const dtor = charm.listen(atom, function(state, lastState: T?)
		task.spawn(val, state)
	end)
	vide.cleanup(dtor)
	return val :: () -> T
end
