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

	-- One fresh table per `add`, used only for its IDENTITY. It marks which
	-- GENERATION of a key the factory currently running belongs to; see `add`
	-- for why a boolean would not be enough.
	local tokens: { [Key]: {} } = {}

	local function remove(key: Key)
		-- Voided BEFORE the cleanup runs, so an `add` still inside its factory
		-- for this key can tell that its generation is gone.
		tokens[key] = nil
		local cleanup = cleanups[key]
		if cleanup then
			cleanups[key] = nil
			cleanup()
		end
	end

	local function add<Args...>(key: Key, factory: (Args...) -> Cleanup?, ...: Args...)
		remove(key)
		local token = {}
		tokens[key] = token
		local cleanup = factory(...) or noop
		-- THE FACTORY CAN REMOVE ITS OWN KEY WHILE IT IS STILL RUNNING. A
		-- factory that yields -- a WaitForChild on a streaming character, an
		-- await on a profile load -- is still executing when the event that
		-- removes that key arrives, and `remove` has by then already torn down
		-- everything there was to tear down. Filing the cleanup it eventually
		-- returns under that key leaves a LIVE teardown attached to an entry
		-- nobody will ever remove again: a connection, a humanoid hook, a
		-- per-character loop, kept for the life of the process with no handle
		-- left to reach it by. Nothing errors, nothing warns; it only shows up
		-- as a callback firing for a character that left.
		--
		-- So: if the generation is no longer ours, run the cleanup NOW and
		-- store nothing.
		--
		-- Identity rather than a flag, because the key can have been removed
		-- AND re-added while this factory ran (a respawn inside a yielding
		-- factory). A "was removed" boolean would be cleared by the re-add and
		-- this stale cleanup would then be written over the NEW generation's.
		-- Comparing the token is the only test that answers the actual
		-- question: is the entry I am about to write still mine?
		if tokens[key] ~= token then
			cleanup()
			return
		end
		cleanups[key] = cleanup
	end

	local function clear()
		-- Every generation is void before any teardown runs, so a factory
		-- yielding through a `clear` cannot store a survivor afterwards.
		table.clear(tokens)
		for key, cleanup in cleanups do
			-- The entry is dropped BEFORE its cleanup runs: a cleanup that
			-- calls back into `remove` for its own key would otherwise still
			-- find it and run a second time.
			cleanups[key] = nil
			cleanup()
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
