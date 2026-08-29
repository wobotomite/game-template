--!strict
-- Shared scaffolding for the specs in this directory.
--
-- Every spec here is a plain Lune script, run either through `tests/run.luau`
-- or on its own with `lune run tests/<name>.spec.luau`. There is no test
-- framework: a spec prints a line per assertion and exits non-zero if any of
-- them failed. That is deliberate — it keeps a spec readable top to bottom and
-- lets it do whatever it needs (read source, load a chunk, walk the tree)
-- without fighting a runner.
--
-- What this module exists for is the part that is NOT worth rewriting per
-- spec. In the game this template came from, forty-five specs each carried
-- their own copy-pasted `check`, `strip`, `walk` and brace matcher, and every
-- copy was a chance to get one of them subtly wrong.
--
-- ## The one rule worth internalising
--
-- A source-scanning check that silently fails to FIND anything reports
-- "clean", which is indistinguishable from passing. Every scan here should be
-- paired with `saw()` — an assertion that the scan located what it was looking
-- for at all. That guard has caught more real problems than the checks it
-- guards.

local fs = require "@lune/fs"
local process = require "@lune/process"

local harness = {}

-- ============================== assertions ================================

local failures = 0
local passes = 0

-- One-line banner. Optional, but a spec that says what it is checking is much
-- easier to read in a runner's combined output.
function harness.title(text: string)
	print(text)
end

function harness.check(label: string, ok: boolean, detail: string?)
	if ok then
		passes += 1
		print(`  ok   {label}`)
	else
		failures += 1
		print(`  FAIL {label}{if detail then ` -- {detail}` else ""}`)
	end
end

function harness.equals(label: string, got: any, want: any)
	harness.check(label, got == want, `got {tostring(got)}, want {tostring(want)}`)
end

-- THE BLINDNESS GUARD. Assert that a scan actually located `count` of
-- something, so a matcher that has gone blind fails loudly instead of
-- reporting a vacuous pass.
--
-- Pass a `min` you can estimate independently. "At least one" is worth having;
-- "at least the eleven I counted by hand" is worth much more.
function harness.saw(what: string, count: number, min: number?)
	local floor = min or 1
	harness.check(`scan found {count} {what}`, count >= floor, `expected at least {floor}`)
end

-- Prints the summary and exits. Call it as the last line of every spec — the
-- exit code is how `tests/run.luau` and CI learn what happened.
--
-- EXITS EXPLICITLY, INCLUDING ON SUCCESS. Falling off the end instead lets
-- anything still running decide the exit code, and specs here start real code:
-- `loads.spec` requires every module, and a module that spawns a thread at
-- require time keeps running after the assertions are done. One of those
-- throwing against a stubbed service made a spec print `3 passed, 0 failed` and
-- exit 1 — a verdict contradicting itself, which is worse than either answer
-- alone, because the reader has to work out which half to believe.
--
-- The printed summary is the verdict. A stray background error still lands on
-- stderr where a human can see it; it just does not get to overrule the
-- assertions.
function harness.done()
	print(`{passes} passed, {failures} failed`)
	process.exit(if failures > 0 then 1 else 0)
end

function harness.failed(): number
	return failures
end

-- ================================ sources =================================

function harness.read(path: string): string
	return fs.readFile(path)
end

-- Every `.luau` file under `dir` (default `src`), depth first.
function harness.walk(dir: string?, out: { string }?): { string }
	local root = dir or "src"
	local found = out or {}
	for _, name in fs.readDir(root) do
		local path = `{root}/{name}`
		if fs.isDir(path) then
			harness.walk(path, found)
		elseif name:match "%.luau$" then
			table.insert(found, path)
		end
	end
	return found
end

export type Source = { path: string, source: string }

function harness.sources(dir: string?): { Source }
	local out: { Source } = {}
	for _, path in harness.walk(dir) do
		table.insert(out, { path = path, source = fs.readFile(path) })
	end
	return out
end

-- ================================ stripping ===============================

-- Blank out comments and string BODIES, preserving line count and structure.
--
-- Both halves matter, and the second half is the one people leave out.
-- A source-scanning spec that reads raw text forbids its own documentation:
-- the clearest way to explain a rule is to quote the code it forbids, so the
-- more precisely someone documents an invariant, the more certainly they trip
-- the check that enforces it. The same sentence inside a `warn()` does exactly
-- the same thing, which is why strings are blanked too.
--
-- Pass `keep_strings` for the rare scan that genuinely wants string contents
-- (looking for an asset id, say).
function harness.strip(source: string, keep_strings: boolean?): string
	-- Long comments first: they span lines, so they have to go before the
	-- per-line pass. Replaced with a newline so line numbers only shrink where
	-- the comment really was.
	source = source:gsub("%-%-%[(=*)%[.-%]%1%]", "\n")
	local out = {}
	for line in (source .. "\n"):gmatch "(.-)\n" do
		line = line:gsub("%-%-.*$", "")
		if not keep_strings then
			line = line:gsub('"[^"]*"', '""')
			line = line:gsub("'[^']*'", "''")
			line = line:gsub("`[^`]*`", "``")
		end
		table.insert(out, line)
	end
	return table.concat(out, "\n")
end

function harness.lines(source: string): { string }
	local out = {}
	for line in (source .. "\n"):gmatch "(.-)\n" do
		table.insert(out, line)
	end
	return out
end

-- ============================== table reading =============================

-- The body of the first brace-delimited block following `header`, matched by
-- BRACE DEPTH rather than by pattern.
--
-- `header.-%b{}` and friends look like they would do this and do not: a `.-`
-- between two braces stops at the first close brace, so a nested table hands
-- back its first entry and calls it the whole block.
function harness.block_after(source: string, header: string): string?
	local at = source:find(header, 1, true)
	if not at then
		return nil
	end
	local open = source:find("{", at + #header - 1, true)
	if not open then
		return nil
	end
	local depth = 0
	for i = open, #source do
		local c = source:sub(i, i)
		if c == "{" then
			depth += 1
		elseif c == "}" then
			depth -= 1
			if depth == 0 then
				return source:sub(open + 1, i - 1)
			end
		end
	end
	return nil
end

-- Keys written at the TOP level of a block body: `Density = 0.3`, but not the
-- `Color = ...` inside a nested table.
function harness.top_keys(body: string): { string }
	local keys = {}
	local depth = 0
	local i = 1
	while i <= #body do
		local c = body:sub(i, i)
		if c == "{" then
			depth += 1
		elseif c == "}" then
			depth -= 1
		elseif depth == 0 then
			local key, after = body:match("^([%a_][%w_]*)%s*=()", i)
			-- Not a key if it is the tail of a longer expression
			-- (`a.b = 1`, `x == y`).
			if key and not body:sub(1, i - 1):match "[%w_.:\"']$" then
				table.insert(keys, key)
				i = after - 1
			end
		end
		i += 1
	end
	return keys
end

function harness.set(list: { string }): { [string]: boolean }
	local out = {}
	for _, key in list do
		out[key] = true
	end
	return out
end

-- =============================== requires =================================

-- Every `require(...)` argument in `source`, matched by BALANCED PARENS.
--
-- The obvious `require%(([^)]*)%)` cannot cross an inner paren, so it silently
-- skips the one form that contains one:
--
--     require(game:GetService("ReplicatedStorage").Shared.records["thing"])
--
-- A differential that misses a file is indistinguishable from a differential
-- that passes it, and one outlier is enough to make a whole scan a lie.
function harness.requires(source: string): { string }
	local found = {}
	local i = 1
	while true do
		local at = source:find("require%s*%(", i)
		if not at then
			break
		end
		local open = source:find("(", at, true) :: number
		local depth = 0
		local j = open
		while j <= #source do
			local c = source:sub(j, j)
			if c == "(" then
				depth += 1
			elseif c == ")" then
				depth -= 1
				if depth == 0 then
					table.insert(found, source:sub(open + 1, j - 1))
					break
				end
			end
			j += 1
		end
		i = j + 1
	end
	return found
end

return harness
