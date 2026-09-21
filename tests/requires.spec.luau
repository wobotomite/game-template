--!strict
-- Every `require` in src/ must point at a module that exists.
-- Run with:
--   lune run tests/requires.spec.luau
--
-- WHY THIS EXISTS. A Rojo require is a chain of table indexes against a tree
-- that does not exist until the game is running, so nothing in the toolchain
-- objects to a path that is simply wrong. stylua does not care. luau-lsp says
-- `Unknown require`, one line among hundreds of type diagnostics, and it says
-- the same thing about requires that are perfectly fine but unresolvable from
-- a static sourcemap. And a module nobody has required YET is a module nobody
-- has discovered is broken.
--
-- This template shipped five such modules at once. Four different flavours of
-- the same mistake:
--
--   * a path from a codebase this was extracted from
--     (`ReplicatedStorage.Client.ui.traits.clickable` — no such folder)
--   * a module renamed on one side only
--     (`Server.network`, when the file is `server-network.luau`)
--   * a package that was never added to pesde.toml
--     (`Packages.ripple`, required by two UI hooks)
--   * a package required under the wrong name
--     (`Packages.promise`; it publishes as `typed-promise`)
--
-- Each one threw at the first line of the module, so the failure landed on
-- whoever first reached for it rather than on whoever shipped it. All four
-- classes are caught here, in about a second.
--
-- WHAT IT CANNOT SEE, said out loud so a clean run is not over-read: a require
-- built from a runtime value, and any tree relocated at boot (a multi-place
-- build that moves a client bundle out of ServerStorage will have requires
-- that no static check can resolve — list those in IGNORED_PREFIXES below and
-- keep the list short).

local fs = require "@lune/fs"
local serde = require "@lune/serde"

local h = require "./harness"

h.title "requires resolve:"

-- Roblox paths that genuinely cannot be resolved statically. Anything added
-- here needs a comment saying why, or it is just a silenced bug.
local IGNORED_PREFIXES: { string } = {}

-- ===================== the Rojo tree -> filesystem map ====================

-- Read from default.project.json rather than hardcoded, so this keeps working
-- when a project grows places, folders, or a second source root.
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

-- Longest first, so `ReplicatedStorage.Shared` wins over `ReplicatedStorage`.
table.sort(mounts, function(a, b)
	return #a.roblox > #b.roblox
end)

h.saw("mount points in default.project.json", #mounts, 3)

-- The top-level names in the tree -- ReplicatedStorage, ServerScriptService,
-- and so on. Used to tell a service path apart from a local variable.
local service_roots: { [string]: boolean } = {}
for _, mount in mounts do
	service_roots[(mount.roblox:match "^[^.]+") :: string] = true
end

-- ============================== resolution ================================

local function exists(base: string): string?
	-- A MOUNT MAY POINT AT A FILE. `"$path": "src/shared/settings.luau"` mounts
	-- that one module under a name of the project's choosing -- which is how
	-- the shared data files reach ReplicatedFirst -- so `base` can already be
	-- the file, and the candidates below would ask for `settings.luau.luau`.
	if fs.isFile(base) then
		return base
	end
	for _, candidate in { `{base}.luau`, `{base}/init.luau`, `{base}.lua`, `{base}/init.lua` } do
		if fs.isFile(candidate) then
			return candidate
		end
	end
	-- A bare directory is a Folder in the tree: a legitimate require target
	-- only if it has an init, which the loop above already checked. But it IS
	-- a legitimate intermediate, so report it as present.
	if fs.isDir(base) then
		return base
	end
	return nil
end

-- `a.b["c-d"]` -> { "a", "b", "c-d" }. Returns nil if the expression contains
-- anything that is not a plain index (a call, a variable subscript), because
-- guessing at those is how a scanner starts lying.
local function segments(expr: string): { string }?
	local out: { string } = {}
	local i = 1
	local head = expr:match "^%s*([%a_][%w_]*)"
	if not head then
		return nil
	end
	table.insert(out, head)
	i = (expr:find(head, 1, true) :: number) + #head
	while i <= #expr do
		local c = expr:sub(i, i)
		if c:match "%s" then
			i += 1
		elseif c == "." then
			local name, after = expr:match("^%.([%a_][%w_]*)()", i)
			if not name then
				return nil
			end
			table.insert(out, name)
			i = after
		elseif c == "[" then
			local name, after = expr:match('^%["([^"]+)"%]()', i)
			if not name then
				name, after = expr:match("^%['([^']+)'%]()", i)
			end
			if not name or name == "" then
				return nil
			end
			table.insert(out, name)
			i = after
		else
			return nil
		end
	end
	return out
end

-- Where does this file's `script` live, as a filesystem path? For `init.luau`
-- that is its own directory; for anything else it is the file's stem.
-- Rojo turns `init.luau`, `init.server.luau` and `init.client.luau` into the
-- PARENT FOLDER, so inside one of those `script` is the directory. Handling
-- only the plain `init.luau` form reports every `require(script.x)` in a
-- `.server.luau` entry point as broken, which is a false positive precisely in
-- the boot scripts.
local function script_base(file: string): string
	if file:match "/init%.[%a]*%.?luau$" then
		return (file:gsub("/init%.[%a]*%.?luau$", ""))
	end
	return (file:gsub("%.luau$", ""))
end

-- Four outcomes, not two, because "could not check it" is the answer that
-- hides bugs and it deserves to be split:
--   ok        resolved to a real module
--   missing   resolved to a path with nothing at it -- a bug
--   unmounted a STATIC path under no mount in default.project.json. Also a
--             bug, and the exact shape of a require copied in from another
--             codebase. Silently skipping these is what let five dead modules
--             ship at once.
--   computed  not a static path at all (`require(child)` in a loader). The
--             only honestly uncheckable kind; counted so a jump is visible.
type Outcome = "ok" | "missing" | "unmounted" | "computed" | "ignored"

local function resolve(file: string, expr: string): (Outcome, string)
	-- Normalise `game:GetService("X")` / `game:GetService "X"` to a bare name,
	-- so both the header-alias style and the inline style are checked. Missing
	-- this is how a scanner goes blind on exactly one file and reports clean.
	expr = expr:gsub("game:GetService%s*%(%s*[\"']([%w_]+)[\"']%s*%)", "%1")
	expr = expr:gsub("game:GetService%s*[\"']([%w_]+)[\"']", "%1")
	expr = expr:gsub("^%s*(.-)%s*$", "%1")

	for _, ignored in IGNORED_PREFIXES do
		if expr:sub(1, #ignored) == ignored then
			return "ignored", expr
		end
	end

	local segs = segments(expr)
	if not segs then
		return "computed", expr
	end

	-- A path whose ROOT is not a service alias or `script` is a local variable
	-- holding an Instance -- `require(child)` inside a loader that walks a
	-- folder. It parses as a perfectly good one-segment path, which is how it
	-- got mistaken for a broken require pointing at nothing.
	if segs[1] ~= "script" and not service_roots[segs[1]] then
		return "computed", expr
	end

	-- script-relative
	if segs[1] == "script" then
		local base = script_base(file)
		local i = 2
		while segs[i] == "Parent" do
			base = base:gsub("/[^/]*$", "")
			i += 1
		end
		for j = i, #segs do
			base = `{base}/{segs[j]}`
		end
		local found = exists(base)
		return (if found then "ok" else "missing"), base
	end

	local joined = table.concat(segs, ".")
	for _, mount in mounts do
		if joined == mount.roblox or joined:sub(1, #mount.roblox + 1) == mount.roblox .. "." then
			local base = mount.path
			local rest = joined:sub(#mount.roblox + 2)
			if rest ~= "" then
				for seg in rest:gmatch "[^.]+" do
					base = `{base}/{seg}`
				end
			end
			local found = exists(base)
			return (if found then "ok" else "missing"), base
		end
	end

	-- A static path under no mount. Not "unknown" -- there is nothing in the
	-- built tree at that path, so this is a broken require that happens to be
	-- broken one level higher up than a missing file.
	return "unmounted", expr
end

-- ================================= scan ===================================

local checked = 0
local computed = 0
local ignored = 0
local broken: { string } = {}

for _, entry in h.sources "src" do
	-- Comments stripped, STRINGS KEPT. Both halves are deliberate: a
	-- `require(Shared.thing)` quoted inside a comment explaining this very rule
	-- is prose and must not be scanned, but the bracket form of a require --
	-- `tables["extend-object"]` -- carries the module name INSIDE a string. The
	-- default string-blanking turns that into `tables[""]`, which resolves to
	-- the directory and reports OK: a check that ran, counted itself, and
	-- verified nothing. Every hyphenated module in the tree is written that way,
	-- so that is most of them.
	local stripped = h.strip(entry.source, true)
	for _, expr in h.requires(stripped) do
		-- Relative Lune-style requires belong to tests/, not src/.
		if expr:match '^%s*"' then
			continue
		end
		local outcome, target = resolve(entry.path, expr)
		if outcome == "computed" then
			computed += 1
		elseif outcome == "ignored" then
			ignored += 1
		else
			checked += 1
			if outcome == "missing" then
				table.insert(broken, `{entry.path}: require({expr}) -> no module at {target}`)
			elseif outcome == "unmounted" then
				table.insert(broken, `{entry.path}: require({expr}) -> nothing is mounted at that path`)
			end
		end
	end
end

-- The guard that makes the result mean something. If the matcher breaks, this
-- fails instead of the scan reporting a clean tree it never looked at.
-- The floor is set near the real count (155 as of writing), not at 1. A floor
-- of "at least one" would have passed the version of this spec that silently
-- checked 68 and faked the other 87. If you strip the template down far enough
-- to trip this, lower it deliberately -- do not lower it to make a run go green.
h.saw("resolvable requires", checked, 100)
print(`  note {computed} computed require(s) and {ignored} explicitly ignored -- neither is checkable`)

h.check(`every resolvable require points at a real module ({checked} checked)`, #broken == 0)
for _, line in broken do
	print(`       {line}`)
end

h.done()
