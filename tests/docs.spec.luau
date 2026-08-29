--!nocheck
-- Every file path the docs and code comments point at must exist.
-- Run with:
--   lune run tests/docs.spec.luau
--
-- WHY THIS EXISTS. Documentation goes stale silently, and the specific way it
-- goes stale is a MOVE: a module sitting in `shared` is moved into
-- `shared/world`, and eleven prose references keep naming the old path. Nothing errors. The
-- reader follows the pointer, finds nothing, and now distrusts the rest of the
-- document — which is worse than the document not existing, because the parts
-- that are still true have lost their credibility too.
--
-- This tree moved six files in one pass. That is exactly when this check earns
-- itself.
--
-- THE FALSE-POSITIVE PROBLEM IS THE HARD PART, and it is why the matcher below
-- is narrow. An earlier version of this check on the game this template came
-- from reported 45 stale references, of which ZERO were real: it was matching
-- hyphenated adjectives ("client-side", "run-over") as if they were module
-- names. A check that cries wolf 45 times gets deleted, and takes the one real
-- finding with it.
--
-- So a reference counts only when it is unambiguous:
--   * inside backticks or a markdown link, AND
--   * contains a `/`, AND
--   * starts at a known root (src, tests, docs, scripts) or ends in .luau/.md
--
-- Prose like "see the sync registry" is not checked and should not be. The
-- point is to catch pointers that LOOK precise and are wrong.

-- NOTE FOR EDITORS OF THIS FILE: keep the examples in these comments free of
-- concrete tree paths. This spec is mirrored verbatim into the game built from
-- the template, and the two trees do not have the same layout -- an example
-- naming a real file here is a BROKEN REFERENCE there, reported by this very
-- check. Three of them were, which is how this note came to exist.

local h = require "./harness"
local fs = require "@lune/fs"

h.title "docs references:"

local ROOTS = { "src/", "tests/", "docs/", "scripts/" }
-- SRC-RELATIVE SHORTHAND. `util/events/step-stats` is how this tree's docs and
-- comments actually write a pointer -- far more often than the `src/`-prefixed
-- form -- and until these roots were added, every one of them went unchecked.
-- Adding them took the reference count from 109 to 172 and immediately turned
-- up five stale pointers, including a doc naming a module that does not exist
-- for the very convention that doc exists to document.
local SRC_ROOTS = { "util/", "shared/", "server/", "client/", "effects/" }

local function is_candidate(text: string): boolean
	if not text:find "/" then
		return false
	end
	-- A path reference has no whitespace. This excludes quoted TOOL OUTPUT,
	-- which is the one thing in these docs that looks like a path and is not:
	-- `src/util/tween/init.luau(98,10): LintName: ...` is an example of a
	-- diagnostic format, printed to show what to filter on.
	if text:find "%s" then
		return false
	end
	for _, root in ROOTS do
		if text:sub(1, #root) == root then
			return true
		end
	end
	for _, root in SRC_ROOTS do
		if text:sub(1, #root) == root then
			-- ONE SLASH IS NOT ENOUGH ON ITS OWN for the shorthand form,
			-- because English writes pairs the same way: "the client/server
			-- boundary" is prose, not a pointer, and flagging it is precisely
			-- the crying-wolf failure described above. A real module name in
			-- this tree is hyphenated or carries an extension, so require the
			-- last segment to look like one -- or require enough depth
			-- (`util/debug/gizmos`) that prose is no longer a plausible
			-- reading.
			local last = text:match "[^/]+$" or ""
			if last:find "[%-%.]" then
				return true
			end
			return select(2, text:gsub("/", "")) >= 2
		end
	end
	return false
end

-- A shorthand reference -> the file it names, whichever extension that has.
local function resolves(reference: string): boolean
	-- Strip a line anchor or a markdown heading fragment.
	local path = reference:gsub("#.*$", ""):gsub(":%d+$", ""):gsub("/$", "")
	-- `.spec.luau` too: a comment pointing at `tests/tween` is the house
	-- shorthand for `tests/tween.spec.luau`, and reporting those as broken
	-- would be three false positives out of five hits -- which is how a check
	-- earns a reputation for crying wolf and stops being run.
	-- `util/debug/gizmos.drawCube` is a MEMBER reference: the pointer is the
	-- module and the tail names a function on it. Resolving the module is the
	-- right answer -- but only as a fallback, so a genuinely wrong extension
	-- still fails rather than passing on the strength of its directory.
	-- (`[%w_]`, not `%w`: Lua's `%w` excludes underscores, so a first cut of
	-- this missed every `module.snake_case_member` -- which is most of them.)
	local without_member = path:gsub("%.[%w_]+$", "")
	for _, base in { path, "src/" .. path, without_member, "src/" .. without_member } do
		-- `.client.luau` / `.server.luau` for the same reason as `.spec.luau`:
		-- the house shorthand drops the role suffix, so a comment pointing at a
		-- client module resolves to its `.client.luau` file.
		-- Five of the ghost game's references were reported broken purely
		-- because the resolver did not try these two.
		for _, candidate in
			{
				base,
				base .. ".luau",
				base .. "/init.luau",
				base .. ".md",
				base .. ".spec.luau",
				base .. ".client.luau",
				base .. ".server.luau",
			}
		do
			if fs.isFile(candidate) or fs.isDir(candidate) then
				return true
			end
		end
	end
	return false
end

local checked = 0
local broken: { string } = {}
local seen: { [string]: boolean } = {}

-- Bare, unquoted paths. ONLY used on comment text, and only for tokens that
-- start at a known root: `src/shared/records/tags` written mid-sentence in a
-- header comment is unambiguously a pointer, while the same words in a doc
-- might be prose. Mutation-testing this spec is what surfaced the gap -- the
-- backtick-and-link matcher alone missed a broken path in a code comment,
-- which is the most common place they are written.
local function scan_bare(path: string, source: string)
	for reference in source:gmatch "([%w_%-%./]+)" do
		-- Trailing sentence punctuation is not part of the path.
		local trimmed = reference:gsub("[%.,;:%)]+$", "")
		if is_candidate(trimmed) and not seen[`{path}|{trimmed}`] then
			seen[`{path}|{trimmed}`] = true
			checked += 1
			if not resolves(trimmed) then
				table.insert(broken, `{path}: {trimmed}`)
			end
		end
	end
end

local function scan(path: string, source: string)
	-- Backticked spans and markdown link targets. Both are the author saying
	-- "this is a path", which is the whole basis for checking it.
	for reference in source:gmatch "`([^`\n]+)`" do
		if is_candidate(reference) and not seen[`{path}|{reference}`] then
			seen[`{path}|{reference}`] = true
			checked += 1
			if not resolves(reference) then
				table.insert(broken, `{path}: {reference}`)
			end
		end
	end
	for reference in source:gmatch "%]%(([^)%s]+)%)" do
		if is_candidate(reference) and not seen[`{path}|{reference}`] then
			seen[`{path}|{reference}`] = true
			checked += 1
			if not resolves(reference) then
				table.insert(broken, `{path}: {reference}`)
			end
		end
	end
end

for _, name in fs.readDir "docs" do
	if name:match "%.md$" then
		scan(`docs/{name}`, fs.readFile(`docs/{name}`))
	end
end
scan("README.md", fs.readFile "README.md")
if fs.isFile "src/effects/README.md" then
	scan("src/effects/README.md", fs.readFile "src/effects/README.md")
end

-- Code comments too: a header pointing at a sibling module is a pointer with
-- the same failure mode as one in a doc.
--
-- `tests` AS WELL AS `src`, and that gap was not hypothetical. Spec headers are
-- dense with pointers -- to the module under test, to the doc explaining the
-- rule, to sibling specs -- and they were the one place nothing checked. This
-- very file was the offender: the comment above explaining `.spec.luau`
-- shorthand cited a spec that exists in the game this template came from and
-- not in the template, so the check for stale references carried a stale
-- reference, in the only directory it declined to read.
for _, dir in { "src", "tests" } do
	for _, entry in h.sources(dir) do
		-- Comments only. A path inside a STRING is usually a real runtime value
		-- (an asset folder name), not a pointer, and checking it would flag
		-- things that are correct.
		local comments = {}
		for line in (entry.source .. "\n"):gmatch "(.-)\n" do
			local comment = line:match "%-%-(.*)$"
			if comment then
				table.insert(comments, comment)
			end
		end
		local comment_text = table.concat(comments, "\n")
		scan(entry.path, comment_text)
		scan_bare(entry.path, comment_text)
	end
end

h.saw("path references in docs and comments", checked, 30)

table.sort(broken)
h.check(
	`every referenced path exists ({checked} references)`,
	#broken == 0,
	if #broken > 0 then "\n       " .. table.concat(broken, "\n       ") else nil
)

h.done()
