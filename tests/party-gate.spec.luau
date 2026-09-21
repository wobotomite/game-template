--!nocheck
-- server/players/party-gate: the failsafe, which is the part whose absence is fatal.
-- Run with:
--   lune run tests/party-gate.spec.luau
--
-- WHAT IS AND IS NOT COVERED, up front. `ready_count` walks
-- `Players:GetPlayers()`, which does not exist outside Roblox, so the
-- everyone-arrived path cannot be exercised here -- a stubbed Players service
-- reports an empty server no matter who was marked ready.
--
-- What CAN be exercised is the timeout, and that is the case worth having.
-- The gate opening late is a bad minute; the gate never opening is a dead
-- session for everybody, and the difference between those two is one deadline.
-- `wait_for_party` returning FALSE is also the signal a game should watch: a
-- rising opened-on-timeout rate is how you find out the ready event is being
-- lost, rather than reading it in a bug report that says "the game was stuck".

local h = require "./harness"
local env = require "./roblox-env"

h.title "party gate:"

local gate = env.load("ServerScriptService.Server.players.party-gate", { realm = "server" })

do
	local p1, p2 = { Name = "a" }, { Name = "b" }
	gate.reset()
	h.check("nobody is ready to begin with", not gate.is_ready(p1))

	gate.mark_ready(p1)
	h.check("marking makes a player ready", gate.is_ready(p1))
	h.check("and does not mark anyone else", not gate.is_ready(p2))

	-- A client that reconnects mid-gate may well send twice.
	gate.mark_ready(p1)
	h.check("marking twice is harmless", gate.is_ready(p1))

	gate.reset()
	h.check("reset clears readiness", not gate.is_ready(p1))
end

do
	-- THE FAILSAFE. A player whose client crashed, or whose teleport half
	-- failed, never reports ready. Without a deadline the whole party waits on
	-- them forever.
	gate.reset()
	gate.configure {
		expected = function()
			return 4
		end,
		timeout = 0.3,
		interval = 0.05,
	}

	local began = os.clock()
	local completed = gate.wait_for_party()
	local took = os.clock() - began

	h.check("the gate opens even though nobody reported ready", took >= 0.25)
	h.check("and it does not hang past its deadline", took < 3)
	-- The return value is the difference between "started properly" and
	-- "started on the timeout", and a game that never checks it cannot tell
	-- those apart in telemetry.
	h.equals("it reports that it did NOT complete", completed, false)
end

do
	-- `expected` returning 0 means "not known yet" -- teleport data has not
	-- arrived. The gate must keep waiting rather than opening on a vacuous
	-- match of 0 ready against 0 expected.
	gate.reset()
	gate.configure {
		expected = function()
			return 0
		end,
		timeout = 0.3,
		interval = 0.05,
	}
	local began = os.clock()
	local completed = gate.wait_for_party()
	h.check("an unknown party size does not open the gate immediately", os.clock() - began >= 0.25)
	h.equals("and it opens on the failsafe instead", completed, false)
end

do
	-- The progress callback drives a status sign. If it never fires, the
	-- players see a frozen screen for the whole wait -- which is the same
	-- experience as a hang, from their side.
	gate.reset()
	local reports = 0
	gate.configure {
		expected = function()
			return 2
		end,
		timeout = 0.25,
		interval = 0.05,
		on_progress = function()
			reports += 1
		end,
	}
	gate.wait_for_party()
	h.check(`on_progress is called while waiting ({reports} times)`, reports >= 2)
end

do
	-- THE EARLY OPEN'S VACUOUS GUARD. `stall` opens the gate once everyone
	-- PRESENT is ready and nobody new has arrived for that long -- which, in an
	-- empty server, is trivially true of nobody. `present > 0` is what stops it,
	-- and without that guard this configuration would open on the first poll
	-- with zero players ready and report a completed party.
	--
	-- The other half of the early open -- that it fires when players ARE present
	-- and ready -- needs `Players:GetPlayers()` to report a roster, which a
	-- stubbed service cannot. Same blind spot as `ready_count` above, and the
	-- same honest answer: what is testable here is the guard.
	gate.reset()
	gate.configure {
		expected = function()
			return 4
		end,
		timeout = 0.3,
		interval = 0.05,
		stall = 0.01,
	}
	local began = os.clock()
	local completed = gate.wait_for_party()
	h.check("an empty server does not satisfy the stall early-open", os.clock() - began >= 0.25)
	h.equals("so the gate still opens on the failsafe", completed, false)
end

h.done()
