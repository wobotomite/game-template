export type Cleanup = () -> ()

export type Observer<Key> = {
	add: <Args...>(instance: Key, factory: (Args...) -> Cleanup?, Args...) -> (),
	remove: (instance: Key) -> (),
	clear: () -> (),
}

@native
function noop() end

@native
function create_observer<Key>(setup: (Observer<Key>) -> Cleanup): Cleanup
	local cleanups: { [Key]: Cleanup } = {}

	local function remove(key: Key)
		local cleanup = cleanups[key]
		if cleanup then
			cleanups[key] = nil
			cleanup()
		end
	end

	local function add<Args...>(key: Key, factory: (Args...) -> Cleanup?, ...: Args...)
		remove(key)
		cleanups[key] = factory(...) or noop
	end

	local function clear()
		for key, cleanup in cleanups do
			cleanup()
			cleanups[key] = nil
		end
	end

	local stop = setup(table.freeze {
		add = add,
		remove = remove,
		clear = clear,
	})

	return function()
		stop()
		clear()
	end
end

return create_observer
