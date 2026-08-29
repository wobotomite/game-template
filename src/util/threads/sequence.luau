-- An ordered series of steps that can be cancelled, and that cleans up after
-- itself when it is.
--
--   const running = sequence.run {
--       function(step)
--           const door = open_door()
--           step.on_cancel(function() close_door(door) end)
--           step.wait(1.5)
--       end,
--       function(step)
--           step.wait_until(everyone_inside, 30)
--       end,
--       function(step)
--           start_wave()
--       end,
--   }
--
--   running.cancel()   -- stops, and unwinds every step's cleanup
--
-- ========================= WHY NOT JUST task.spawn ========================
--
-- Because this is already fine, and it is what everyone writes first:
--
--   task.spawn(function()
--       open_door()
--       wait_for_everyone()
--       close_door()
--       start_wave()
--   end)
--
-- It is fine right up until the round ends in the middle of it. That coroutine
-- does not know: it closes a door on a room nobody is in and starts a wave into
-- an empty level, several seconds after the thing it belonged to stopped
-- existing. Every fix for that is the same bookkeeping — a cancelled flag,
-- checked after every wait, plus a list of things to undo — hand-rolled once
-- per sequence, and the bookkeeping is where the bugs are.
--
-- So this owns exactly two things: WHEN THE SEQUENCE STOPS, and WHAT UNDOING IT
-- MEANS. Everything else is your code, in a plain function.
--
-- ===================== WHEN TO REACH FOR THIS INSTEAD =====================
--
-- `util/extra-features/cutscene-player` is a TIMELINE: clips positioned on an
-- absolute time axis, with speed, pause, scrubbing and markers. Reach for it
-- when the moment is authored and fixed-length, and when "halfway through" is a
-- meaningful position.
--
-- This is a SEQUENCE: step N finishes, then step N+1 begins. Its length is not
-- known in advance, because a step can wait on a CONDITION rather than a
-- duration. Reach for it for gameplay that unfolds — a round, an objective, a
-- scripted encounter.
--
-- They are not layered on each other on purpose. A timeline cannot express
-- "wait until every player is inside the zone", and a sequence cannot be
-- scrubbed. A single abstraction covering both would do neither well, and its
-- users would spend their time working out which half they were in.

-- Raised out of a wait when the sequence is cancelled, so the step ABORTS
-- rather than carrying on with the rest of its body. A unique table, compared
-- by identity, so it can never collide with a real error someone raised.
--
-- This was originally "the wait returns false and you check it". That is the
-- version everybody writes and it is wrong in the one case the module exists
-- for: a step that opens a door, waits, then closes it will still close it,
-- because ignoring the return value is the default and nothing forces the
-- check. Mutation testing found it -- removing the cancellation check from
-- inside `wait` broke nothing, which meant nothing was relying on it.
const CANCELLED = table.freeze { __sequence_cancelled = true }

export type Step = {
	-- Yield for `seconds`.
	--
	-- IF THE SEQUENCE IS CANCELLED WHILE WAITING, THIS DOES NOT RETURN: it
	-- aborts the step. That is deliberate and it is the whole safety property
	-- -- a step that opens a door, waits, and closes it must not close it after
	-- the round it belonged to has ended, and "remember to check the return
	-- value" is not a property, it is a hope.
	wait: (seconds: number) -> (),
	-- Yield until `predicate` returns true, or until `timeout` seconds pass.
	-- Returns whether the predicate actually came true, so a step can branch on
	-- a timeout. Cancellation aborts the step rather than returning, as above.
	--
	-- THE TIMEOUT IS REQUIRED, and that is deliberate. A wait with no deadline
	-- is a sequence that can never end: one player who disconnects at the wrong
	-- moment, one flag nothing sets any more, and the round is stuck with
	-- nothing on screen to say why. Pick a number you would be willing to
	-- explain in a bug report.
	wait_until: (predicate: () -> boolean, timeout: number) -> boolean,
	-- Undo what this step did. Runs if the sequence is cancelled, and runs
	-- whether or not the step has finished.
	on_cancel: (cleanup: () -> ()) -> (),
	-- True until the sequence stops.
	is_running: () -> boolean,
	-- Which step this is, 1-based. For logging.
	index: number,
}

export type Handle = {
	cancel: () -> (),
	is_running: () -> boolean,
	-- Yields until the sequence finishes or is cancelled. Returns whether it
	-- ran to completion.
	wait_for_finish: () -> boolean,
}

export type Runner = (step: Step) -> ()

const POLL = 0.05

local function run(steps: { Runner }, on_error: ((index: number, err: unknown) -> ())?): Handle
	local cancelled = false
	local finished = false
	-- A STACK, not a list. Cleanups unwind newest-first because later steps are
	-- built on earlier ones: the wave spawned in step 3 has to be cleared before
	-- the arena raised in step 1 is torn down, or it is cleared into nothing.
	const cleanups: { () -> () } = {}

	local function unwind()
		for i = #cleanups, 1, -1 do
			const cleanup = cleanups[i]
			cleanups[i] = nil
			-- Spawned: these come from caller code, and one that throws must
			-- not strand the cleanups below it on the stack. That would leave
			-- exactly the half-torn-down state this whole module exists to
			-- avoid, and it would do it during the error path, where nobody is
			-- looking.
			task.spawn(function()
				const ok, err = pcall(cleanup)
				if not ok then
					warn(`[sequence] a cleanup threw: {err}`)
				end
			end)
		end
	end

	local function cancel()
		if cancelled or finished then
			return
		end
		cancelled = true
		unwind()
	end

	local function is_running(): boolean
		return not cancelled and not finished
	end

	task.spawn(function()
		for index, runner in steps do
			if cancelled then
				break
			end

			const step: Step = {
				index = index,
				is_running = is_running,
				on_cancel = function(cleanup: () -> ())
					if cancelled then
						-- Registered after the fact: the sequence is already
						-- unwinding, so run it now rather than pushing it onto
						-- a stack nothing will read again.
						task.spawn(cleanup)
						return
					end
					table.insert(cleanups, cleanup)
				end,
				wait = function(seconds: number)
					const deadline = os.clock() + seconds
					while os.clock() < deadline do
						if cancelled then
							error(CANCELLED, 0)
						end
						task.wait(POLL)
					end
					if cancelled then
						error(CANCELLED, 0)
					end
				end,
				wait_until = function(predicate: () -> boolean, timeout: number): boolean
					const deadline = os.clock() + timeout
					while os.clock() < deadline do
						if cancelled then
							error(CANCELLED, 0)
						end
						-- pcall, because a predicate is caller code evaluated on
						-- a timer: one that throws would otherwise kill the
						-- sequence thread from inside a wait, which reads as
						-- "it just stopped".
						const ok, result = pcall(predicate)
						if ok and result then
							return true
						end
						if not ok then
							warn(`[sequence] step {index} predicate threw: {result}`)
						end
						task.wait(POLL)
					end
					return false
				end,
			}

			-- A STEP THAT THROWS CANCELS THE SEQUENCE, and still unwinds.
			-- xpcall then report, rather than pcall and swallow: the error is
			-- the one signal that something is wrong, and a sequence that
			-- silently stopped halfway is indistinguishable from one that
			-- finished.
			-- The handler passes the cancel sentinel through by identity and
			-- only builds a traceback for a real error. Doing it the other way
			-- round -- stringifying everything and matching on the text -- would
			-- make a step that raised the same words look like a cancellation.
			const ok, err = xpcall(runner, function(raised: any)
				if raised == CANCELLED then
					return raised
				end
				return debug.traceback(tostring(raised), 2)
			end, step)
			if not ok and err == CANCELLED then
				-- Stopped on purpose, mid-step. `cancel` has already unwound.
				return
			end
			if not ok then
				if on_error then
					task.spawn(on_error, index, err)
				else
					warn(`[sequence] step {index} threw: {err}`)
				end
				cancel()
				return
			end
		end

		if not cancelled then
			-- Finished cleanly. THE CLEANUPS ARE NOT RUN: `on_cancel` means
			-- undo-if-interrupted, not teardown. A door the sequence opened on
			-- purpose stays open when it completes; that is the whole
			-- difference between finishing and being stopped.
			finished = true
		end
	end)

	return table.freeze {
		cancel = cancel,
		is_running = is_running,
		wait_for_finish = function(): boolean
			while is_running() do
				task.wait(POLL)
			end
			return finished
		end,
	}
end

return table.freeze {
	run = run,
	CANCELLED = CANCELLED,
}
