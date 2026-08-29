--!nocheck
-- util/pathfinding: the decisions, not the routing.
-- Run with:
--   lune run tests/pathfinding.spec.luau
--
-- WHAT CAN AND CANNOT BE TESTED HERE, said up front because the gap is real.
--
-- `PathfindingService` does not exist outside Roblox, so nothing below exercises
-- an actual navmesh. What it does exercise is the part that goes wrong in
-- practice: WHEN the follower recomputes, when it advances a waypoint, when it
-- decides it is stuck. Those are four rules on a clock, they are where the bugs
-- live, and they regress silently — a throttle that stops throttling looks
-- identical until a log fills up.
--
-- The seam is `options.route`, which exists for a game with its own navmesh or
-- waypoint graph and doubles as the injection point here. `compute` itself is
-- guard clauses around an engine call; only its input guard is checkable, and
-- that case is below.

local h = require "./harness"
local env = require "./roblox-env"
-- Plain Lune script: Roblox datatypes are not globals here the way they are
-- inside a module loaded through roblox-env.
local roblox = require "@lune/roblox"
local Vector3 = roblox.Vector3
local Enum = roblox.Enum

h.title "pathfinding:"

local pathfinding = env.load "ReplicatedStorage.Util.pathfinding"

-- A humanoid stand-in. `follow` only ever touches RootPart.Position, MoveTo and
-- Jump, so this is the whole surface.
local function fake_humanoid()
	local moved_to: { Vector3 } = {}
	local self
	self = {
		RootPart = { Position = Vector3.new(0, 0, 0) },
		Jump = false,
		MoveTo = function(_self, position: Vector3)
			table.insert(moved_to, position)
		end,
		-- test-only handles
		moves = moved_to,
		place = function(x: number, z: number)
			self.RootPart.Position = Vector3.new(x, 0, z)
		end,
	}
	return self
end

-- A router that hands back a fixed straight line and counts its calls.
local function counting_router(points: { Vector3 })
	local calls = 0
	return function()
		calls += 1
		local waypoints = {}
		for _, p in points do
			table.insert(waypoints, { Position = p, Action = Enum.PathWaypointAction.Walk })
		end
		return { waypoints = waypoints, jumped = false, status = "Success" }, "Success"
	end, function()
		return calls
	end
end

-- ============================== the throttle ==============================

do
	local humanoid = fake_humanoid()
	local router, call_count = counting_router {
		Vector3.new(0, 0, 0),
		Vector3.new(0, 0, 40),
	}
	local agent = pathfinding.follow(humanoid, { route = router, recompute_interval = 10 })

	-- Ten ticks with a goal that keeps moving well past the drift threshold.
	-- Without the throttle this is ten routes; with it, one.
	for i = 1, 10 do
		agent.move_to(Vector3.new(i * 50, 0, 0))
	end
	h.equals("a moving goal inside the interval recomputes once", call_count(), 1)
end

do
	local humanoid = fake_humanoid()
	local router, call_count = counting_router {
		Vector3.new(0, 0, 0),
		Vector3.new(0, 0, 40),
	}
	-- Interval and refresh both effectively off, so only DRIFT can trigger a
	-- recompute.
	local agent = pathfinding.follow(humanoid, {
		route = router,
		recompute_interval = 0,
		refresh_seconds = 1e6,
		goal_drift = 8,
	})

	agent.move_to(Vector3.new(0, 0, 100))
	local after_first = call_count()
	-- A goal that has barely moved is the SAME goal. A chasing agent's target
	-- moves every frame; treating that as a new goal is the unthrottled case
	-- with extra steps.
	for _ = 1, 5 do
		agent.move_to(Vector3.new(1, 0, 100))
	end
	h.equals("a goal inside the drift threshold does not recompute", call_count(), after_first)

	agent.move_to(Vector3.new(50, 0, 100))
	h.check("a goal past the drift threshold does", call_count() > after_first)
end

-- =========================== waypoint advance =============================

do
	local humanoid = fake_humanoid()
	-- Waypoint 1 is at -10, not at the agent's feet. That is the REAL case:
	-- ComputeAsync snaps the start onto the navmesh, which can be several studs
	-- from where the agent actually is -- sometimes backwards.
	--
	-- The first version of this case put waypoint 1 at (0,0,0), directly under
	-- the agent, where the advance loop skipped it regardless. So the mutation
	-- "start at waypoint 1" changed nothing and the case passed. Passing for
	-- the wrong reason again, and in the same shape as the sequence spec's
	-- timing bug: the fixture was too kind to the code.
	local router = counting_router {
		Vector3.new(0, 0, -10),
		Vector3.new(0, 0, 10),
		Vector3.new(0, 0, 20),
	}
	local agent = pathfinding.follow(humanoid, { route = router, waypoint_range = 3 })

	agent.move_to(Vector3.new(0, 0, 20))
	-- Starting at waypoint 1 walks the agent BACKWARDS onto the snap point
	-- before setting off, which reads as a stutter at every recompute.
	h.equals("the follower skips waypoint 1", humanoid.moves[#humanoid.moves].Z, 10)

	humanoid.place(0, 9)
	agent.move_to(Vector3.new(0, 0, 20))
	h.equals("reaching a waypoint advances to the next", humanoid.moves[#humanoid.moves].Z, 20)
end

do
	-- A target off the navmesh -- airborne, or in geometry that has not streamed
	-- in -- has no route, and the agent still has to try. Standing still is the
	-- one wrong answer.
	local humanoid = fake_humanoid()
	local agent = pathfinding.follow(humanoid, {
		route = function()
			return nil, "NoPath"
		end,
	})
	local pathing = agent.move_to(Vector3.new(0, 0, 60))
	h.check("no route means it walks straight at the goal", #humanoid.moves == 1)
	h.equals("and it says it is not pathing", pathing, false)
	h.equals("and reports why", agent.last_status(), "NoPath")
end

-- ============================== input guard ===============================

do
	-- The one part of `compute` that is checkable without the engine. A NaN
	-- reaching the router means something upstream divided by zero, and the
	-- useful report is that, not a traceback inside a Roblox service.
	local nan = 0 / 0
	local result, status = pathfinding.compute(Vector3.new(0, 0, 0), Vector3.new(nan, nan, nan))
	h.equals("a NaN target is refused rather than passed to the engine", result, nil)
	h.equals("and named", status, "NaN")
end

-- ======================= blocked routes and recovery ======================
--
-- The failure this section exists for: a door shuts across a computed route.
-- Nothing about the waypoints changes, so the follower happily keeps walking
-- into it, and the first sign of trouble is the stuck detector a second and a
-- half later. `Path.Blocked` is the only notification the engine gives, and it
-- gives it once.

-- A router whose routes can be blocked on demand, and which counts the
-- teardown -- because a subscription per route that is never disconnected is a
-- leak measured in "one per recompute, several times a second, forever".
local function blockable_router(points: { Vector3 }, status: string?)
	local state = { calls = 0, disconnects = 0, destroys = 0, listeners = {} }
	local router = function()
		state.calls += 1
		local waypoints = {}
		for _, point in points do
			table.insert(waypoints, { Position = point, Action = Enum.PathWaypointAction.Walk })
		end
		local my_index = state.calls
		return {
			waypoints = waypoints,
			jumped = false,
			status = status or "Success",
			partial = (status ~= nil and status ~= "Success"),
			on_blocked = function(callback)
				state.listeners[my_index] = callback
				return function()
					state.listeners[my_index] = nil
					state.disconnects += 1
				end
			end,
			destroy = function()
				state.destroys += 1
			end,
		},
			status or "Success"
	end
	return router, state
end

local function fake_clock()
	local t = 0
	return function()
		return t
	end, function(by: number)
		t += by
	end
end

do
	-- Blocked AHEAD of the agent retires the route.
	local humanoid = fake_humanoid()
	local router, state = blockable_router { Vector3.new(0, 0, 0), Vector3.new(0, 0, 40) }
	local now, advance = fake_clock()
	local agent = pathfinding.follow(humanoid, {
		route = router,
		clock = now,
		recompute_interval = 1,
		refresh_seconds = 1e6,
		-- The agent deliberately holds position here while the clock advances,
		-- which is precisely what the stuck detector is for. It firing would
		-- clear the route for its OWN reasons and quietly invalidate every
		-- assertion below about WHY the route was dropped.
		stuck_after = 1e6,
	})

	agent.move_to(Vector3.new(0, 0, 40))
	h.equals("one route to begin with", state.calls, 1)
	h.check("a route is being followed", agent.is_pathing())

	-- The engine reports the blockage at a waypoint ahead of us.
	local fire = state.listeners[1]
	h.check("the follower subscribed to Blocked", fire ~= nil)
	fire(5)

	advance(2)
	agent.move_to(Vector3.new(0, 0, 40))
	h.equals("a blockage ahead forces a recompute", state.calls, 2)
	h.equals("and the blocked route was disconnected", state.disconnects, 1)
	h.equals("and its Path destroyed", state.destroys, 1)
end

do
	-- Blocked BEHIND is somebody else's problem. Reacting to it throws away a
	-- good route -- repeatedly, for an agent walking away through a door that
	-- is closing behind it.
	local humanoid = fake_humanoid()
	local router, state = blockable_router {
		Vector3.new(0, 0, 0),
		Vector3.new(0, 0, 10),
		Vector3.new(0, 0, 20),
		Vector3.new(0, 0, 30),
	}
	local now, advance = fake_clock()
	local agent = pathfinding.follow(humanoid, {
		route = router,
		clock = now,
		recompute_interval = 1,
		refresh_seconds = 1e6,
		goal_drift = 1e6,
		stuck_after = 1e6, -- see the note above; the agent holds position here too
	})

	agent.move_to(Vector3.new(0, 0, 30))
	-- Walk ONTO waypoint 2 so the follower advances past it.
	--
	-- Standing at z=21 does NOT do this, which is worth knowing: the follower
	-- advances only when it comes within `waypoint_range` of the CURRENT
	-- waypoint, so an agent that overshoots -- knocked, or moving fast -- keeps
	-- aiming at a waypoint it has already passed. This fixture originally stood
	-- at 21 and asserted waypoint 2 was behind it; it was not, and the module
	-- was right to treat a blockage there as ahead.
	humanoid.place(0, 10)
	advance(0.1)
	agent.move_to(Vector3.new(0, 0, 30))
	local before = state.calls

	state.listeners[1](2) -- a waypoint now behind the agent
	advance(2)
	agent.move_to(Vector3.new(0, 0, 30))
	h.equals("a blockage behind the agent is ignored", state.calls, before)
	h.check("and the route is still being followed", agent.is_pathing())
end

-- ============================= partial routes =============================

do
	-- A route to the closest reachable point beats standing still AND beats
	-- walking in a straight line into whatever is in the way.
	local humanoid = fake_humanoid()
	local router = blockable_router({ Vector3.new(0, 0, 0), Vector3.new(0, 0, 20) }, "ClosestNoPath")
	local now = fake_clock()
	local agent = pathfinding.follow(humanoid, { route = router, clock = now })

	local following = agent.move_to(Vector3.new(0, 0, 100))
	h.check("a partial route is followed", following)
	h.check("and is flagged as partial", agent.is_partial())
	h.check("the agent was sent at a waypoint, not the goal", #humanoid.moves > 0)
	h.equals("and not straight at the unreachable goal", humanoid.moves[#humanoid.moves].Z, 20)
end

-- ======================== backoff on repeated failure =====================

do
	-- An unreachable goal used to mean a compute every recompute_interval,
	-- forever, each one logging. The backoff is what keeps a shuffling agent
	-- from burying the console.
	local humanoid = fake_humanoid()
	local calls = 0
	local failing = function()
		calls += 1
		return nil, "NoPath"
	end
	local now, advance = fake_clock()
	local agent = pathfinding.follow(humanoid, {
		route = failing,
		clock = now,
		recompute_interval = 1,
		max_recompute_interval = 8,
		refresh_seconds = 1e6,
	})

	agent.move_to(Vector3.new(0, 0, 50))
	h.equals("the first attempt happens", calls, 1)
	h.equals("and is counted as a failure", agent.failures(), 1)

	-- Second attempt now waits 2s, not 1s.
	advance(1.5)
	agent.move_to(Vector3.new(0, 0, 50))
	h.equals("a retry inside the backed-off interval is refused", calls, 1)

	advance(1)
	agent.move_to(Vector3.new(0, 0, 50))
	h.equals("and allowed once it has elapsed", calls, 2)
	h.equals("failures keep counting", agent.failures(), 2)
end

do
	-- ...and one success clears it, or the agent stays sluggish long after the
	-- door it was waiting on opened.
	local humanoid = fake_humanoid()
	local ok_router, state = blockable_router { Vector3.new(0, 0, 0), Vector3.new(0, 0, 20) }
	local mode = "fail"
	local router = function(from, to, o)
		if mode == "fail" then
			return nil, "NoPath"
		end
		return ok_router(from, to, o)
	end
	local now, advance = fake_clock()
	local agent = pathfinding.follow(humanoid, {
		route = router,
		clock = now,
		recompute_interval = 1,
		refresh_seconds = 1e6,
	})

	agent.move_to(Vector3.new(0, 0, 50))
	advance(3)
	agent.move_to(Vector3.new(0, 0, 50))
	h.check("failures accumulated", agent.failures() >= 2)

	mode = "ok"
	advance(9)
	agent.move_to(Vector3.new(0, 0, 50))
	h.equals("a success resets the backoff", agent.failures(), 0)
end

-- ============================== stuck recovery ============================

do
	-- THE BUG THIS PINS. Stuck was judged by comparing one tick's displacement
	-- against a threshold that grew with how long the agent had been slow, so
	-- an agent stuck for a second needed to cover a full stud in a single frame
	-- to count as moving -- it could enter the stuck state and not leave it
	-- under its own power.
	local humanoid = fake_humanoid()
	local router = blockable_router { Vector3.new(0, 0, 0), Vector3.new(0, 0, 40) }
	local now, advance = fake_clock()
	local jumped = false
	local agent = pathfinding.follow(humanoid, {
		route = router,
		clock = now,
		recompute_interval = 1e6,
		refresh_seconds = 1e6,
		stuck_speed = 1,
		stuck_after = 1,
		on_stuck = function()
			jumped = true
			return true
		end,
	})

	agent.move_to(Vector3.new(0, 0, 40))
	-- Sit still for a while, but not long enough to fire.
	for _ = 1, 5 do
		advance(0.1)
		agent.move_to(Vector3.new(0, 0, 40))
	end
	h.check("not yet declared stuck", not jumped)

	-- Now MOVE, properly, for LONGER THAN stuck_after. The length matters: a
	-- shorter moving phase passes whether or not the window actually clears,
	-- because the accumulator simply has not reached the threshold yet. At 2s
	-- against a 1s threshold, "not stuck" can only mean the movement reset it.
	-- Found by mutation -- deleting the reset left this green at five ticks.
	for i = 1, 20 do
		advance(0.1)
		humanoid.place(0, i * 5)
		agent.move_to(Vector3.new(0, 0, 40))
	end
	h.check("moving again clears the stuck accumulation", not jumped)

	-- And stopping dead for longer than stuck_after does fire it.
	for _ = 1, 15 do
		advance(0.1)
		agent.move_to(Vector3.new(0, 0, 40))
	end
	h.check("stopping for longer than stuck_after fires the handler", jumped)
end

-- ================================ teardown ================================

do
	local humanoid = fake_humanoid()
	local router, state = blockable_router { Vector3.new(0, 0, 0), Vector3.new(0, 0, 40) }
	local now = fake_clock()
	local agent = pathfinding.follow(humanoid, { route = router, clock = now })
	agent.move_to(Vector3.new(0, 0, 40))
	h.equals("nothing released while the route is live", state.destroys, 0)
	agent.stop()
	h.equals("stop disconnects the Blocked subscription", state.disconnects, 1)
	h.equals("stop destroys the Path", state.destroys, 1)
end

-- ========================= options reach the router =======================

do
	-- `follow` forwarded exactly two fields for a while, so a walk-only route
	-- could not be asked for, the candidate retries could not be turned off,
	-- and the cache ran on `os.clock` while the follower ran on an injected one
	-- -- two clocks inside one agent, and the cache expiring on a timeline the
	-- throttle knew nothing about.
	local humanoid = fake_humanoid()
	local seen: any = nil
	local router = function(_from, _to, options)
		seen = options
		return nil, "NoPath"
	end
	local now = fake_clock()
	local agent = pathfinding.follow(humanoid, {
		route = router,
		clock = now,
		agent_radius = 6,
		allow_jump_retry = false,
		retry_candidates = false,
		cache_ttl = 9,
	})
	agent.move_to(Vector3.new(0, 0, 40))

	h.check("the router was called", seen ~= nil)
	h.equals("agent_radius reaches it", seen.agent_radius, 6)
	h.equals("allow_jump_retry reaches it", seen.allow_jump_retry, false)
	h.equals("retry_candidates reaches it", seen.retry_candidates, false)
	h.equals("cache tuning reaches it", seen.cache_ttl, 9)
	h.equals("and it shares the follower's clock", seen.clock, now)
end

do
	-- A cached route must never outlive the interval on which the follower
	-- re-anchors. If it does, the re-anchor -- whose entire job is replacing a
	-- route computed from where the agent USED to be -- is handed back the
	-- route it was trying to replace, and the staleness the cache introduces
	-- silently becomes the staleness of the whole system.
	local humanoid = fake_humanoid()
	local seen: any = nil
	local router = function(_from, _to, options)
		seen = options
		return nil, "NoPath"
	end
	local now = fake_clock()
	local agent = pathfinding.follow(humanoid, { route = router, clock = now, refresh_seconds = 2 })
	agent.move_to(Vector3.new(0, 0, 40))
	h.equals("cache_ttl defaults to the re-anchor interval", seen.cache_ttl, 2)
end

-- ================================ arrival =================================

do
	-- Standing on the goal is not being stuck. Observed live: an agent that had
	-- reached its goal and was still being driven called `on_stuck` ten times in
	-- twelve seconds -- with the stock handler, a hop every 1.5 s, forever.
	local humanoid = fake_humanoid()
	local router = blockable_router { Vector3.new(0, 0, 0), Vector3.new(0, 0, 40) }
	local now, advance = fake_clock()
	local stuck = 0
	local agent = pathfinding.follow(humanoid, {
		route = router,
		clock = now,
		refresh_seconds = 1e6,
		stuck_after = 1,
		arrive_range = 4,
		on_stuck = function()
			stuck += 1
			return true
		end,
	})

	-- Park the agent ON the goal and keep driving it, well past stuck_after.
	local GOAL = Vector3.new(0, 0, 40)
	humanoid.place(0, 40)
	for _ = 1, 40 do
		advance(0.1)
		agent.move_to(GOAL)
	end
	h.check("an arrived agent reports it", agent.has_arrived())
	h.equals("and is never declared stuck", stuck, 0)

	-- Move it away and stop dead: now it IS stuck, and must still be caught.
	humanoid.place(0, -60)
	for _ = 1, 40 do
		advance(0.1)
		agent.move_to(GOAL)
	end
	h.check("an agent stopped short of the goal still is", stuck > 0)
	h.check("and no longer reports arrival", not agent.has_arrived())
end

h.done()
