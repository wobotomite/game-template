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

type EventType<IN...> = setmetatable<{
	__listeners: { [() -> ()]: true },
}, { __index: EventMt<IN...> }>

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

function pseudo_connection.fire(self, ...)
	for fn in self.__listeners do
		task.spawn(fn, ...)
	end
end

table.freeze(pseudo_connection)
return pseudo_connection
