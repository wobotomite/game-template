--!nocheck
-- util/threads/sequence: what happens when a running sequence is stopped.
-- Run with:
--   lune run tests/sequence.spec.luau
--
-- WHY THIS EXISTS. The module owns exactly two things — when a sequence stops,
-- and what undoing it means — and both are only observable at the moment
-- something goes wrong. A sequence that runs to completion in a test proves
-- almost nothing; every case below interrupts one.
--
-- The unwind ORDER is the part most likely to be got wrong and least likely to
-- be noticed: cleanups have to run newest-first, because later steps are built
-- on earlier ones. Reversed, a wave is cleared into an arena that was already
-- torn down, and the symptom is a nil index somewhere unrelated.

local h = require "./harness"
local env = require "./roblox-env"
-- The spec is a plain Lune script, so `task` is not a global here the way it is
-- inside a module loaded through roblox-env.
local task = require "@lune/task"

h.title "sequence:"

local sequence = env.load "ReplicatedStorage.Util.threads.sequence"

-- The runner yields on a real clock, so cases that need progress wait a few
-- poll intervals. Kept small: the module polls at 0.05s.
local function settle(seconds: number?)
	local deadline = os.clock() + (seconds or 0.2)
	while os.clock() < deadline do
		task.wait(0.02)
	end
end

-- ============================ it runs in order ============================

do
	local order = {}
	local handle = sequence.run {
		function()
			table.insert(order, 1)
		end,
		function()
			table.insert(order, 2)
		end,
		function()
			table.insert(order, 3)
		end,
	}
	settle()
	h.equals("steps run in order", table.concat(order, ","), "1,2,3")
	h.check("a finished sequence is no longer running", not handle.is_running())
end

-- ===================== cancelling stops the next step =====================

do
	local reached = { false, false }
	local handle
	handle = sequence.run {
		function(step)
			reached[1] = true
			step.wait(5)
		end,
		function()
			reached[2] = true
		end,
	}
	settle(0.15)
	handle.cancel()
	settle()

	h.check("the first step ran", reached[1])
	h.check("the step after the cancel never ran", not reached[2])
	h.check("a cancelled sequence is not running", not handle.is_running())
end

-- ========================= cleanups, and their order ======================

do
	local unwound = {}
	local handle
	handle = sequence.run {
		function(step)
			step.on_cancel(function()
				table.insert(unwound, "first")
			end)
			step.wait(0.05)
		end,
		function(step)
			step.on_cancel(function()
				table.insert(unwound, "second")
			end)
			step.wait(5)
		end,
	}
	settle(0.3)
	handle.cancel()
	settle()

	h.equals("every registered cleanup ran", #unwound, 2)
	-- NEWEST FIRST. The second step's work is built on the first step's, so it
	-- has to come apart in the opposite order to how it went together.
	h.equals("cleanups unwind newest-first", table.concat(unwound, ","), "second,first")
end

do
	-- Finishing is not cancelling. `on_cancel` means undo-if-interrupted, not
	-- teardown -- a door a sequence opened on purpose stays open when it
	-- completes. Running cleanups on success would make every sequence undo
	-- itself the moment it worked.
	local undone = false
	local handle = sequence.run {
		function(step)
			step.on_cancel(function()
				undone = true
			end)
		end,
	}
	settle()
	h.check("a sequence that completes does NOT run its cleanups", not undone)
	h.check("and reports as finished", handle.wait_for_finish())
end

do
	-- Registering a cleanup after cancellation must still run it, or a step
	-- that was mid-setup when the sequence stopped leaks whatever it had just
	-- built.
	local late_ran = false
	local handle
	handle = sequence.run {
		function(step)
			step.wait(0.05)
			handle.cancel()
			step.on_cancel(function()
				late_ran = true
			end)
		end,
	}
	settle(0.4)
	h.check("a cleanup registered after the cancel still runs", late_ran)
end

-- =================== a cancelled wait ABORTS the step =====================

do
	-- The property the whole module exists for. A step that opens a door, waits,
	-- then closes it must NOT close it once the sequence has been stopped -- and
	-- "the wait returns false, so check it" is not a property, it is a hope.
	--
	-- This case exists because mutation testing found its absence: removing the
	-- cancellation check from inside `wait` broke nothing, which meant nothing
	-- was relying on it.
	local closed_after_cancel = false
	local handle
	handle = sequence.run {
		-- 0.4s, not 5s. The settle below has to outlast an UNGUARDED wait, or
		-- the case passes simply because the step is still waiting -- which is
		-- how the first version of this test passed against the very mutation
		-- it was written to catch.
		function(step)
			step.wait(0.4)
			-- Deliberately NOT guarded. If the wait returned instead of
			-- aborting, this runs, and that is the bug.
			closed_after_cancel = true
		end,
	}
	settle(0.1)
	handle.cancel()
	settle(0.8)
	h.check("code after a cancelled wait does not run", not closed_after_cancel)
end

do
	-- Same for the conditional wait.
	local ran_on = false
	local handle
	handle = sequence.run {
		function(step)
			step.wait_until(function()
				return false
			end, 0.4)
			ran_on = true
		end,
	}
	settle(0.1)
	handle.cancel()
	settle(0.8)
	h.check("code after a cancelled wait_until does not run", not ran_on)
end

-- ============================== wait_until ================================

do
	local flag = false
	local saw = nil
	sequence.run {
		function(step)
			saw = step.wait_until(function()
				return flag
			end, 5)
		end,
	}
	settle(0.15)
	task.spawn(function()
		flag = true
	end)
	settle(0.3)
	h.check("wait_until returns true when the predicate comes true", saw == true)
end

do
	local saw = nil
	sequence.run {
		function(step)
			saw = step.wait_until(function()
				return false
			end, 0.1)
		end,
	}
	settle(0.4)
	h.check("wait_until gives up at its timeout and says so", saw == false)
end

do
	-- A predicate is caller code on a timer. One that throws must not kill the
	-- sequence from inside a wait, which would read as "it just stopped".
	local reached_next = false
	sequence.run {
		function(step)
			step.wait_until(function()
				error "predicate blew up"
			end, 0.1)
		end,
		function()
			reached_next = true
		end,
	}
	settle(0.5)
	h.check("a throwing predicate does not kill the sequence", reached_next)
end

-- ========================== a step that throws ============================

do
	local reported_index = nil
	local reached_next = false
	local cleaned = false
	local handle = sequence.run({
		function(step)
			step.on_cancel(function()
				cleaned = true
			end)
			error "step blew up"
		end,
		function()
			reached_next = true
		end,
	}, function(index)
		reported_index = index
	end)
	settle()

	h.equals("the error handler is told which step threw", reported_index, 1)
	h.check("a throwing step stops the sequence", not reached_next)
	h.check("and it still unwinds", cleaned)
	h.check("the sequence is no longer running", not handle.is_running())
end

-- ============================== idempotence ===============================

do
	local unwound = 0
	local handle
	handle = sequence.run {
		function(step)
			step.on_cancel(function()
				unwound += 1
			end)
			step.wait(5)
		end,
	}
	settle(0.15)
	handle.cancel()
	handle.cancel()
	handle.cancel()
	settle()
	h.equals("cancelling repeatedly unwinds exactly once", unwound, 1)
end

h.done()
