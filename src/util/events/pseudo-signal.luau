const ReplicatedStorage = game:GetService "ReplicatedStorage"

const count_map = require(ReplicatedStorage.Util.tables["count-map"])
const pseudo_connection = {}
pseudo_connection.__index = pseudo_connection

type EventMt<IN...> = {
	connect: (self: EventMt<IN...>, fn: (IN...) -> ()) -> () -> (),
	fire: (self: EventMt<IN...>, IN...) -> (),
	wait: (self: EventMt<IN...>) -> IN...,
	count: (self: EventMt<IN...>) -> number,
}

-- The cached dispatch order, and the two bits of bookkeeping that keep it
-- honest: `dirty` says the listener set changed since `order` was built, and
-- `depth` counts how many fires are walking it right now (see `fire`).
type Dispatch = {
	order: { (...any) -> () },
	n: number,
	dirty: boolean,
	depth: number,
}

type EventType<IN...> = setmetatable<{
	__listeners: { [() -> ()]: true },
	__dispatch: Dispatch,
}, { __index: EventMt<IN...> }>

function pseudo_connection.connect<T>(self, cb: () -> ())
	self.__listeners[cb] = true
	-- The ONLY two places the listener set can change, so the only two places
	-- that have to invalidate the cached order. Missing one of these is the
	-- failure mode of this design: a stale order calls a disconnected listener
	-- (caught by the membership check in `fire`) or skips a new one forever
	-- (not caught by anything).
	self.__dispatch.dirty = true
	return function()
		self.__listeners[cb] = nil
		self.__dispatch.dirty = true
	end
end

function pseudo_connection.wait(self)
	const coro = coroutine.running()
	local c
	c = self:connect(function(...)
		c()
		if coroutine.status(coro) ~= "suspended" then
			return
		end
		coroutine.resume(coro, ...)
	end)
	return coroutine.yield()
end

function pseudo_connection.count(self)
	return count_map(self.__listeners)
end

function pseudo_connection.new<T>(): EventType<T>
	return setmetatable({
		__listeners = {},
		__dispatch = { order = {}, n = 0, dirty = false, depth = 0 },
	}, pseudo_connection)
end

-- Dispatch reads the listener set into an ARRAY before any of them run, and
-- CACHES that array between fires.
--
-- WHY AN ARRAY AT ALL. A listener is allowed to connect or disconnect during
-- dispatch, and some do: tool-visuals' suction updater is itself a step
-- listener, and it connects a fresh per-effect listener to that SAME signal
-- every time it spawns a wind streak or a siphon orb. Adding a key to a table
-- while `next` is walking it is undefined in Lua -- it can skip listeners or
-- throw "invalid key to 'next'" outright -- so the walk has to finish before
-- anything is called.
--
-- It also fixes the guest list: a listener connected mid-dispatch runs on the
-- NEXT fire rather than this one, which is the behaviour a per-frame effect
-- wants (its first frame is the frame after it was created, not a partial one).
--
-- WHY IT IS CACHED RATHER THAN REBUILT. The array used to be refilled from the
-- hash part on every single fire. On a step signal that is a full walk of the
-- listener set 60 times a second whether or not anything changed, and the set
-- is stable for long stretches -- a HUD that mounts once and runs for a whole
-- round never changes it again. `dirty` is set by the only two operations that
-- can invalidate the order (see `connect`), so a steady-state fire is now an
-- indexed loop over an array that is already correct.
--
-- WHY A NESTED FIRE GETS ITS OWN ARRAY. Re-entrancy is live here, not
-- theoretical: a listener is allowed to fire the same signal it is being
-- dispatched from. If that inner fire found `dirty` set it would rebuild --
-- and rebuilding means `table.clear` on the array the OUTER loop is still
-- indexing, which silently truncates the outer dispatch and drops every
-- listener it had not reached yet. So `depth > 0` means "somebody is walking
-- the cache": build into a throwaway table instead, and leave `dispatch.n` and
-- `dirty` alone so the outer frame's view stays intact and the NEXT top-level
-- fire still knows it has to rebuild.
--
-- `depth` is a counter rather than a boolean because the nesting can go more
-- than one level deep, and a boolean cleared by the innermost return would tell
-- the middle frames they were safe to clear.
function pseudo_connection.fire(self, ...)
	const listeners = self.__listeners
	const dispatch = self.__dispatch

	local order, n = dispatch.order, dispatch.n
	if dispatch.dirty then
		const nested = dispatch.depth > 0
		order = if nested then {} else dispatch.order
		table.clear(order)
		n = 0
		for fn in listeners do
			n += 1
			order[n] = fn
		end
		if not nested then
			dispatch.n = n
			dispatch.dirty = false
		end
	end

	dispatch.depth += 1
	for i = 1, n do
		const fn = order[i]
		-- Disconnected by an earlier listener in this same dispatch. The cached
		-- order can also be one fire STALE in the nested case above, so this
		-- membership check is what keeps a dropped listener from being called.
		if listeners[fn] then
			task.spawn(fn, ...)
		end
	end
	dispatch.depth -= 1
end

table.freeze(pseudo_connection)
return pseudo_connection
