--!nocheck
-- The project file and the tree agree.
-- Run with:
--   lune run tests/project.spec.luau
--
-- WHY THIS EXISTS. `default.project.json` is the only thing that decides what
-- ends up in the built game, and it is edited by hand, rarely, usually while
-- thinking about something else. Two failures live there and neither raises
-- anything:
--
--   * a mount pointing at a path that does not exist. Rojo BUILDS ANYWAY --
--     verified, not assumed: renaming a mount's directory away still produces
--     a place file, just without that branch. So the symptom is a subsystem
--     that is simply absent at runtime.
--   * a directory under src/ that no mount covers. Every file in it is dead:
--     it typechecks, it passes every source scan, and it is not in the game.
--     `tests/loads.spec` will not even see it, because it maps files THROUGH
--     the mounts.
--
-- Both are invisible to everything else in this suite, because everything else
-- starts from the mounts and asks about the files. This asks the other way.

local h = require "./harness"
local fs = require "@lune/fs"
local serde = require "@lune/serde"

h.title "project:"

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

h.saw("mounts in default.project.json", #mounts, 5)

local missing: { string } = {}
for _, mount in mounts do
	if not fs.isDir(mount.path) and not fs.isFile(mount.path) then
		table.insert(missing, `{mount.roblox} -> {mount.path}`)
	end
end
h.check(
	`every mount points at something that exists ({#mounts} mounts)`,
	#missing == 0,
	if #missing > 0 then table.concat(missing, ", ") else nil
)

-- The other direction.
local roots: { string } = {}
for _, mount in mounts do
	if mount.path:sub(1, 4) == "src/" or mount.path == "src" then
		table.insert(roots, (mount.path:gsub("/$", "")))
	end
end
h.saw("mounts under src/", #roots, 3)

local unreachable: { string } = {}
for _, path in h.walk "src" do
	local covered = false
	for _, root in roots do
		if path == root or path:sub(1, #root + 1) == root .. "/" then
			covered = true
			break
		end
	end
	if not covered then
		table.insert(unreachable, path)
	end
end
table.sort(unreachable)
h.check(
	"every file under src/ is inside a mount",
	#unreachable == 0,
	if #unreachable > 0 then table.concat(unreachable, ", ") else nil
)

h.done()
