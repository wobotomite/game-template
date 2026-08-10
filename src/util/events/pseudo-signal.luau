const pseudo_connection = {}
pseudo_connection.__index = pseudo_connection

type EventMt<IN...> = {
	connect: (self: EventMt<IN...>, fn: (IN...) -> ()) -> (),
	fire: (self: EventMt<IN...>, IN...) -> (),
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

function pseudo_connection.new<T>(): EventType<T>
	return setmetatable({ __listeners = {} }, pseudo_connection)
end

function pseudo_connection.fire(self)
	for i, v in self.__listeners do
		task.defer(v)
	end
end

table.freeze(pseudo_connection)
return pseudo_connection
