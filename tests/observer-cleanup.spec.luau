--!nocheck
-- Every observer subscription must be disposable or provably one-shot.
-- Run with:
--   lune run tests/observer-cleanup.spec.luau
--
-- WHY THIS EXISTS. `observe_players` and `observe_character` return a
-- destructor. Dropping it is harmless in the one case everything here happens
-- to be in today -- a subscription taken once, at module scope or behind a
-- re-entry guard, meant to live as long as the process -- and silently wrong in
-- the case nobody notices adding: a subscription taken inside a function that
-- runs more than once.
--
-- That second case does not error, does not warn and does not leak visibly. It
-- stacks. The second run has two observers, the fifth has five, and every
-- callback fires that many times -- so a "damage applied twice" or a
-- "leaderboard row duplicated" bug appears several runs in, scaling with how
-- long the server has been up, which is the hardest possible shape to
-- reproduce from a report.
--
-- An audit of both trees found 38 call sites and no violations, so this spec
-- starts green. That is the point: it is cheap to hold a clean invariant and
-- expensive to rediscover it, and the invariant is not visible from any one
-- call site.
--
-- WHAT COUNTS AS SAFE, and why each is enough:
--   * MODULE SCOPE -- runs exactly once, at require. Nothing to clean up
--     before the process ends.
--   * CAPTURED or RETURNED -- the caller now owns the destructor, which is the
--     whole contract. This spec does not chase what they do with it; handing it
--     back is where its jurisdiction ends.
--   * RE-ENTRY GUARDED -- `if started then return end started = true`, or
--     `if not observing then observing = true ... end`. The function may be
--     called many times but subscribes once.
--
-- THE FALSE-POSITIVE PROBLEM IS THE HARD PART. A first cut of this check looked
-- back a fixed 25 lines for a guard and reported three violations that were all
-- guarded further up -- including `run-orchestrator.init`, whose guard is the
-- first thing in a function hundreds of lines long. A check that cries wolf
-- three times out of five gets deleted. So the guard search reads the WHOLE
-- enclosing function, found by scanning to the next top-level `end`.

local h = require "./harness"

h.title "observer cleanup:"

local CALL = "observe_players%s*%(", "observe_character%s*%("
local PATTERNS = { "observe_players%s*%(", "observe_character%s*%(" }

-- `if started then return end ... started = true`, or
-- `if not observing then observing = true`.
--
-- BOTH HALVES, AND THE SAME FLAG. An earlier version accepted any
-- `if X then return end` anywhere in the function, which meant every function
-- with an ordinary early return read as guarded -- and a deliberately-injected
-- unguarded subscription sailed through. Found by mutation; it is the exact
-- vacuous-green this spec is supposed to be immune to, sitting inside the spec.
--
-- `prefix` is the function body UP TO the subscription line, so a guard that
-- happens to sit after the call cannot vouch for it either.
local function has_reentry_guard(prefix: string): boolean
	for flag in prefix:gmatch "if%s+([%w_]+)%s+then%s*\n%s*return%s*\n%s*end" do
		if prefix:find(`{flag}%s*=%s*true`) then
			return true
		end
	end
	for flag in prefix:gmatch "if%s+not%s+([%w_]+)%s+then" do
		if prefix:find(`{flag}%s*=%s*true`) then
			return true
		end
	end
	return false
end

local sites = 0
local violations: { string } = {}

for _, dir in { "src" } do
	for _, entry in h.sources(dir) do
		if entry.path:find "util/observers/" then
			continue
		end
		local lines = h.lines(h.strip(entry.source))
		for i, line in lines do
			local is_call = false
			for _, pattern in PATTERNS do
				if line:find(pattern) then
					is_call = true
					break
				end
			end
			if not is_call then
				continue
			end
			sites += 1

			local trimmed = line:gsub("^%s+", "")
			-- THE ONLY DISCARD IS A STATEMENT THAT STARTS WITH THE CALL. Anything
			-- else -- `const d = observe_x(...)`, `return observe_x(...)`,
			-- `vide.cleanup(observe_x(...))`, `table.insert(bin, observe_x(...))`
			-- -- puts the destructor somewhere, and where it goes after that is
			-- not this spec's business.
			--
			-- The first version of this only accepted assignment and `return`,
			-- and duly reported four `vide.cleanup(observe_character(...))` call
			-- sites -- the single most correct way to write this -- as
			-- violations. Four false positives out of six findings is how a
			-- spec earns a reputation for crying wolf and stops being run.
			if not trimmed:match "^observe_%a+%s*%(" then
				continue
			end

			-- Find the enclosing top-level function, if there is one. A
			-- backwards scan alone is not enough: it happily finds a function
			-- that CLOSED before this line, which is how a subscription inside
			-- a top-level `if` block gets blamed on an unrelated function above
			-- it. So the function's own `end` has to come after us.
			local start_line = nil
			for j = i, 1, -1 do
				if lines[j]:match "^@?%a*%s*local?%s*function%s" or lines[j]:match "^function%s" then
					local closes_at = nil
					for k = j + 1, #lines do
						if lines[k] == "end" then
							closes_at = k
							break
						end
					end
					if closes_at == nil or closes_at > i then
						start_line = j
					end
					break
				end
			end

			-- Not inside any function: module scope, however deeply a top-level
			-- `if` indents it. Runs once, at require.
			if start_line == nil then
				continue
			end
			local prefix = {}
			if start_line then
				for j = start_line, i do
					table.insert(prefix, lines[j])
				end
			end
			if has_reentry_guard(table.concat(prefix, "\n")) then
				continue
			end

			table.insert(violations, `{entry.path}:{i} — subscribes inside a function with no guard and drops the destructor`)
		end
	end
end

-- BLINDNESS GUARD. If the scan matched nothing, "no violations" means "looked
-- at nothing" -- the vacuous green this whole class of spec exists to avoid.
h.saw("observer call sites", sites, 10)

table.sort(violations)
h.check(
	`every subscription is captured, module-scope, or guarded ({sites} sites)`,
	#violations == 0,
	if #violations > 0 then "\n       " .. table.concat(violations, "\n       ") else nil
)

h.done()
