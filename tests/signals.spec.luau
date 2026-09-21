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

	-- Each listener runs under its own `pcall`, so a throw is contained to it.
	-- The first dispatcher ran listeners bare, a throw propagated, and the rest
	-- of that dispatch was lost -- so this spec deliberately did NOT assert that
	-- the other listener ran, because it depended on table order and failed
	-- whenever the thrower went first. The second gave each listener a thread,
	-- which contained the throw and cost a coroutine per listener per fire.
	-- `pcall` keeps the containment and drops the allocation.
	--
	-- EXPECT ONE `[warn]` LINE IN THE OUTPUT HERE. The throw is reported once
	-- per listener rather than swallowed, so this spec prints "listener blew up"
	-- and passes. It is not a failure.
	signal:fire()
	h.check("a listener that throws does not stop the others", good_calls > 0)

	-- THE PROPERTY THAT MATTERS is that the signal is not permanently broken.
	-- Dispatch keeps a re-entrancy DEPTH counter, raised around the walk and
	-- lowered after it, and `pcall` contains a listener throw -- so the loop
	-- always reaches the decrement and the counter cannot be left stuck above
	-- zero. If it could, every later fire would believe it was nested forever
	-- and allocate a throwaway order table on each one: the exact cost the
	-- cached order exists to avoid, on the signal most likely to go unnoticed.
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
			-- A nested fire sees depth > 0. If it has to rebuild the order at
			-- all it builds into a throwaway table, rather than clearing the
			-- array the outer walk is still indexing and shredding it.
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
	-- Listeners are called in place, so the count is settled by the time fire
	-- returns. (It was already true under `task.spawn`, which runs a body up to
	-- its first yield -- but only because these do not yield.)
	h.equals("fire has finished dispatching by the time it returns", seen, 10)
end

-- ================================ wait() ==================================

do
	local signal = pseudo_signal.new()
	local order = {}
	local got_a, got_b

	-- The waiter's continuation must run AFTER every listener of the fire that
	-- woke it. Resumed inline it ran between two listeners, and whatever it did
	-- next -- fire again, destroy what the others were about to read -- landed
	-- in the middle of their dispatch.
	-- A bare coroutine, not `task.spawn`: `wait()` parks on `coroutine.yield`
	-- and is woken by `coroutine.resume`, so no scheduler is involved.
	coroutine.wrap(function()
		got_a, got_b = signal:wait()
		table.insert(order, "waiter")
	end)()
	signal:connect(function()
		table.insert(order, "listener")
	end)

	signal:fire("x", 7)
	h.equals("a waiter receives what was fired", `{got_a},{got_b}`, "x,7")
	h.equals("and is resumed after the listeners of that fire", order[#order], "waiter")
	h.equals("a waiter is a one-shot: it leaves no listener behind", signal:count(), 1)

	signal:fire("y", 8)
	h.equals("a second fire does not resume it again", `{got_a},{got_b}`, "x,7")
end

h.done()
