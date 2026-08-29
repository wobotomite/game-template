--!nocheck
-- util/debug/profile: scope bookkeeping, and the balance mistake the engine
-- tolerates silently.
-- Run with:
--   lune run tests/profile.spec.luau
--
-- WHY THIS EXISTS. The whole reason the module wraps a two-line engine API is
-- that `debug.profileend()` with nothing open does not error, does not warn and
-- returns nothing -- so a leaked scope produces a plausible, wrong flame graph.
-- Every case below is about the bookkeeping that turns that into something you
-- can see. The engine calls themselves are not exercised: `available` is false
-- under Lune, which is exactly why the depth counter is kept independently of
-- the engine rather than inferred from it.
--
-- EXPECT TWO [warn] LINES IN THE OUTPUT. They are the module reporting the
-- unbalanced close and the leaked frame, which is the behaviour under test --
-- their absence would be the failure. Both are latched, so each appears once
-- however many times its case is provoked.

local h = require "./harness"
local env = require "./roblox-env"

h.title "profile:"

-- Module-level state (the depth counter, the latched warnings) is shared by
-- everyone who requires it, so each block that dirties it reloads a clean copy
-- rather than depending on the order these run in.
local function fresh()
	env.clear_cache()
	return env.load "ReplicatedStorage.Util.debug.profile"
end

local profile = fresh()

do
	h.equals("the engine profiler is absent under Lune", profile.available, false)
	h.equals("nothing is open to begin with", profile.depth_now(), 0)
end

-- =============================== open / close =============================

do
	local p = fresh()
	local close = p.open "a"
	h.equals("open raises the depth", p.depth_now(), 1)
	close()
	h.equals("its closure lowers it again", p.depth_now(), 0)
end

do
	local p = fresh()
	local outer = p.open "outer"
	local inner = p.open "inner"
	h.equals("scopes nest", p.depth_now(), 2)
	inner()
	outer()
	h.equals("and unwind", p.depth_now(), 0)
end

do
	-- Closing twice is easy to write when a close is reachable from two paths.
	-- THE SECOND CLOSE MUST NOT EAT THE ENCLOSING SCOPE, which is the damage:
	-- it does not merely double-count, it silently closes somebody else's
	-- scope and misnests everything after.
	--
	-- The obvious version of this test -- open one scope, close it twice, check
	-- the depth is 0 -- proves nothing. At depth 0 the underflow guard catches
	-- the second close anyway, so it passes with the idempotence guard removed.
	-- Found by mutation, and the fix is to have an OUTER scope for the stray
	-- close to damage.
	local p = fresh()
	local outer = p.open "outer"
	local inner = p.open "inner"
	inner()
	inner()
	h.equals("a repeated close does not close the enclosing scope", p.depth_now(), 1)
	outer()
	h.equals("the outer scope still closes normally", p.depth_now(), 0)
end

do
	-- The engine tolerates this silently; the module must not go negative,
	-- because a negative depth would mask the NEXT real leak by cancelling it.
	local p = fresh()
	p.close()
	h.equals("close with nothing open does not go negative", p.depth_now(), 0)
	local close = p.open "a"
	h.equals("and the counter still tracks correctly afterwards", p.depth_now(), 1)
	close()
	h.equals("back to zero", p.depth_now(), 0)
end

do
	-- The zero-allocation pair. Same bookkeeping as the closure form, so a
	-- per-frame call site is not choosing between cheap and correct.
	local p = fresh()
	p.begin "a"
	h.equals("begin raises the depth", p.depth_now(), 1)
	p.begin "b"
	h.equals("begin nests", p.depth_now(), 2)
	p.close()
	p.close()
	h.equals("close unwinds both", p.depth_now(), 0)
end

-- ================================= scope ==================================

do
	local p = fresh()
	local got_a, got_b = p.scope("work", function(a, b)
		return a + b, `{a}-{b}`
	end, 2, 3)
	h.equals("scope returns the function's first value", got_a, 5)
	h.equals("scope returns the rest too", got_b, "2-3")
	h.equals("scope leaves nothing open", p.depth_now(), 0)
end

do
	-- THE CASE THE MODULE EXISTS FOR. A throw must not leak the scope.
	local p = fresh()
	local ok, err = pcall(function()
		p.scope("work", function()
			error "boom"
		end)
	end)
	h.check("scope re-raises the error", not ok)
	h.check("the original message survives", tostring(err):find "boom" ~= nil)
	h.equals("and the scope was still closed", p.depth_now(), 0)
end

do
	local p = fresh()
	local n = 0
	p.scope("outer", function()
		p.scope("inner", function()
			n += 1
		end)
	end)
	h.equals("nested scopes both ran", n, 1)
	h.equals("nested scopes both closed", p.depth_now(), 0)
end

-- ================================= memory =================================

do
	local p = fresh()
	local value = p.memory("tag", function(x)
		return x * 2
	end, 21)
	h.equals("memory passes arguments and returns values", value, 42)

	local ok = pcall(function()
		p.memory("tag", function()
			error "boom"
		end)
	end)
	h.check("memory re-raises too", not ok)
end

-- ============================ frame_boundary ==============================

do
	-- A leak should be caught the frame it happens, not inherited by every
	-- frame after it.
	local p = fresh()
	p.open "leaked"
	p.open "also leaked"
	h.equals("two scopes are open", p.depth_now(), 2)
	p.frame_boundary()
	h.equals("the frame boundary closes what leaked", p.depth_now(), 0)

	local close = p.open "clean"
	close()
	p.frame_boundary()
	h.equals("a balanced frame is left alone", p.depth_now(), 0)
end

-- ===================== balance, across the whole tree =====================

-- `begin`/`close` is the zero-allocation pair, and it is the one that can be
-- got wrong: the engine tolerates an unbalanced `profileend` silently, so a
-- missing `close` shows up as a plausible, wrong flame graph rather than an
-- error. Counting per file is a coarse check and it catches the mistake that
-- actually happens -- adding a `begin` and forgetting its partner.
--
-- Counted on STRIPPED source so the examples in these comments do not vote.
do
	local files = 0
	local unbalanced: { string } = {}
	for _, entry in h.sources "src" do
		if entry.path:find "util/debug/profile" then
			continue
		end
		local source = h.strip(entry.source)
		local begins, closes = 0, 0
		for _ in source:gmatch "profile%.begin%s*[\"'`(]" do
			begins += 1
		end
		for _ in source:gmatch "profile%.close%s*%(" do
			closes += 1
		end
		if begins > 0 or closes > 0 then
			files += 1
			if begins ~= closes then
				table.insert(unbalanced, `{entry.path}: {begins} begin, {closes} close`)
			end
		end
	end

	-- Blindness guard: zero files scanned would make the assertion below
	-- vacuously true forever.
	h.saw("files using the begin/close pair", files, 1)
	h.check(
		`every begin has a close ({files} file(s))`,
		#unbalanced == 0,
		if #unbalanced > 0 then "\n       " .. table.concat(unbalanced, "\n       ") else nil
	)
end

h.done()
