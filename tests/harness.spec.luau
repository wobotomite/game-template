--!nocheck
-- The harness, tested with its own assertions deliberately NOT used.
-- Run with:
--   lune run tests/harness.spec.luau
--
-- WHY THIS EXISTS. Eleven specs trust `tests/harness.luau` to be right, and
-- this exercise has repeatedly found bugs in checking infrastructure rather
-- than in the code being checked: an RNG seed that was decorative, an LCG with
-- no low-bit entropy, a matcher that saw everything, a matcher that saw
-- nothing, an assertion that was never true. The thing that checks fails more
-- quietly than the thing being checked, because its failure looks like good
-- news.
--
-- ON THE CIRCULARITY. A spec that tested `h.check` by calling `h.check` would
-- report clean if `check` were broken to always pass. So this file counts and
-- prints for itself, and uses the harness ONLY as the subject. That leaves
-- `check`, `saw` and `done` untested here — and they are covered by something
-- better than a test: every spec in this suite has been mutation-tested, and
-- each went red on its mutation. A `check` that could not fail would have made
-- all of those pass.
--
-- WHAT IS ACTUALLY TESTED is the part with logic in it: the stripper, the brace
-- matcher, the key reader, the require extractor, and the walker. Those are
-- where a subtle wrong answer produces a silently weaker check somewhere else.

local h = require "./harness"
local fs = require "@lune/fs"

local passes, failures = 0, 0
local function expect(label: string, got: any, want: any)
	if got == want then
		passes += 1
		print(`  ok   {label}`)
	else
		failures += 1
		print(`  FAIL {label}: got {tostring(got)}, want {tostring(want)}`)
	end
end

print "harness:"

-- ================================ strip ===================================

do
	local source = table.concat({
		"local x = 1 -- trailing comment",
		"-- whole line",
		'local s = "a string"',
		"local t = 'single'",
		"local i = `interp`",
	}, "\n")

	local stripped = h.strip(source)
	expect("strip removes a trailing comment", stripped:find "trailing" == nil, true)
	expect("strip removes a whole-line comment", stripped:find "whole line" == nil, true)
	expect("strip blanks a double-quoted body", stripped:find "a string" == nil, true)
	expect("strip blanks a single-quoted body", stripped:find "single" == nil, true)
	expect("strip blanks an interpolated body", stripped:find "interp" == nil, true)
	expect("strip keeps the code", stripped:find "local x = 1" ~= nil, true)

	-- LINE STRUCTURE IS THE CONTRACT. Several scans report a line number, and a
	-- stripper that collapsed lines would make every one of them point at the
	-- wrong place -- which is worse than no line number, because it is
	-- confidently wrong.
	expect("strip preserves the line count", #h.lines(stripped), #h.lines(source))

	local kept = h.strip(source, true)
	expect("keep_strings keeps a string body", kept:find "a string" ~= nil, true)
	expect("keep_strings still removes comments", kept:find "whole line" == nil, true)
end

do
	-- Long comments span lines, so they have to be handled before the per-line
	-- pass. A scan that missed them would read commented-out code as code.
	local source = "local a = 1\n--[[\nlocal forbidden = 2\n]]\nlocal b = 3"
	local stripped = h.strip(source)
	expect("strip removes a long comment", stripped:find "forbidden" == nil, true)
	expect("strip keeps code around a long comment", stripped:find "local b = 3" ~= nil, true)
end

-- ============================= block_after ================================

do
	-- The nested case is the whole reason this is brace-matched rather than
	-- pattern-matched: `header.-}` stops at the FIRST close brace and hands
	-- back only the first entry.
	local source = table.concat({
		"const MOODS = {",
		"\tdark = {",
		"\t\tBrightness = 0,",
		"\t},",
		"\tbright = {",
		"\t\tBrightness = 2,",
		"\t},",
		"}",
	}, "\n")

	local body = h.block_after(source, "const MOODS")
	expect("block_after found the block", body ~= nil, true)
	expect("block_after spans past a nested close brace", (body or ""):find "bright" ~= nil, true)
	expect("block_after stops at the matching brace", (body or ""):find "^%s*}" == nil, true)
	expect("block_after returns nil for a header that is not there", h.block_after(source, "const NOPE"), nil)
end

-- ============================== top_keys ==================================

do
	local body = table.concat({
		"\tdark = {",
		"\t\tBrightness = 0,",
		"\t\tAmbient = 1,",
		"\t},",
		"\tbright = {",
		"\t\tBrightness = 2,",
		"\t},",
	}, "\n")

	local keys = h.top_keys(body)
	expect("top_keys found both top-level keys", #keys, 2)
	expect("top_keys[1]", keys[1], "dark")
	expect("top_keys[2]", keys[2], "bright")

	local set = h.set(keys)
	expect("nested keys are not reported", set.Brightness, nil)
end

-- ============================== requires ==================================

do
	-- The inner-paren form is the one that matters. A `require%(([^)]*)%)`
	-- matcher cannot cross the paren in `game:GetService("X")`, so it skips
	-- exactly the files that use the inline style -- silently, and a scan that
	-- misses a file is indistinguishable from one that passes it.
	local source = table.concat({
		'local a = require(ReplicatedStorage.Util.tables["deep-copy"])',
		'local b = require(game:GetService("ReplicatedStorage").Shared.network)',
		"local c = require(script.Parent.sibling)",
	}, "\n")

	local found = h.requires(source)
	expect("requires found all three", #found, 3)
	expect("requires handles a bracketed key", found[1]:find "deep%-copy" ~= nil, true)
	expect("requires crosses an inner paren", found[2]:find "Shared%.network" ~= nil, true)
	expect("requires does not swallow the next call", found[2]:find "script" == nil, true)
	expect("requires handles script-relative", found[3], "script.Parent.sibling")
end

do
	expect("requires returns nothing for a file with none", #h.requires "local x = 1", 0)
end

-- ============================ walk / sources ==============================

do
	local files = h.walk "tests"
	local found_self = false
	for _, path in files do
		if path == "tests/harness.spec.luau" then
			found_self = true
		end
	end
	expect("walk finds a file it should", found_self, true)

	local only_luau = true
	for _, path in files do
		if not path:match "%.luau$" then
			only_luau = false
		end
	end
	expect("walk returns only .luau files", only_luau, true)

	local sources = h.sources "tests"
	expect("sources returns one entry per file", #sources, #files)
	local first = sources[1]
	expect("sources carries the path", typeof(first.path), "string")
	expect("sources carries the text", first.source, fs.readFile(first.path))
end

-- ================================ summary =================================

print(`{passes} passed, {failures} failed`)
if failures > 0 then
	error(`{failures} harness case(s) failed`, 0)
end
