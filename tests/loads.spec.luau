--!nocheck
-- Every module in src/ must survive being required.
-- Run with:
--   lune run tests/loads.spec.luau
--
-- WHY THIS EXISTS. `tests/requires.spec` proves that every require POINTS at a
-- real file. That is a different question from whether the file runs. A module
-- can resolve perfectly and still throw the moment it is required:
--
--   * it indexes a record key that was renamed out from under it, at module
--     scope, where the read is fatal rather than merely nil
--   * it calls a function declared below it with `local function`, which is not
--     in scope above its own declaration and so reads as a nil global
--   * it reaches for a package API that does not exist under that name
--     (`vide.for_values`, in this very tree)
--
-- None of those are visible to stylua, and luau-lsp reports the last two among
-- hundreds of lines of type noise. All three are a hard error at require time,
-- which means the whole subtree that depends on the module dies with it -- far
-- from the edit that caused it.
--
-- WHAT COUNTS AS A PASS. A module that loads passes. A module that fails
-- because a third-party PACKAGE cannot run outside the engine is recorded as a
-- known limit, not a failure -- charm, vide and lyra all touch engine behaviour
-- at require time. Anything else failing is a real bug in this tree, and that
-- distinction is the whole point: "could not check it" and "it is broken" must
-- never be the same result.
--
-- A NOTE ON STDERR AFTER THIS SPEC FINISHES. Requiring a module runs it, and a
-- module that starts a thread at require time keeps running after the last
-- assertion. Those threads meet stubbed services and sometimes throw --
-- `attempt to compare table <= number` from a stubbed value reaching arithmetic
-- in a spawned loop. That is a stub limit, not a finding about the module: the
-- question this spec asks is whether the module survives being REQUIRED, and it
-- did. The harness exits on its own verdict so a late throw cannot overrule it.
--
-- Specs that need one of those packages inject a stand-in instead:
--
--   env.load("ReplicatedStorage.Shared.player-data", { packages = { charm = fake } })

local h = require "./harness"
local env = require "./roblox-env"

h.title "modules load:"

-- Modules that CANNOT be required outside the engine for a reason that is not
-- about their own code. Each needs a note, or it is a silenced failure.
local EXPECTED_ENGINE_FAILURES: { [string]: string } = {}

local loaded, blocked = 0, 0
local blocked_by: { [string]: number } = {}
local broken: { string } = {}
local stub_limited: { string } = {}

-- Rojo turns a `.server.luau` / `.client.luau` file into a Script that RUNS at
-- boot rather than a module, so requiring one executes a whole subsystem
-- against stubs. That is a different (and much less useful) test than this one.
local function is_module(path: string): boolean
	return not path:match "%.server%.luau$" and not path:match "%.client%.luau$"
end

-- src path -> the dotted Roblox path Rojo mounts it at.
local function roblox_path_of(file: string): string?
	for _, mount in env.mounts do
		if file:sub(1, #mount.path + 1) == mount.path .. "/" then
			local rest = file:sub(#mount.path + 2)
			-- A mount's own `init.luau` IS the mount: `src/effects/init.luau`
			-- is `ReplicatedStorage.Effects`, not `.Effects.init`. The
			-- `/init.luau` form has no leading slash to strip in that case, so
			-- it has to be handled separately or the whole subtree resolves one
			-- level too deep and reports as missing.
			if rest == "init.luau" then
				rest = ""
			else
				rest = rest:gsub("/init%.luau$", ""):gsub("%.luau$", "")
			end
			local dotted = mount.roblox
			for seg in rest:gmatch "[^/]+" do
				dotted = `{dotted}.{seg}`
			end
			return dotted
		end
	end
	return nil
end

local seen: { [string]: boolean } = {}
local paths: { string } = {}
for _, file in h.walk "src" do
	if not is_module(file) then
		continue
	end
	local dotted = roblox_path_of(file)
	if dotted and not seen[dotted] then
		seen[dotted] = true
		table.insert(paths, dotted)
	end
end
table.sort(paths)

h.saw("modules under src/", #paths, 50)

for _, path in paths do
	-- A fresh cache per module, so one module's successful load cannot mask
	-- another's failure by having already pulled its dependency in.
	env.clear_cache()
	-- Both realms. A module is allowed to be one-realm-only and say so
	-- (`assert(RunService:IsClient(), "CAN ONLY BE RUN ON THE CLIENT!")`), and
	-- half of them export a different table per realm. Loading in one realm
	-- only would report every client-only module as broken.
	local ok, err = env.try(path, { realm = "server" })
	if not ok then
		env.clear_cache()
		ok, err = env.try(path, { realm = "client" })
	end
	if ok then
		loaded += 1
	else
		local message = tostring(err)
		local package_name = message:match 'roblox%-env: package "([^"]+)"'
		if package_name then
			blocked += 1
			blocked_by[package_name] = (blocked_by[package_name] or 0) + 1
		elseif message:find("expected userdata of type", 1, true) then
			-- The stub boundary, stated by Lune itself: something tried to
			-- parent a real Instance into a stubbed service, or hand one to an
			-- engine call. Unambiguously this loader's limit rather than the
			-- module's code, so it is recorded rather than failed -- but it is
			-- recorded BY NAME, because a stub limit that starts spreading is
			-- worth seeing.
			blocked += 1
			blocked_by["<stubbed service>"] = (blocked_by["<stubbed service>"] or 0) + 1
			table.insert(stub_limited, path)
		elseif EXPECTED_ENGINE_FAILURES[path] then
			blocked += 1
		else
			table.insert(broken, `{path}\n         {message}`)
		end
	end
end

local names: { string } = {}
for name, count in blocked_by do
	table.insert(names, `{name} x{count}`)
end
table.sort(names)
print(`  note {loaded} loaded, {blocked} blocked by a package that needs the engine: {table.concat(names, ", ")}`)

-- The guard. Without it, a loader that broke outright would block every module
-- and report zero failures, which reads exactly like a clean tree.
for _, path in stub_limited do
	print(`       (stub limit) {path}`)
end

h.saw("modules that actually loaded", loaded, 40)

h.check(`no module throws at require time ({loaded} loaded)`, #broken == 0)
for _, line in broken do
	print(`       {line}`)
end

h.done()
