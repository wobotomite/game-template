-- MicroProfiler scopes, with the balance mistake made loud.
--
--   const close = profile.open "ghost tick"
--   ... work ...
--   close()
--
--   profile.scope("ghost tick", ghost.tick, g, ctx)   -- closes even on a throw
--
-- Open the MicroProfiler with Ctrl+F6 (Cmd+F6 on Mac) to see the labels, or
-- `/console` -> MicroProfiler on a live server.
--
-- ========================= WHY THIS EXISTS AT ALL =========================
--
-- `debug.profilebegin` / `debug.profileend` are already a two-line API, so a
-- wrapper has to earn itself. It earns itself on ONE measured fact:
--
--     an unbalanced `debug.profileend()` is SILENTLY TOLERATED. It does not
--     error, it does not warn, it returns nothing.
--
-- So a scope leaked by an early `return`, a `continue`, or a throw does not
-- announce itself. What happens instead is that every subsequent scope nests
-- one level deeper than it should, and the MicroProfiler shows a plausible,
-- wrong picture -- which is worse than no picture, because it is the tool you
-- reach for when you already distrust your own guesses about where time goes.
--
-- This module counts depth and says so once. That is the whole value add; the
-- rest is a thin pass-through.
--
-- =============================== THE COSTS ================================
--
-- Measured in Studio, warmed, best of five interleaved rounds against an empty
-- loop of the same length:
--
--     debug.profilebegin + debug.profileend        51.6 ns per pair
--     ...with a concatenated label                 92.1 ns per pair
--     debug.setmemorycategory + reset              77.4 ns per pair
--
-- 51.6 ns is why there is NO debug-flag gate on this: for scale, one property
-- write is ~90 ns and one `task.spawn` is ~740 ns. Markers are meant to be left
-- in -- the MicroProfiler runs on live servers, and a marker you have to switch
-- on is a marker that is off when you need it.
--
-- THE ONE COST WORTH AVOIDING IS THE LABEL, not the marker. A concatenated
-- label nearly doubles the pair (51.6 -> 92.1 ns) and allocates a string every
-- frame, so `profile.open("ghost " .. id)` in a per-frame loop is paying for
-- something the profiler groups by anyway. Use a constant label per call site
-- and let the profiler aggregate.

const has_profiler = type((debug :: any).profilebegin) == "function"

-- Depth is tracked whether or not the engine profiler is present, so the
-- balance check is testable outside Roblox.
local depth = 0
local warned_underflow = false
local warned_leak = false

-- Open a scope. Returns the function that closes it.
--
-- THE RETURNED CLOSURE ALLOCATES (~35 bytes). That is deliberate and it is the
-- reason `scope` exists below: for a per-frame call site, prefer `scope`, which
-- takes the work as an argument instead, or hold one `close` outside the loop.
-- For anything coarser than per-frame the allocation is beneath notice.
-- Open a scope WITHOUT allocating anything. Pair it with `close()`.
--
-- This is the form for a per-frame call site. `open` below is friendlier and
-- allocates a closure to be friendly with; at sixty calls a second that is a
-- trade worth making deliberately rather than by default, so both exist and the
-- hot one is the plain one.
--
-- YOU OWN THE BALANCE with this pair. An early `return` between them leaks the
-- scope, which is the mistake the module is here to catch rather than one it
-- can prevent -- `frame_boundary` is how you find out you made it.
function begin(label: string)
	if has_profiler then
		(debug :: any).profilebegin(label)
	end
	depth += 1
end

function open(label: string): () -> ()
	begin(label)
	local closed = false
	return function()
		-- Idempotent: closing twice is a mistake that would otherwise unbalance
		-- everything after it, and it is an easy one to make when a close is
		-- reachable from two paths.
		if closed then
			return
		end
		closed = true
		close()
	end
end

-- Close the innermost open scope. Prefer the closure `open` hands back; this is
-- for call sites that genuinely cannot hold one.
function close()
	if depth <= 0 then
		-- The silent failure, made loud. Latched, because whatever is
		-- unbalanced is usually unbalanced on every frame, and a warning per
		-- frame buries the console and distorts the very timings being read.
		if not warned_underflow then
			warned_underflow = true
			warn "[profile] close() with no open scope -- the profile view is now misnested"
		end
		return
	end
	depth -= 1
	if has_profiler then
		(debug :: any).profileend()
	end
end

-- Profile one call. Closes the scope even if `fn` throws, and re-raises.
--
-- This is the form to reach for. It cannot leak a scope, which is the entire
-- failure this module exists to prevent, and it costs one pcall (~50 ns,
-- measured) on top of the marker pair.
function scope<A..., R...>(label: string, fn: (A...) -> R..., ...: A...): R...
	if has_profiler then
		(debug :: any).profilebegin(label)
	end
	depth += 1

	const results = table.pack(pcall(fn, ...))

	depth -= 1
	if has_profiler then
		(debug :: any).profileend()
	end

	if not results[1] then
		-- Level 0: a Luau runtime error message already carries its own
		-- `file:line:` prefix, and re-raising with a level would staple THIS
		-- file's position on top of it, pointing the reader at the profiler
		-- instead of at the code that failed.
		error(results[2], 0)
	end
	return table.unpack(results, 2, results.n)
end

-- Tag allocations made by `fn` so they show up as their own line in the
-- memory view (Developer Console -> Memory -> LuaHeap).
function memory<A..., R...>(tag: string, fn: (A...) -> R..., ...: A...): R...
	if has_profiler then
		(debug :: any).setmemorycategory(tag)
	end
	const results = table.pack(pcall(fn, ...))
	if has_profiler then
		(debug :: any).resetmemorycategory()
	end
	if not results[1] then
		error(results[2], 0)
	end
	return table.unpack(results, 2, results.n)
end

-- How many scopes are open right now. Zero at a frame boundary, or something
-- leaked.
function depth_now(): number
	return depth
end

-- Call at a frame boundary to catch a leak the same frame it happens rather
-- than a hundred frames later. Warns once and resets, so one bad frame does not
-- misnest every frame after it.
function frame_boundary()
	if depth == 0 then
		return
	end
	if not warned_leak then
		warned_leak = true
		warn(`[profile] {depth} scope(s) still open at a frame boundary -- a close was missed`)
	end
	while depth > 0 do
		close()
	end
end

return table.freeze {
	begin = begin,
	open = open,
	close = close,
	scope = scope,
	memory = memory,
	depth_now = depth_now,
	frame_boundary = frame_boundary,
	-- Whether the engine profiler is actually there. False under Lune, so a
	-- spec can assert the bookkeeping without asserting the engine calls.
	available = has_profiler,
}
