--!nocheck
-- The effect registry's two blind spots, closed against the real folder.
-- Run with:
--   lune run tests/effects.spec.luau
--
-- WHY THIS EXISTS. `src/effects` decides what an effect is by WALKING `list/` —
-- a file exists, therefore the effect exists. That is the right design (there
-- is no list to keep in sync) and it has exactly two holes, one in each
-- direction:
--
--   a name that resolves to nothing   `effects.new "commmon/telegraph"` is a
--                                     typo the registry cannot see until it is
--                                     spawned, which is mid-fight
--   an entry nobody spawns            a dead file that LOOKS alive, because it
--                                     sits in the folder next to the live ones
--
-- `effect-types.luau` generates a union of the real folder paths so Studio
-- rejects the first kind. But **luau-lsp cannot evaluate user-defined type
-- functions** — it reports "This syntax is not supported" for that file — so
-- the union constrains names in Studio and NOT on the command line, and a union
-- that silently degraded to `string` would look exactly the same. That is the
-- whole reason this spec exists rather than trusting the type.
--
-- THE COUNT IS PINNED EXACTLY, NOT BOUNDED. A `>= 20` style check was
-- mutation-tested on the original of this spec and stayed green while three
-- effects were deleted one at a time. **A bound is only a check outside its own
-- slack.** Bumping the number when you add an effect is the point, not an
-- annoyance: it is the one line that makes a deletion visible.

local h = require "./harness"

h.title "effects:"

-- Bump this when you add or remove an entry in src/effects/list. Deliberately.
local EXPECTED_ENTRIES = 1

-- ============================ what exists =================================

local entries: { [string]: boolean } = {}
for _, path in h.walk "src/effects/list" do
	-- `list/common/ground-telegraph.luau` -> `common/ground-telegraph`
	local name = path:gsub("^src/effects/list/", ""):gsub("%.luau$", "")
	entries[name] = true
end

local entry_count = 0
for _ in entries do
	entry_count += 1
end

h.saw("entries in src/effects/list", entry_count, 1)
h.equals("the entry count is what the spec expects", entry_count, EXPECTED_ENTRIES)

-- ============================ what is spawned =============================

-- Every spawn call across the tree, found by RESOLVING THE REGISTRY'S ALIAS in
-- each file rather than by matching `.new "..."` anywhere.
--
-- The loose version of this was written first and it matched
-- `Instance.new "Part"`, `BrickColor.new "Bright orange"` and every other
-- constructor in the codebase — 35 "call sites", 22 of them nonsense, and the
-- real ones buried among them. A scan can fail by seeing nothing; it can also
-- fail by seeing everything, and the second kind is louder but no more useful.
--
-- Comments are stripped, so the usage examples in the registry's own header --
-- which name effects on purpose -- are not read as call sites. Strings are
-- KEPT, because the name being looked for lives inside one.
local spawned: { [string]: { string } } = {}
local call_sites = 0
local users = 0

for _, entry in h.sources "src" do
	local stripped = h.strip(entry.source, true)
	-- `const effects = require(ReplicatedStorage.Effects)` -- whatever it is
	-- called locally.
	local alias = stripped:match "[%w_]+%s+([%w_]+)%s*=%s*require%(ReplicatedStorage%.Effects%)"
	if not alias then
		continue
	end
	users += 1
	for name in stripped:gmatch(alias .. '%s*%.new%s*%(?%s*"([^"]+)"') do
		call_sites += 1
		if not spawned[name] then
			spawned[name] = {}
		end
		table.insert(spawned[name], entry.path)
	end
end

-- NOTHING USES THE REGISTRY YET is a real state for a fresh template, and it is
-- not the same as "everything checks out". Both directional checks below are
-- inert without call sites, so say so rather than printing two green lines that
-- examined nothing.
local wired_up = users > 0
if not wired_up then
	print "  note nothing in src/ requires the Effects registry yet -- the two"
	print "       directional checks below are inert until something spawns an effect."
else
	h.saw(`effects.new call sites across {users} file(s)`, call_sites, 1)
end

-- ======================= direction 1: names resolve =======================

local unresolved: { string } = {}
for name, sites in spawned do
	if not entries[name] then
		table.insert(unresolved, `{name} (from {sites[1]})`)
	end
end
h.check(
	`every spawned name resolves to a file in list/ ({call_sites} call sites)`,
	#unresolved == 0,
	if #unresolved > 0 then table.concat(unresolved, ", ") else nil
)

-- ==================== direction 2: entries are reached ====================

local unused: { string } = {}
for name in entries do
	if not spawned[name] then
		table.insert(unused, name)
	end
end
table.sort(unused)
if wired_up then
	h.check(
		`every entry in list/ is spawned somewhere ({entry_count} entries)`,
		#unused == 0,
		if #unused > 0 then table.concat(unused, ", ") else nil
	)
else
	print(`  note {#unused} entry(ies) unspawned, which is expected while nothing uses the registry`)
end

-- ====================== the registry's own contract =======================

-- Each entry returns ONE FUNCTION. The registry asserts this at build time,
-- but that assert only fires for a place that actually builds the registry --
-- so a module returning a table ships fine and breaks the first time anything
-- spawns anything.
local not_functions: { string } = {}
for _, path in h.walk "src/effects/list" do
	local source = h.strip(h.read(path))
	if not source:match "return%s+function" then
		table.insert(not_functions, path)
	end
end
h.check(
	"every entry returns a function",
	#not_functions == 0,
	if #not_functions > 0 then table.concat(not_functions, ", ") else nil
)

-- ============== the rule the generated type union depends on ==============

-- `effect-types.luau` builds its union of valid names by walking the list/
-- folder's TYPE and taking the leaves: a node with children is a folder, a node
-- without is a module. That rule holds for a tree where no entry is written as
-- an `init.luau` -- Rojo turns one of those into a ModuleScript that HAS
-- children, which the walk would read as a folder and leave out of the union.
--
-- The consequence is mild (the effect still registers and runs; it just stops
-- typechecking by name) and completely silent, which is the part worth
-- guarding. None of it is checkable in the type itself: luau-lsp cannot
-- evaluate type functions and Lune has no DataModel, so the walk runs in
-- exactly one place -- Studio. This checks the same rule against the real
-- folder instead, which is a proxy for the type and not the type.
local init_entries: { string } = {}
for _, path in h.walk "src/effects/list" do
	if path:match "/init%.luau$" then
		table.insert(init_entries, path)
	end
end
h.check(
	"no entry is written as an init.luau (it would drop out of the name union)",
	#init_entries == 0,
	if #init_entries > 0 then table.concat(init_entries, ", ") else nil
)

-- And the other half of the same rule: every name the union would produce is a
-- name the RUNTIME would register. The runtime walk registers ModuleScripts and
-- recurses into Folders, so a folder path is never an effect -- which is why
-- the union no longer offers one.
local folder_names: { [string]: boolean } = {}
for name in entries do
	local parent = name:match "^(.*)/[^/]+$"
	while parent do
		folder_names[parent] = true
		parent = parent:match "^(.*)/[^/]+$"
	end
end
local offered_folders: { string } = {}
for folder in folder_names do
	if entries[folder] then
		table.insert(offered_folders, folder)
	end
end
h.check(
	"no path is both a grouping folder and an entry",
	#offered_folders == 0,
	if #offered_folders > 0 then table.concat(offered_folders, ", ") else nil
)

h.done()
