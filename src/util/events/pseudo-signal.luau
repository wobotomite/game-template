const ReplicatedStorage = game:GetService "ReplicatedStorage"

const count_map = require(ReplicatedStorage.Util.tables["count-map"])
const pseudo_connection = {}
pseudo_connection.__index = pseudo_connection

-- One warning per broken listener (or waiter), ever. A listener on a step
-- signal that throws does so EVERY frame, and sixty identical lines a second
-- bury the first one -- which is the only one carrying information. Weak keys,
-- so remembering a listener here never keeps it alive.
const warned: { [(...any) -> ()]: true } = setmetatable({}, { __mode = "k" }) :: any

type EventMt<IN...> = {
	connect: (self: EventMt<IN...>, fn: (IN...) -> ()) -> () -> (),
	fire: (self: EventMt<IN...>, IN...) -> (),
	wait: (self: EventMt<IN...>) -> IN...,
	count: (self: EventMt<IN...>) -> number,
}

-- The cached dispatch order, and the two bits of bookkeeping that keep it
-- honest: `dirty` says the listener set changed since `order` was built, and
-- `depth` counts how many fires are walking it right now (see `fire`).
-- `resume*` is the queue of `wait()` callers this dispatch has to wake once it
-- is over (see `wait`).
type Dispatch = {
	order: { (...any) -> () },
	n: number,
	dirty: boolean,
	depth: number,
	resume: { thread },
	resume_args: { any },
	resume_n: number,
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

-- A waiter is QUEUED by its listener and resumed after the dispatch that woke
-- it has finished, never from inside it.
--
-- Resuming inline ran the waiter's continuation in the middle of the listener
-- loop: whatever it did next -- fire this signal again, connect, destroy the
-- thing the remaining listeners were about to read -- happened between two
-- listeners of the same fire, and if it yielded again the rest of the dispatch
-- waited on it. Queued, every listener of a fire sees the same world, and the
-- waiters then run in the order they were woken.
function pseudo_connection.wait(self)
	const coro = coroutine.running()
	const dispatch = self.__dispatch
	local c
	c = self:connect(function(...)
		c()
		if coroutine.status(coro) ~= "suspended" then
			return
		end
		const at = dispatch.resume_n + 1
		dispatch.resume_n = at
		dispatch.resume[at] = coro
		dispatch.resume_args[at] = table.pack(...)
	end)
	return coroutine.yield()
end

function pseudo_connection.count(self)
	return count_map(self.__listeners)
end

function pseudo_connection.new<T>(): EventType<T>
	return setmetatable({
		__listeners = {},
		__dispatch = { order = {}, n = 0, dirty = false, depth = 0, resume = {}, resume_args = {}, resume_n = 0 },
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
--
-- WHY LISTENERS ARE CALLED IN PLACE, NOT SPAWNED. This used to be
-- `task.spawn(fn, ...)` -- one coroutine per listener per fire. A game built on
-- this template measured ~30 unthrottled step signals per rendered frame, which
-- is ~30 coroutine allocations before any gameplay code ran. `pcall` keeps the
-- isolation that mattered (one throwing listener cannot stop the rest, and the
-- throw is reported once instead of leaking into the scheduler) without the
-- allocation.
--
-- THE CONTRACT THAT BUYS: A LISTENER MUST NOT YIELD. `pcall` is yieldable in
-- Luau, so a listener that waits does not error -- it parks the whole dispatch,
-- and every listener after it runs late. Return immediately and `task.spawn` the
-- waiting, which is the same rule a reactive scope already lives under. The
-- census that made the switch safe found no yield in 64 step-listener bodies.
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
			const ok, err = pcall(fn, ...)
			if not ok and not warned[fn] then
				warned[fn] = true
				warn(`[pseudo-signal] a listener errored and was reported once: {err}`)
			end
		end
	end
	dispatch.depth -= 1

	-- Wake the `wait()` callers, but only from the OUTERMOST fire: a nested fire
	-- returning is still inside somebody else's listener loop. The queue is moved
	-- out before anything resumes because a resumed waiter may call `wait()`
	-- again at once, and that write must land in a fresh queue, not the one being
	-- walked.
	if dispatch.depth == 0 and dispatch.resume_n > 0 then
		const pending_n = dispatch.resume_n
		const pending = table.move(dispatch.resume, 1, pending_n, 1, {})
		const pending_args = table.move(dispatch.resume_args, 1, pending_n, 1, {})
		table.clear(dispatch.resume)
		table.clear(dispatch.resume_args)
		dispatch.resume_n = 0

		for i = 1, pending_n do
			const coro = pending[i]
			const packed = pending_args[i] :: any
			if coroutine.status(coro) == "suspended" then
				const ok, err = coroutine.resume(coro, table.unpack(packed, 1, packed.n))
				if not ok and not warned[coro :: any] then
					warned[coro :: any] = true
					warn(`[pseudo-signal] a waiter errored and was reported once: {err}`)
				end
			end
		end
	end
end

table.freeze(pseudo_connection)
return pseudo_connection
