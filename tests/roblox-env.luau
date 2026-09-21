--!nocheck
-- Load a real `src/` module inside a spec, under a stubbed Roblox environment.
--
--   local env = require "./roblox-env"
--   local timings = env.load("ReplicatedStorage.Shared.records.timings")
--   local validate = env.load("ServerScriptService.Server.net.validate", { realm = "server" })
--
-- WHY THIS EXISTS. Lune cannot require a Roblox module: there is no DataModel,
-- `game:GetService` does not exist, and the Rojo tree the requires index into
-- is a build artifact. So the specs in the game this template came from reached
-- for the only thing left — pulling a function out of the source file with a
-- regex and `luau.load`-ing the text:
--
--     local body = source:match("\nfunction hold_clearance%f[%W].-\nend\n")
--     local chunk = ("local Vector3 = ...\n%s\nreturn hold_clearance"):format(body)
--
-- That works, and it is miserable. The extraction breaks when the function
-- moves, gains a helper, or is renamed; every constant it reads has to be
-- re-parsed out of the file by hand and kept in sync; and when the regex stops
-- matching, the spec does not fail — it asserts, at the top, that the match
-- succeeded, and if you forget that assert the spec tests nothing and passes.
--
-- Loading the module for real removes all of it.
--
-- ## What gets rewritten, and why
--
-- Roblox's Luau is not upstream Luau. Three constructs in this codebase are
-- accepted by Roblox and luau-lsp and rejected by Lune:
--
--   `const x = ...`     a Roblox binding form; rewritten to `local`, but ONLY
--                       at statement position -- `local const = require(...)`
--                       is a variable legitimately NAMED const, and rewriting
--                       that produces `local local`.
--   `f<<T>>(...)`       explicit type arguments at a call site. Types are
--                       erased at runtime, so the whole `<<...>>` is dropped.
--   `@native`           a codegen attribute with no runtime meaning here.
--
-- Nothing else is touched. A rewrite that changed BEHAVIOUR would make every
-- spec built on this a test of the rewriter rather than of the code.
--
-- ## What the stubs do and do not give you
--
-- Services that Rojo mounts (ReplicatedStorage.Shared, .Util, and so on)
-- resolve to real modules on disk. Everything else -- RunService, Players,
-- SoundService -- is a permissive stub: indexing it returns another stub,
-- calling it returns a stub, and `:Connect()` hands back something with
-- `:Disconnect()`. That is enough for the require-time side effects most
-- modules have (connecting to a step signal, creating a Folder) to run
-- harmlessly.
--
-- It is NOT a Roblox emulator. A module that depends on real engine behaviour
-- at require time will not load, and that is the honest answer rather than a
-- silently wrong one. Use `env.try` when you want to ask whether it loads
-- rather than assert that it does.

local fs = require "@lune/fs"
local luau = require "@lune/luau"
local roblox = require "@lune/roblox"
local serde = require "@lune/serde"
local lune_task = require "@lune/task"

local env = {}

-- ============================ the Rojo mounts =============================

local project = serde.decode("json", fs.readFile "default.project.json")
local mounts: { { roblox: string, path: string } } = {}

local function collect(node: any, prefix: string)
	if typeof(node) ~= "table" then
		return
	end
	if typeof(node["$path"]) == "string" then
		table.insert(mounts, { roblox = prefix, path = node["$path"] })
	end
	for key, child in node do
		if typeof(key) == "string" and key:sub(1, 1) ~= "$" then
			collect(child, if prefix == "" then key else `{prefix}.{key}`)
		end
	end
end

collect(project.tree, "")
table.sort(mounts, function(a, b)
	return #a.roblox > #b.roblox
end)

env.mounts = mounts

-- Instance paths are resolved as SEGMENT LISTS, never as a dotted string.
-- pesde's package links index folders whose names contain dots -- `.pesde`,
-- `010devx101_lyra@0.6.3` -- so joining with "." and splitting again silently
-- shreds exactly the paths that reach a dependency.
local mount_segments: { { segs: { string }, path: string } } = {}
for _, mount in mounts do
	local segs = {}
	for seg in mount.roblox:gmatch "[^.]+" do
		table.insert(segs, seg)
	end
	table.insert(mount_segments, { segs = segs, path = mount.path })
end
table.sort(mount_segments, function(a, b)
	return #a.segs > #b.segs
end)

local function module_at(base: string): string?
	-- A MOUNT MAY POINT AT A FILE, not only at a directory: `"$path":
	-- "src/shared/settings.luau"` mounts that one module under a name of the
	-- project's choosing. `base` is then already the file, and appending
	-- `.luau` to it asks for `settings.luau.luau`. Without this the aliases
	-- that put the shared data files into ReplicatedFirst resolve to nothing,
	-- and the loading cover that requires them looks broken.
	if fs.isFile(base) then
		return base
	end
	for _, candidate in { `{base}.luau`, `{base}/init.luau` } do
		if fs.isFile(candidate) then
			return candidate
		end
	end
	-- A dependency's root is a Rojo project of its own, and most of them point
	-- somewhere other than an `init.luau` beside the manifest (`"$path": "src"`
	-- is the wally convention). Without this, every require of a package
	-- resolves to nothing and the module that wanted it looks broken.
	local manifest = `{base}/default.project.json`
	if fs.isFile(manifest) then
		local ok, decoded = pcall(serde.decode, "json", fs.readFile(manifest))
		if ok and typeof(decoded) == "table" then
			local inner = (decoded :: any).tree
			if typeof(inner) == "table" and typeof(inner["$path"]) == "string" then
				local target = `{base}/{inner["$path"]}`
				for _, candidate in { `{target}.luau`, `{target}/init.luau` } do
					if fs.isFile(candidate) then
						return candidate
					end
				end
			end
		end
	end
	return nil
end

-- Does anything at all exist at this path -- a module, or a folder a package
-- link walks THROUGH on its way to one?
function env.exists_at_segments(segs: { string }): boolean
	for _, mount in mount_segments do
		if #segs < #mount.segs then
			continue
		end
		local matches = true
		for i, want in mount.segs do
			if segs[i] ~= want then
				matches = false
				break
			end
		end
		if matches then
			local base = mount.path
			for i = #mount.segs + 1, #segs do
				base = `{base}/{segs[i]}`
			end
			return fs.isDir(base) or module_at(base) ~= nil
		end
	end
	return false
end

function env.file_for_segments(segs: { string }): string?
	for _, mount in mount_segments do
		if #segs < #mount.segs then
			continue
		end
		local matches = true
		for i, want in mount.segs do
			if segs[i] ~= want then
				matches = false
				break
			end
		end
		if matches then
			local base = mount.path
			for i = #mount.segs + 1, #segs do
				base = `{base}/{segs[i]}`
			end
			return module_at(base)
		end
	end
	return nil
end

-- Convenience for a path written by hand in a spec. A dotted string cannot
-- name a package-internal folder, which is fine: nothing writes one by hand.
function env.segments_of(path: string): { string }
	local segs = {}
	for seg in path:gmatch "[^.]+" do
		table.insert(segs, seg)
	end
	return segs
end

function env.file_for(path: string): string?
	return env.file_for_segments(env.segments_of(path))
end

-- ============================== the rewrite ===============================

function env.rewrite(source: string): string
	local out = {}
	for line in (source .. "\n"):gmatch "(.-)\n" do
		-- Statement position only. `local const = require(...)` in
		-- records/currencies is a variable named `const`, and a blanket
		-- substitution turns it into `local local`.
		line = line:gsub("^(%s*)const%f[%s]", "%1local")
		table.insert(out, line)
	end
	source = table.concat(out, "\n")
	-- Explicit type arguments at a call site: erased at runtime anyway.
	source = source:gsub("<<.->>", "")
	source = source:gsub("@native%s*", "")
	return source
end

-- =============================== the stubs ================================

local function stub(name: string): any
	local self
	self = setmetatable({}, {
		__index = function(_, key)
			if key == "Connect" or key == "ConnectParallel" or key == "Once" then
				return function()
					return { Disconnect = function() end, Connected = false }
				end
			elseif key == "Wait" then
				return function()
					return nil
				end
			elseif key == "IsA" then
				return function()
					return false
				end
			end
			return stub(`{name}.{tostring(key)}`)
		end,
		__newindex = function() end,
		__call = function(_, ...)
			return stub(`{name}()`)
		end,
		-- Yields nothing. Without this, `for _, player in Players:GetPlayers()`
		-- sees a CALLABLE value and treats the stub itself as the iterator
		-- function: it returns a stub (never nil), so the loop runs forever-ish
		-- with a nil second value, and the body fails on `player.CharacterAdded`
		-- -- a nil-index error that looks like a bug in the module under test.
		-- `__iter` takes precedence over the callable path, so an empty
		-- collection is what a stubbed service actually reports.
		__iter = function()
			return function()
				return nil
			end
		end,
		__tostring = function()
			return `<stub {name}>`
		end,
	})
	return self
end

env.stub = stub

-- ========================== engine globals ================================

-- Roblox globals that are not datatypes and that Lune does not provide. These
-- are REAL implementations, not stubs, because module code runs against them:
-- a `task.spawn` that does nothing would silently skip half of a module's
-- require-time setup and the spec would be testing a different program.
local task_global = {
	spawn = function(fn: any, ...)
		if typeof(fn) == "function" then
			return lune_task.spawn(fn, ...)
		end
		return nil
	end,
	defer = function(fn: any, ...)
		if typeof(fn) == "function" then
			return lune_task.defer(fn, ...)
		end
		return nil
	end,
	delay = function(seconds: number, fn: any, ...)
		if typeof(fn) == "function" then
			return lune_task.delay(seconds, fn, ...)
		end
		return nil
	end,
	wait = function(seconds: number?)
		return lune_task.wait(seconds)
	end,
	cancel = function(thread: any)
		pcall(lune_task.cancel, thread)
	end,
	desynchronize = function() end,
	synchronize = function() end,
}

-- Roblox's Random, on a seeded LCG.
--
-- THE SEED IS REAL. The first version of this took a seed, stored it in a field
-- nothing read, and answered from the global `math.random` -- so `Random.new(42)`
-- looked deterministic, was not, and would have produced a spec that passes
-- until the day it does not. A fake RNG that ignores its seed is worse than no
-- fake at all, because the whole reason to reach for one is repeatability.
local Random = {}
Random.__index = Random

local function next_state(state: number): number
	-- Numerical Recipes LCG. Not good randomness; perfectly good repeatability,
	-- which is the only property a spec wants from this.
	return (state * 1103515245 + 12345) % 2147483648
end

function Random.new(seed: number?)
	return setmetatable({ state = next_state((seed or 0) % 2147483648) }, Random)
end

function Random:NextNumber(min: number?, max: number?): number
	self.state = next_state(self.state)
	local value = self.state / 2147483648
	if min and max then
		return min + value * (max - min)
	end
	return value
end

-- NextInteger takes the HIGH bits, never `state % n`. A linear congruential
-- generator's LOW bits have a period as short as 2 or 4, so `% 4` on the raw
-- state can cycle through two of the four values and never emit the others.
-- Found by weighted-random.spec: two of four equally-weighted entries got zero
-- samples out of sixty thousand, which read as a broken alias table and was a
-- broken random number generator.
function Random:NextInteger(min: number, max: number): number
	self.state = next_state(self.state)
	return min + math.floor(self.state / 2147483648 * (max - min + 1))
end

function Random:NextUnitVector()
	local x, y, z = math.random() - 0.5, math.random() - 0.5, math.random() - 0.5
	local v = roblox.Vector3.new(x, y, z)
	return if v.Magnitude > 0 then v.Unit else roblox.Vector3.new(0, 1, 0)
end

function Random:Clone()
	return Random.new()
end

-- ============================== the loader ================================

export type Options = {
	-- Decides `RunService:IsServer()` / `:IsClient()`. Modules branch on this
	-- at require time and export different tables per realm, so a spec that
	-- does not say which realm it wants is asking an ambiguous question.
	realm: ("server" | "client")?,
	-- Extra globals merged into the chunk environment.
	globals: { [string]: any }?,
	-- What `RunService:IsStudio()` answers. Defaults to true; see the note
	-- beside it below.
	studio: boolean?,
	-- Stand-ins for third-party packages, keyed by the name under
	-- ReplicatedStorage.Packages: `{ charm = fake_charm }`.
	--
	-- Real packages ARE loaded when they can be -- pesde's link files, wally's
	-- `"$path": "src"` manifests and Lune's `@self` requires are all followed.
	-- But a package that reaches for engine behaviour at require time will not
	-- load, and when that happens this throws NAMING THE PACKAGE rather than
	-- handing back a stub. A silent stand-in for `charm.atom` would let a spec
	-- run green against a program that never existed, which is worse than not
	-- running at all.
	packages: { [string]: any }?,
}

local cache: { [string]: any } = {}

-- Services that modules PARENT INTO or build instances under. Lune can create
-- a real DataModel, and a real service is worth much more than a stub for
-- these: `container.Parent = SoundService` fails against a plain table with
-- "error converting Lua table to userdata", which reads as a bug in the module
-- rather than as a missing stub.
--
-- Everything else stays stubbed, because what those services offer is
-- BEHAVIOUR rather than a place to put things -- RunService's realm queries,
-- Players' lifecycle signals -- and Lune's copies have the class without the
-- engine behind it.
--
-- Workspace is deliberately NOT on this list even though things are parented
-- into it. A real service is STRICTER than a stub: an unknown member throws
-- instead of yielding another stub, and Lune's Workspace has no `BulkMoveTo`,
-- so making it real broke a module that a stub had handled fine. Real services
-- earn their place only where the alternative is a parenting failure.
local REAL_SERVICES: { [string]: boolean } = {
	SoundService = true,
	Lighting = true,
	ReplicatedFirst = true,
	ServerStorage = true,
	StarterGui = true,
	StarterPlayer = true,
	Teams = true,
}

local data_model: any = nil
local function real_service(name: string): any?
	if not REAL_SERVICES[name] then
		return nil
	end
	if not data_model then
		local ok, dm = pcall(roblox.Instance.new, "DataModel")
		if not ok then
			return nil
		end
		data_model = dm
	end
	local ok, service = pcall(function()
		return data_model:GetService(name)
	end)
	return if ok then service else nil
end

local function make_service(realm: string, name: string, opts: any): any
	local real = real_service(name)
	if real then
		return real
	end
	if name == "RunService" then
		return setmetatable({
			IsServer = function()
				return realm == "server"
			end,
			IsClient = function()
				return realm == "client"
			end,
			-- TRUE, because it is. A spec run is not a live server, and a
			-- module is entitled to assert on production-only configuration
			-- (`assert(place_ids.run ~= 0)` guards a place id that is 0 until
			-- the game is published). Answering `false` makes every such module
			-- fail to load for a reason that has nothing to do with its code.
			-- Override with `{ globals = ... }` if a spec wants the other
			-- branch.
			IsStudio = function()
				return opts.studio ~= false
			end,
			IsRunning = function()
				return true
			end,
		}, {
			__index = function(_, key)
				return stub(`RunService.{tostring(key)}`)
			end,
		})
	end
	return stub(name)
end

-- Loads the module at a dotted Roblox path. Throws naming the path if there is
-- no such module, so a typo in a spec fails as a typo rather than as a nil
-- index three lines later.
function env.load(path: string, options: Options?): any
	return env.load_segments(env.segments_of(path), options)
end

function env.load_segments(segs: { string }, options: Options?): any
	local opts = options or {}
	local realm = opts.realm or "server"
	local path = table.concat(segs, ".")
	local key = `{realm}:{path}`
	if cache[key] ~= nil then
		return cache[key]
	end

	local file = env.file_for_segments(segs)
	if not file then
		error(`roblox-env: no module at "{path}" (checked every mount in default.project.json)`, 2)
	end
	local result = env.load_file(file, opts, segs)
	cache[key] = result
	return result
end

-- Loads one FILE. `segs` is what `script` should report for it, when the
-- caller knows; a string require inside a package does not, and nothing in a
-- package indexes the Roblox tree from below its own link file.
function env.load_file(file: string, options: Options?, segs: { string }?): any
	local opts = options or {}
	local realm = opts.realm or "server"
	local key = `file:{realm}:{file}`
	if cache[key] ~= nil then
		return cache[key]
	end
	-- Set before the chunk runs, so a require cycle resolves to a partial
	-- result instead of recursing forever -- the same thing Roblox does.
	cache[key] = false
	local self_segs = segs or { file }

	local services: { [string]: any } = {}
	local mounted_roots: { [string]: boolean } = {}
	for _, mount in mount_segments do
		mounted_roots[mount.segs[1]] = true
	end

	-- A proxy for one node in the tree, carrying its path as a SEGMENT LIST.
	-- FindFirstChild and WaitForChild are the same operation as indexing here;
	-- pesde's package link files use FindFirstChild for every hop.
	local function node(at: { string }): any
		return setmetatable({}, {
			__index = function(_, child)
				if child == "__segs" then
					return at
				elseif child == "FindFirstChild" or child == "WaitForChild" then
					-- Returns nil when nothing is there, which is the whole
					-- point of the call. Handing back a node unconditionally
					-- made `ReplicatedStorage:FindFirstChild "PlaceTag"` look
					-- like a hit for a value that does not exist, and the
					-- caller then failed on `tag:IsA(...)` -- an error about
					-- this loader, reported against the module under test.
					--
					-- Package link files walk real folders, so those still
					-- resolve.
					return function(_, name: string)
						local next_at = table.clone(at)
						table.insert(next_at, name)
						return if env.exists_at_segments(next_at) then node(next_at) else nil
					end
				elseif child == "Parent" then
					local up = table.clone(at)
					table.remove(up)
					return node(up)
				elseif child == "Name" then
					return at[#at] or ""
				end
				local next_at = table.clone(at)
				table.insert(next_at, tostring(child))
				return node(next_at)
			end,
			__tostring = function()
				return table.concat(at, ".")
			end,
		})
	end

	local injected = opts.packages or {}

	local function get_service(_, name: string)
		if mounted_roots[name] then
			if not services[name] then
				services[name] = node { name }
			end
			return services[name]
		end
		if not services[name] then
			services[name] = make_service(realm, name, opts)
		end
		return services[name]
	end

	local game_stub = setmetatable({}, {
		__index = function(_, key)
			if key == "GetService" then
				return get_service
			elseif key == "PlaceId" then
				return 0
			elseif key == "PrivateServerId" then
				return ""
			elseif key == "PrivateServerOwnerId" then
				return 0
			elseif key == "BindToClose" then
				return function() end
			elseif mounted_roots[key] then
				return get_service(nil, key)
			end
			return stub(`game.{tostring(key)}`)
		end,
	})

	local function chunk_require(target: any): any
		-- Package internals use Luau's own STRING requires (`require "./lib"`),
		-- resolved against the requiring FILE rather than against the Roblox
		-- tree. Both forms have to work: the link file at the top of a package
		-- is a Roblox path, and everything under it is relative.
		if typeof(target) == "string" then
			local dir = (file :: string):gsub("/[^/]*$", "")
			local rel = target
			-- `@self` is Lune's alias for the requiring file's own directory,
			-- which is how the vide/charm family reach their own src.
			if rel:sub(1, 6) == "@self/" then
				rel = `./{rel:sub(7)}`
			end
			while rel:sub(1, 3) == "../" do
				dir = dir:gsub("/[^/]*$", "")
				rel = rel:sub(4)
			end
			if rel:sub(1, 2) == "./" then
				rel = rel:sub(3)
			end
			local base = `{dir}/{rel}`
			local found = module_at(base)
			if not found then
				error(`roblox-env: no module at "{base}" (string require "{target}" from {file})`, 2)
			end
			return env.load_file(found, opts)
		end
		local wanted = (target :: any).__segs
		if typeof(wanted) ~= "table" then
			error(`roblox-env: require() of something that is not a module path: {tostring(target)}`, 2)
		end
		-- A spec-supplied stand-in wins over the real package, and is checked
		-- before any file work so injecting one also sidesteps a package that
		-- cannot load here at all.
		if #wanted == 3 and wanted[2] == "Packages" and injected[wanted[3]] ~= nil then
			return injected[wanted[3]]
		end
		local ok, loaded = pcall(env.load_segments, wanted, opts)
		if ok then
			return loaded
		end
		if #wanted >= 3 and wanted[2] == "Packages" then
			error(
				`roblox-env: package "{wanted[3]}" could not be loaded here ({tostring(loaded)}). `
					.. "Pass a stand-in via the `packages` option, keyed by that name.",
				2
			)
		end
		error(loaded, 2)
	end

	local globals: { [string]: any } = {
		game = game_stub,
		workspace = stub "workspace",
		-- Rojo turns `init.luau` into its PARENT FOLDER, so inside one of those
		-- `script` already is the folder and `script.Parent` pops one level
		-- less. `segs` is that folder's path either way, because file_for
		-- resolved it through `<base>/init.luau`.
		script = node(self_segs),
		require = chunk_require,
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		Vector2 = roblox.Vector2,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Rect = roblox.Rect,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		BrickColor = roblox.BrickColor,
		Font = roblox.Font,
		Region3 = roblox.Region3,
		Ray = roblox.Ray,
		Enum = roblox.Enum,
		Random = Random,
		task = task_global,
		typeof = typeof,
		tick = os.clock,
		time = os.clock,
		-- TweenInfo and RaycastParams have no Lune equivalent; a permissive
		-- stub is enough for the require-time constants that hold one.
		TweenInfo = {
			new = function(...)
				return stub "TweenInfo"
			end,
		},
		RaycastParams = {
			new = function()
				return stub "RaycastParams"
			end,
		},
		OverlapParams = {
			new = function()
				return stub "OverlapParams"
			end,
		},
		-- A module that warns at require time should still load, but it must
		-- not do so silently: a swallowed "misconfigured" warning is exactly
		-- what a spec is there to surface.
		warn = function(...)
			print("[warn]", ...)
		end,
	}
	for name, value in (opts.globals or {}) :: any do
		globals[name] = value
	end

	local source = env.rewrite(fs.readFile(file))
	local chunk = luau.load(luau.compile(source), {
		debugName = file,
		environment = globals,
		injectGlobals = true,
	})

	local result = chunk()
	cache[key] = result
	return result
end

-- The same, but answers "does this load?" instead of throwing. For a spec that
-- sweeps the whole tree and wants to report every failure rather than stop at
-- the first.
function env.try(path: string, options: Options?): (boolean, any)
	local ok, result = pcall(env.load, path, options)
	return ok, result
end

function env.clear_cache()
	table.clear(cache)
end

return env
