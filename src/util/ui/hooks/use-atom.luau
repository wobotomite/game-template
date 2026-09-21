const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm = require(ReplicatedStorage.Packages.charm)
const vide = require(ReplicatedStorage.Packages.vide)

return function<T>(atom: charm.Getter<T>)
	const val = vide.source(atom())
	-- The write below is DEFERRED, so it can land after this scope was destroyed
	-- (an atom changes on the frame a panel unmounts). `dtor` stops new
	-- deliveries but cannot recall one already queued, and a source written
	-- after its scope died re-runs effects that have been cleaned up. The flag
	-- is what the queued write checks.
	local alive = true
	const function write(state: T)
		if alive then
			val(state)
		end
	end
	-- `subscribe`, NOT `listen`. The two differ in exactly one way in charm
	-- 0.11: `listen` invokes the callback once immediately, `subscribe` does
	-- not. The line above has already seeded the source with `atom()`, so
	-- `listen`'s immediate call was a deferred write of the value the source was
	-- just constructed with -- a wasted task per hook on every mount, and a
	-- source that spuriously counted as having CHANGED one frame into its life,
	-- which is visible to anything downstream that animates on change.
	--
	-- The signature difference follows: `subscribe` types `lastState` as `T`
	-- rather than `T?`, because without the initial call there is always a
	-- previous state.
	const dtor = charm.subscribe(atom, function(state, lastState: T)
		-- Defer: the listener runs inside charm's flush, and writing a vide
		-- source there nests graph evaluation inside the flush (recursion /
		-- script-timeout territory). Deferring lands the write outside both.
		task.defer(write, state)
	end)
	vide.cleanup(function()
		alive = false
		dtor()
	end)
	return val :: () -> T
end
