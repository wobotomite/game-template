--!strict
-- Builds the service-test place and runs Jest Roblox in it.
--
--   lune run scripts/run-jest               build the place, then run the tests
--   lune run scripts/run-jest --build-only  build the place and stop
--
-- WHY A SECOND RUNNER EXISTS. `tests/run.luau` runs specs under Lune, which
-- has no engine: a module that touches Players, DataStoreService,
-- MarketplaceService or the wire cannot be loaded there at all, so the
-- server's actual services were the one part of this tree nothing tested. Jest
-- Roblox runs INSIDE Roblox, which is the only place those modules can run.
-- See docs/testing-services.md for how to write one and what it costs.
--
-- The two runners do not overlap and must not: `tests/run.luau` discovers
-- specs with `fs.readDir "tests"`, which is not recursive and matches
-- `*.spec.luau`, so the service tests one directory down under a `.test.luau`
-- name are invisible to it, and Jest is invisible to the Lune suite.

local fs = require "@lune/fs"
local process = require "@lune/process"
local serde = require "@lune/serde"

-- ========================= what this script owns =========================
--
-- These five names are the only facts about the test place that live here.
-- Everything else -- every mount, every source path -- is read out of
-- `default.project.json`, because the test place IS the game place plus a test
-- mount. A second hand-kept project file would be the tree written down twice,
-- and the copy would go stale the first time a mount moved.

-- Where the service tests live on disk, and the name they are mounted under.
-- The generated entry point below points Jest at exactly this instance.
local TESTS_DIR = "tests/services"
local TESTS_MOUNT = "Tests"

-- The existing mount that holds the pesde packages. Jest is a pesde DEV
-- dependency, and pesde links dev dependencies into the same `roblox_packages`
-- directory as the rest -- so a normal `pesde install` puts Jest inside this
-- mount and `pesde install --prod` takes it out again. That is what keeps the
-- published place free of it; nothing here has to filter the mount.
local PACKAGES_MOUNT = "Packages"

-- Output. Both are gitignored. The project file has to sit at the REPOSITORY
-- ROOT and nowhere else: Rojo resolves every `$path` relative to the directory
-- holding the project file, so a copy written into the build directory would
-- resolve `src/shared` to `build/jest/src/shared` and build an empty place
-- without complaining.
local PROJECT_FILE = "test.project.json"
local BUILD_DIR = "build/jest"

local PLACE_FILE = `{BUILD_DIR}/test-place.rbxl`
local ENTRY_FILE = `{BUILD_DIR}/run.lua`

-- NO BOOT SCRIPT MAY RUN IN THE TEST PLACE. Rojo turns a `.server.luau` into a
-- Script that runs the moment the place opens, so a test place built straight
-- from the game project boots the whole game around the test run -- and the
-- boot scripts are what stand the network up, which means
-- `sendbufs.create_server` and the three `_SB_*` remotes parented into
-- ReplicatedStorage. That is the one thing a service test must never cause (see
-- docs/network.md), and it would also make the assertion in
-- `tests/services/award.test.luau` that the remotes do not exist meaningless.
--
-- It takes TWO mechanisms, because Rojo reaches an `init.server.luau` by a
-- different route than the rest.
--
-- 1. The globs below drop every boot script that is an ordinary file in a
--    directory. Rojo consults `globIgnorePaths` while walking a directory's
--    children, so these never become instances at all.
local BOOT_SCRIPT_GLOBS = { "src/**/*.server.luau", "src/**/*.client.luau" }

-- 2. `init.server.luau` and `init.client.luau` are NOT reached by that walk.
--    Rojo probes for them directly when it snapshots a directory, and they make
--    the directory itself into the Script -- so the glob never sees them and
--    `ServerScriptService.Server` comes out as a Script rather than a Folder.
--    Measured, not assumed: with the globs alone the built place still carried
--    `ServerScriptService.Server` and `ReplicatedStorage.Client` as Scripts.
--
--    Ignoring them is not an option either, since the directory IS the mount.
--    So the mount keeps its instance and the instance is switched off, which is
--    what `Disabled` is for; its children are still reachable by name, which is
--    all the tests want from it.
local BOOT_INIT_FILES = { "init.server.luau", "init.client.luau" }

-- =============================== the build ===============================

if not fs.isFile "default.project.json" then
	print "run-jest: run this from the repository root (lune run scripts/run-jest)"
	process.exit(1)
end

local project = serde.decode("json", fs.readFile "default.project.json") :: any

local replicated = project.tree.ReplicatedStorage
assert(replicated ~= nil, "default.project.json has no ReplicatedStorage branch to mount the tests under")
assert(
	replicated[TESTS_MOUNT] == nil,
	`default.project.json already has a ReplicatedStorage.{TESTS_MOUNT} -- pick another name for the test mount`
)

local packages = replicated[PACKAGES_MOUNT]
assert(packages ~= nil, `default.project.json has no ReplicatedStorage.{PACKAGES_MOUNT} mount`)

-- Proof that the dev dependency is actually installed, BEFORE Rojo builds a
-- place that would simply be missing Jest. `pesde install --prod` leaves a
-- tree that looks complete and cannot run a test, and the failure without this
-- check is an index of nil inside the generated entry point, in Studio, with
-- no hint about which command to run.
local jest_link = `{packages["$path"]}/jest.luau`
if not fs.isFile(jest_link) then
	print(`run-jest: {jest_link} is missing -- run \`pesde install\` (a plain install, not --prod)`)
	process.exit(1)
end

if not fs.isDir(TESTS_DIR) then
	print(`run-jest: {TESTS_DIR} does not exist`)
	process.exit(1)
end

replicated[TESTS_MOUNT] = { ["$path"] = TESTS_DIR }
project.globIgnorePaths = BOOT_SCRIPT_GLOBS
project.name = `{project.name}-tests`

-- Which mounts need the `Disabled` treatment is READ OFF THE DISK rather than
-- listed here, so moving a boot script or adding one to a new mount needs no
-- edit in this file.
local function disable_boot_scripts(node: any)
	if type(node) ~= "table" then
		return
	end
	local mount = node["$path"]
	-- `isDir` first: a mount may be a single FILE (`src/shared/settings.luau`
	-- is one), and Lune's `fs.isFile` on a path UNDER a file does not answer
	-- false, it throws "Not a directory".
	if type(mount) == "string" and fs.isDir(mount) then
		for _, init in BOOT_INIT_FILES do
			if fs.isFile(`{mount}/{init}`) then
				local properties = node["$properties"] or {}
				properties.Disabled = true
				node["$properties"] = properties
				break
			end
		end
	end
	for key, child in node do
		if string.sub(key, 1, 1) ~= "$" then
			disable_boot_scripts(child)
		end
	end
end

disable_boot_scripts(project.tree)

fs.writeFile(PROJECT_FILE, serde.encode("json", project, true))
fs.writeDir(BUILD_DIR)

local built = process.exec("rojo", { "build", PROJECT_FILE, "-o", PLACE_FILE }, { stdio = "forward" })
if not built.ok then
	process.exit(built.code)
end

-- ============================ the entry point ============================
--
-- GENERATED rather than checked in, because every path in it -- where Jest
-- lives, which instance is the test root -- is a fact this file already owns
-- above. A checked-in copy would be the second home for both: the mount moves
-- and the entry keeps pointing at the old name.
--
-- An empty run is RED here and must stay so. With no test found, Jest 3.20.1
-- calls `exit(1)`, which in Roblox is `error("Exited with code: 1")`, so the
-- promise rejects and `passed` below is false. `passWithNoTests` is the one
-- option that would turn that green; it is deliberately not passed.
--
-- The shape is upstream's, both halves of it: the public example on
-- https://roblox.github.io/jest-roblox/ is the `awaitStatus` / `results.success`
-- pair, and the command-line variant beside it is the ProcessService exit.
--
-- The two `%s` are the packages mount and the tests mount, in that order.
local ENTRY_TEMPLATE = [[
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local runCLI = require(ReplicatedStorage.%s.jest).runCLI
local root = ReplicatedStorage.%s

-- ProcessService exists only under a command-line host (run-in-roblox,
-- roblox-cli). Inside Studio there is no exit code to set, so the failure has
-- to be raised instead -- see below.
local has_process_service, ProcessService = pcall(function()
	return game:GetService("ProcessService")
end)

-- `ci = true` so a missing snapshot is a failure rather than a snapshot
-- quietly written into a place nobody keeps.
local status, result = runCLI(root, { verbose = false, ci = true }, { root }):awaitStatus()

if status == "Rejected" then
	print(result)
end

-- `results.success` is the field upstream's own entry point reads.
local passed = status == "Resolved" and result.results.success == true

if has_process_service then
	ProcessService:ExitAsync(if passed then 0 else 1)
elseif not passed then
	-- Without this a red suite in Studio looks exactly like a green one: the
	-- run just ends and the reporter's output scrolls away.
	error("Tests failed")
end

return nil
]]

fs.writeFile(ENTRY_FILE, string.format(ENTRY_TEMPLATE, PACKAGES_MOUNT, TESTS_MOUNT))

if table.find(process.args, "--build-only") then
	print(`run-jest: built {PLACE_FILE}`)
	print(`run-jest: to run the tests -- run-in-roblox --place {PLACE_FILE} --script {ENTRY_FILE}`)
	return
end

-- run-in-roblox opens the place in the locally installed Roblox Studio, so
-- this is not a headless step and it takes over the Studio that is running.
-- `--build-only` above exists for every check that does not need the engine.
local ran = process.exec("run-in-roblox", { "--place", PLACE_FILE, "--script", ENTRY_FILE }, { stdio = "forward" })
process.exit(ran.code)
