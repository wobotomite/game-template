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

type EventType<IN...> = setmetatable<
	{
		__listeners: { [() -> ()]: true },
		-- Reused dispatch buffer, held only while NOT in use (see `snapshot`).
		__scratch: { (...any) -> () }?,
	},
	{ __index: EventMt<IN...> }
>

function pseudo_connection.connect<T>(self, cb: () -> ())
	self.__listeners[cb] = true
	return function()
		self.__listeners[cb] = nil
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
	return setmetatable({ __listeners = {} }, pseudo_connection)
end

-- Reads the listener set into an array before any of them run.
--
-- A listener is allowed to connect or disconnect during dispatch, and some do:
-- tool-visuals' suction updater is itself a step listener, and it connects a
-- fresh per-effect listener to that SAME signal every time it spawns a wind
-- streak or a siphon orb. Adding a key to a table while `next` is walking it is
-- undefined in Lua -- it can skip listeners or throw "invalid key to 'next'"
-- outright -- so the walk has to finish before anything is called.
--
-- It also fixes the guest list: a listener connected mid-dispatch runs on the
-- NEXT fire rather than this one, which is the behaviour a per-frame effect
-- wants (its first frame is the frame after it was created, not a partial one).
--
-- The buffer is reused, so a per-frame fire costs no allocation.
--
-- A dispatch TAKES the buffer (leaving __scratch nil) and puts it back when it
-- finishes, rather than flagging itself as busy. RE-ENTRANCY is what that is
-- for, and it is the live case: a listener firing this same signal finds
-- nothing to take and allocates its own, instead of sharing one buffer and
-- shredding the outer walk.
--
-- It also fails safe, though that matters less than it used to. While the
-- inline dispatcher existed, a listener that threw unwound past the hand-back
-- and the buffer was simply lost -- the next fire allocated a replacement.
-- `task.spawn` now contains a listener error to its own thread, so the loop
-- always reaches the hand-back and that path is close to unreachable. The
-- take-and-return shape is kept anyway because the alternative is worse in a
-- specific way: a boolean "busy" flag restored after the loop would be stuck
-- true forever after one escape, quietly forcing an allocation on every
-- dispatch from then on -- the exact cost this buffer exists to avoid.
local function snapshot(self): ({ (...any) -> () }, number)
	local list = self.__scratch
	if list == nil then
		list = {} -- first fire, or a nested one that found the buffer taken
	else
		self.__scratch = nil
		table.clear(list)
	end
	local n = 0
	for fn in self.__listeners do
		n += 1
		list[n] = fn
	end
	return list, n
end

function pseudo_connection.fire(self, ...)
	const list, n = snapshot(self)
	for i = 1, n do
		const fn = list[i]
		-- Disconnected by an earlier listener in this same dispatch.
		if self.__listeners[fn] then
			task.spawn(fn, ...)
		end
	end
	self.__scratch = list
end

table.freeze(pseudo_connection)
return pseudo_connection
