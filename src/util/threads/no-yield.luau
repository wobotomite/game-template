
@native
function resultHandler(co: thread, ok: boolean, ...)
	if not ok then
		local message = (...)
		error(debug.traceback(co, message), 2)
	end

	if coroutine.status(co) ~= "dead" then
		error(debug.traceback(co, "attempt to yield"), 2)
	end

	return ...
end

@native
function noYield<Input..., Output...>(callback: (Input...) -> Output..., ...: Input...): Output...
	local co = coroutine.create(callback)

	return resultHandler(co, coroutine.resume(co, ...))
end

return noYield
