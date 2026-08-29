const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm = require(ReplicatedStorage.Packages.charm)
const vide = require(ReplicatedStorage.Packages.vide)

return function<T>(atom: charm.Getter<T>)
	const val = vide.source(atom())
	const dtor = charm.listen(atom, function(state, lastState: T?)
		-- Defer: the listener runs inside charm's flush, and writing a vide
		-- source there nests graph evaluation inside the flush (recursion /
		-- script-timeout territory). Deferring lands the write outside both.
		task.defer(val, state)
	end)
	vide.cleanup(dtor)
	return val :: () -> T
end
