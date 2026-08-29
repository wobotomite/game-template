--!nocheck
-- Every member read off a third-party package must actually exist on it.
-- Run with:
--   lune run tests/package-api.spec.luau
--
-- WHY THIS EXISTS. `util/ui/templates/carousel` called `vide.for_values`. There
-- is no such function in vide 0.4 — the iterator is `vide.values` — and nothing
-- in the toolchain said so:
--
--   * a table read is not a type error, it is `nil`;
--   * luau-lsp reports `Key 'for_values' not found in table 'vide'` among
--     hundreds of lines, in a file that also had four dead requires;
--   * `tests/requires.spec` proves the require RESOLVES, which it did;
--   * `tests/loads.spec` cannot load a module whose package needs the engine.
--
-- So it shipped, and it failed at the moment a carousel was first rendered —
-- which in that project was never, because the module had four other reasons
-- not to load. A module nobody has run is a module nobody has found the bug in.
--
-- This check is exact rather than textual: the package is REQUIRED through
-- `roblox-env` and its real export table is read. No parsing of the package's
-- source, no list to keep in sync with a version bump. A package that changes
-- its API in an update fails here on the next run.
--
-- WHAT IT CANNOT COVER: packages that cannot be required outside the engine
-- (charm-sync, lyra, sendbufs and friends all touch engine behaviour at require
-- time). Those are listed as skipped, by name, rather than quietly omitted --
-- see the testing notes on why "could not check it" must never render as a pass.

local h = require "./harness"
local env = require "./roblox-env"

h.title "package API:"

-- Packages whose export table can be read headlessly. Add to this as more
-- become loadable; nothing else needs changing.
local PACKAGES = { "vide", "charm" }

-- Members that are declared but deliberately absent from the runtime table.
-- `vide.strict` is typed as a boolean and initialised to nil, so it never shows
-- up as a key even though reading it is correct.
local ALLOWED: { [string]: { [string]: boolean } } = {
	vide = { strict = true },
}

local checked_packages = 0
local skipped: { string } = {}
local total_reads = 0
local type_refs = 0
local unknown: { string } = {}

for _, package_name in PACKAGES do
	local ok, module = pcall(env.load_segments, { "ReplicatedStorage", "Packages", package_name }, { realm = "client" })
	if not ok or type(module) ~= "table" then
		table.insert(skipped, package_name)
		continue
	end

	local exports: { [string]: boolean } = {}
	local export_count = 0
	for key in module :: any do
		exports[tostring(key)] = true
		export_count += 1
	end
	h.saw(`exports on '{package_name}'`, export_count, 5)
	checked_packages += 1

	local allowed = ALLOWED[package_name] or {}
	local reads = 0

	for _, entry in h.sources "src" do
		local stripped = h.strip(entry.source, true)
		-- Resolve the LOCAL alias rather than assuming it is called after the
		-- package. Matching a fixed name would silently check nothing in every
		-- file that renamed it, and report clean.
		local alias = stripped:match(`[%w_]+%s+([%w_]+)%s*=%s*require%(ReplicatedStorage%.Packages%.{package_name}%)`)
			or stripped:match(`[%w_]+%s+([%w_]+)%s*=%s*require%(ReplicatedStorage%.Packages%["{package_name}"%]%)`)
		if not alias then
			continue
		end
		-- Walked rather than gmatch'd, so each hit's NEIGHBOURS can be
		-- inspected. A package exports types as well as values, and an exported
		-- TYPE is not a key on the runtime table -- `charm.Getter<T>`,
		-- `vide.Source<number>` and `charm.Cleanup` are all correct code that a
		-- naive value-scan reports as missing members.
		--
		-- Two tells separate a type reference from a value read:
		--   followed by `<`   generic type arguments
		--   preceded by `:`   a type annotation or a return type
		--
		-- Neither has a value-position counterpart here (a method call
		-- `x:foo()` puts the colon before the METHOD, not before the alias).
		--
		-- They are not quite enough. `(fx: () -> ...charm.Cleanup?)` puts the
		-- colon four tokens back and has no `<`. The third tell is CASE: every
		-- value export in these packages is lowerCamel and every exported type
		-- is PascalCase, so a PascalCase name that is not a runtime key is
		-- overwhelmingly a type. Those are COUNTED AND PRINTED rather than
		-- silently dropped -- the cost of the heuristic is that a genuinely
		-- missing PascalCase VALUE would land in that bucket, and a number on
		-- screen is what makes that visible instead of invisible.
		local at = 1
		while true do
			local start, stop, member = stripped:find(alias .. "%.([%w_]+)", at)
			if not start then
				break
			end
			at = stop + 1

			local before = stripped:sub(1, start - 1):match "([^%s])%s*$"
			local after = stripped:sub(stop + 1, stop + 1)
			if after == "<" or before == ":" then
				type_refs += 1
				continue
			end
			if not exports[member] and member:match "^%u" then
				type_refs += 1
				continue
			end

			reads += 1
			if not exports[member] and not allowed[member] then
				table.insert(unknown, `{entry.path}: {alias}.{member}`)
			end
		end
	end

	print(`  note {reads} read(s) of '{package_name}' against {export_count} exports`)
	total_reads += reads
end

h.saw("packages whose API could be read", checked_packages, 1)
if #skipped > 0 then
	table.sort(skipped)
	print(`  note not checkable headlessly: {table.concat(skipped, ", ")}`)
end

-- The guard that makes a clean result mean something: if alias resolution
-- broke, this fails instead of the check below passing over nothing.
h.saw("member reads found", total_reads, 20)
print(`  note {type_refs} read(s) classified as TYPE references and not checked`)

table.sort(unknown)
h.check(
	`every member read exists on its package ({total_reads} reads)`,
	#unknown == 0,
	if #unknown > 0 then table.concat(unknown, ", ") else nil
)

h.done()
