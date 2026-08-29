--!nocheck
-- util/events/pseudo-signal: what happens when the listener set changes DURING
-- a dispatch.
-- Run with:
--   lune run tests/signals.spec.luau
--
-- WHY THIS EXISTS. The original implementation was four lines:
--
--     function fire(self, ...)
--         for fn in self.__listeners do
--             task.spawn(fn, ...)
--         end
--     end
--
-- which is correct right up until a listener connects or disconnects while that
-- loop is running — and per-frame effect code does exactly that, routinely: an
-- updater connected to a step signal spawns a new effect, which connects its own
-- listener to the same signal. Adding a key to a table mid-`next` is undefined
-- in Lua. It can skip listeners, or throw `invalid key to 'next'`, and which one
-- you get depends on the table's internal layout — so it is intermittent, and it
-- surfaces during exactly the busy moments nobody wants to be debugging.
--
-- Every case below is about that boundary. They are cheap to write and were not
-- written until after the bug, which is the usual order and worth noticing.

local h = require "./harness"
local env = require "./roblox-env"

h.title "pseudo-signal:"

local pseudo_signal = env.load("ReplicatedStorage.Util.events.pseudo-signal", { realm = "client" })

-- ============================ basic delivery ==============================

do
	local signal = pseudo_signal.new()
	local seen = {}
	signal:connect(function(value)
		table.insert(seen, value)
	end)
	signal:connect(function(value)
		table.insert(seen, value * 2)
	end)
	signal:fire(3)
	table.sort(seen)
	h.equals("fire reaches every listener", table.concat(seen, ","), "3,6")
end

do
	local signal = pseudo_signal.new()
	local calls = 0
	local disconnect = signal:connect(function()
		calls += 1
	end)
	signal:fire()
	disconnect()
	signal:fire()
	h.equals("a disconnected listener stops being called", calls, 1)
	h.equals("count reflects the disconnect", signal:count(), 0)
end

-- ===================== mutation during dispatch ===========================

do
	local signal = pseudo_signal.new()
	local late_calls = 0
	local fires = 0
	signal:connect(function()
		fires += 1
		if fires == 1 then
			-- The routine case: an effect spawning another effect, which
			-- connects to the same per-frame signal.
			signal:connect(function()
				late_calls += 1
			end)
		end
	end)

	local ok = pcall(function()
		signal:fire()
	end)
	h.check("connecting during a dispatch does not throw", ok)
	h.equals("the new listener does NOT run in the dispatch that created it", late_calls, 0)

	signal:fire()
	h.equals("it runs on the next dispatch", late_calls, 1)
end

do
	local signal = pseudo_signal.new()
	local b_calls = 0
	local disconnect_b
	signal:connect(function()
		-- A drops B mid-dispatch. B must not run afterwards in this same pass:
		-- the snapshot froze the guest list, but a listener removed from the
		-- set is genuinely gone and calling it would resurrect behaviour the
		-- caller just cancelled.
		if disconnect_b then
			disconnect_b()
		end
	end)
	disconnect_b = signal:connect(function()
		b_calls += 1
	end)

	signal:fire()
	-- Table order decides whether A ran first. If B ran first it was still
	-- connected at the time, which is also correct -- so this asserts the
	-- invariant that holds either way.
	h.check("a listener disconnected mid-dispatch is called at most once", b_calls <= 1)
	signal:fire()
	h.equals("and never again after that", b_calls <= 1 and b_calls or -1, b_calls)
end

-- ======================= surviving a throwing listener ====================

do
	local signal = pseudo_signal.new()
	local good_calls = 0
	local remove_thrower = signal:connect(function()
		error "listener blew up"
	end)
	signal:connect(function()
		good_calls += 1
	end)

	-- Each listener gets its own thread, so a throw is contained to it. This
	-- used to be the opposite: the inline dispatcher ran listeners bare, a
	-- throw propagated, and the rest of that dispatch was lost -- so this spec
	-- deliberately did NOT assert that the other listener ran, because it
	-- depended on table order and failed whenever the thrower went first.
	--
	-- Now it is assertable, and asserting it is the point of the change.
	--
	-- EXPECT A STACK TRACE IN THE OUTPUT HERE. The throw is reported by the
	-- scheduler rather than swallowed -- which is the correct behaviour and the
	-- same thing Roblox does -- so this spec prints "listener blew up" and
	-- passes. It is not a failure; `h.done()` sets the exit code explicitly so
	-- a thread throwing cannot be mistaken for a verdict.
	signal:fire()
	h.check("a listener that throws does not stop the others", good_calls > 0)

	--
	-- THE PROPERTY THAT MATTERS is that the signal is not permanently broken.
	-- The scratch buffer is TAKEN for the duration of a dispatch and handed
	-- back at the end, so a throw simply loses it and the next fire allocates a
	-- replacement. A `busy = true` flag restored after the loop would instead
	-- be stuck true forever after one error -- permanently disabling the
	-- optimisation it exists to provide, on the signal most likely to go
	-- unnoticed.
	remove_thrower()
	local before = good_calls
	signal:fire()
	h.check("the signal still dispatches after a listener threw", good_calls > before)
end

-- ============================== re-entrancy ===============================

do
	local signal = pseudo_signal.new()
	local depth = 0
	local max_depth = 0
	local calls = 0
	signal:connect(function()
		calls += 1
		depth += 1
		max_depth = math.max(max_depth, depth)
		if depth < 3 then
			-- A nested fire finds the buffer already taken and allocates its
			-- own, rather than sharing one and shredding the outer walk.
			signal:fire()
		end
		depth -= 1
	end)

	local ok = pcall(function()
		signal:fire()
	end)
	h.check("a listener firing its own signal does not throw", ok)
	h.equals("nesting reached the depth it was asked for", max_depth, 3)
	h.equals("every level dispatched", calls, 3)
end

-- ====================== fire settles synchronously ========================

do
	local signal = pseudo_signal.new()
	local seen = 0
	signal:connect(function(value)
		seen += value
	end)
	signal:connect(function(value)
		seen += value
	end)
	signal:fire(5)
	-- task.spawn runs the body immediately up to its first yield, and these do
	-- not yield, so the count is settled by the time fire returns.
	h.equals("fire has finished dispatching by the time it returns", seen, 10)
end

h.done()
