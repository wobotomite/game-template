const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const synced_time = require(ReplicatedStorage.Util.numbers["synced-time"])
const effect_types = require(script["effect-types"])

-- The effect registry. One named, self-cleaning visual moment per file in
-- list/, spawned by name:
--
--   effects.new("boss/ground-telegraph", nil, {
--       position = landing, radius = 9, duration = 1.2, color = GOO_GREEN,
--   })
--
--   const stream = effects.new("ghosts/capture-stream", nil, {
--       from = ghost_position, user_id = capturer_id, color = ghost_colour,
--   })
--   stream.cleanup() -- or let it end on its own
--
-- Passing a table of instances instead of `nil` binds the effect's LIFETIME to
-- them: destroy one and the effect cleans up. No entry needs that yet, so there
-- is deliberately no example of it here -- an example nothing runs is the first
-- thing to go stale, and this header already shipped one that did. See
-- README.md for the mechanism.
--
-- See README.md for how to write an entry. This file is the machinery.
--
-- ========================= WHAT THIS BUYS ==========================
--
-- Before this, a one-shot VFX was a function on a module that the caller had
-- to know the name and location of, and every effect hand-rolled its own
-- teardown. That works until an effect needs to outlive the call and stop when
-- something else does -- an aura that must die with its ghost, a beam that
-- must stop when the tool is dropped. Each one grew its own bookkeeping, and
-- the bookkeeping is where the leaks were.
--
-- So lifetime is the thing this owns. An effect gets a `cleanup` it can call,
-- the caller gets one it can call, and any instance the effect is BOUND to
-- ends it by being destroyed. Whichever happens first wins, the rest are
-- no-ops, and the effect's own teardown runs exactly once.
--
-- ===================== WHY THE FOLDER IS THE LIST ======================
--
-- `list/` is walked, not enumerated in a table here. An effect exists because
-- its file exists. The cost is that a file nobody spawns is invisible -- it
-- looks alive because it sits in the folder -- and a misspelled name is
-- invisible in the other direction. effect-types generates a union of the real
-- folder paths so Studio rejects a typo, but luau-lsp cannot evaluate type
-- functions, so that check does not run on the command line and a union that
-- degraded to `string` would look identical. tests/effects.spec.luau closes
-- both directions against the real folder: every `new()` name resolves, every
-- entry is reached, and the entry count is pinned exactly rather than bounded.

const MAX_RUN_TIME = 60
const DEBUG = RunService:IsStudio()

-- Built on first use rather than at require time. A `task.defer` here would
-- leave a window where `new()` is callable and the registry is still empty --
-- effects fired during the first frames of a room would silently find nothing.
local registry: { [string]: effect_types.Effect }? = nil

function build_registry(): { [string]: effect_types.Effect }
	const found: { [string]: effect_types.Effect } = {}

	local function walk(folder: Instance, prefix: string)
		for _, child in folder:GetChildren() do
			const path = if prefix == "" then child.Name else `{prefix}/{child.Name}`
			if child:IsA "ModuleScript" then
				const effect = require(child) :: any
				-- Loud here rather than at the call site: a module that
				-- returns a table is a mistake being made once, in this file,
				-- rather than a confusing failure every time it is spawned.
				assert(
					type(effect) == "function",
					`effect '{path}' must return a function, got {type(effect)} ({child:GetFullName()})`
				)
				found[path] = effect
			elseif child:IsA "Folder" then
				walk(child, path)
			end
		end
	end

	walk(script.list, "")
	return table.freeze(found)
end

-- `name` is checked against effect-types' generated union in Studio; the assert
-- is what catches it everywhere else, including a name built at runtime.
function new(
	name: effect_types.EffectName,
	instances: effect_types.Instances?,
	attributes: effect_types.Attributes?
): effect_types.Handle
	if not registry then
		registry = build_registry()
	end
	const effect = assert(
		(registry :: any)[name],
		`no effect named '{name}' -- expected a ModuleScript at Effects.list.{(name :: string):gsub("/", ".")}`
	)

	const connections: { RBXScriptConnection } = {}
	const teardowns: { effect_types.Cleanup } = {}
	const bound: { [string]: Instance } = {}
	const started = synced_time()

	local finished = false
	local long_run_allowed = false

	local function is_running(): boolean
		return not finished
	end

	local function cleanup()
		if finished then
			return
		end
		finished = true
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		-- Spawned, not called: teardowns come from effect authors, and one that
		-- errors must not strand the parts the next one was going to remove.
		for _, teardown in teardowns do
			task.spawn(teardown)
		end
		table.clear(teardowns)
	end

	local function bind(key: string, instance: Instance)
		assert(not bound[key], `'{key}' is already bound on effect '{name}'`)
		bound[key] = instance

		-- Already gone. Binding to it and waiting for AncestryChanged would
		-- wait forever, so the effect ends now rather than never.
		if not instance:IsDescendantOf(game) then
			task.spawn(cleanup)
			return
		end

		table.insert(
			connections,
			instance.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					cleanup()
				end
			end)
		)
	end

	if instances then
		for key, instance in instances do
			bind(key, instance)
		end
	end

	local function get<T>(key: string): T
		return (assert(bound[key], `effect '{name}' has no instance bound as '{key}'`) :: any) :: T
	end

	local function attr<T>(key: string): T
		-- The clock an effect should measure itself against. synced-time, not
		-- os.clock: effects are spawned from replicated events, and the two
		-- clocks cross silently -- a timing bug that shows up as an effect
		-- being subtly early or late rather than as an error.
		if key == "start_time" then
			return (started :: any) :: T
		end
		-- A TRAILING `?` MARKS THE ATTRIBUTE OPTIONAL, mirroring Luau's own
		-- optional-type syntax: `attr "user_id?"` may return nil, `attr
		-- "user_id"` may not.
		--
		-- Asserting by default is right -- a missing attribute should fail at
		-- the effect rather than arrive as a nil three frames later -- but
		-- without this escape hatch a genuinely optional value is IMPOSSIBLE
		-- to pass, even when every type in the chain says it is optional.
		-- ghosts/capture-stream's `user_id` is the case: ghost-service's
		-- `capture(id, capturer: Player?)` sends `capturer and
		-- capturer.UserId`, and vacuum_point accepts nil. Today's single
		-- caller always populates it, so this is defensive rather than a fix
		-- for an observed failure -- but an optional contract that cannot be
		-- honoured is a trap waiting for the second caller.
		const optional = key:sub(-1) == "?"
		const wanted = if optional then key:sub(1, -2) else key
		const value = attributes and attributes[wanted]
		if value == nil and not optional then
			error(`effect '{name}' was not given an attribute '{wanted}'`, 0)
		end
		return value
	end

	-- Spawned rather than called directly, for two reasons that both matter:
	-- an effect that errors must not take its caller down with it (a broken
	-- telegraph should not cancel the attack), and an effect that yields must
	-- not stall the frame that spawned it. task.spawn still runs the body
	-- immediately up to its first yield, so a telegraph is on screen this frame
	-- rather than the next -- which for a windup is the whole point.
	task.spawn(function()
		-- An effect that THROWS must still be torn down. Without this it stays
		-- `is_running` forever: no instances leak (it usually died before
		-- building any) but the entry never ends, and the only symptom is a
		-- long-run warning 60 seconds later pointing at an effect that is not
		-- actually running. That is a worse signal than the error itself,
		-- because it arrives a minute late and describes the wrong problem.
		--
		-- xpcall then re-raise, rather than pcall: cleanup is guaranteed AND
		-- the error still surfaces in red with its traceback, the way an
		-- unprotected error in a spawned thread does. Swallowing it into a
		-- warn would downgrade the one signal that says an effect is broken.
		-- table.pack around the whole call: xpcall returns `ok` followed by
		-- EVERY result, and an effect may return several teardowns.
		const returned = table.pack(xpcall(effect, debug.traceback, cleanup, get, attr))
		if not returned[1] then
			cleanup()
			error(returned[2], 0)
		end
		for index = 2, returned.n do
			const teardown = returned[index]
			if type(teardown) ~= "function" then
				continue
			end
			-- Cleanup can win the race: an effect that bound an
			-- already-destroyed instance, or whose caller cleaned up during a
			-- yield, has nowhere to put these. Run them now instead of
			-- appending to a list nothing will ever read.
			if finished then
				task.spawn(teardown)
			else
				table.insert(teardowns, teardown)
			end
		end
	end)

	if DEBUG then
		task.delay(MAX_RUN_TIME, function()
			if is_running() and not long_run_allowed then
				warn(
					`effect '{name}' has been running for over {MAX_RUN_TIME}s. `
						.. `If that is intended call allow_long_run(); otherwise it is leaking.`
				)
			end
		end)
	end

	return table.freeze {
		bind = bind,
		cleanup = cleanup,
		is_running = is_running,
		allow_long_run = function()
			long_run_allowed = true
		end,
	}
end

return table.freeze {
	new = new,
}
