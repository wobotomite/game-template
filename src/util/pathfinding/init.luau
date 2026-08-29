const compute = require(script.compute)
const cache = require(script.cache)

-- Drives a Humanoid along a navmesh route, and keeps driving it when the route
-- goes stale.
--
--   const agent = pathfinding.follow(humanoid)
--   agent.move_to(target_position)   -- call repeatedly; it recomputes as needed
--   agent.stop()
--
-- `move_to` is meant to be called every tick with a live target. It does the
-- deciding: whether the existing route still applies, whether enough time has
-- passed to recompute, whether the agent is stuck.
--
-- ==================== THE FOUR RULES NOBODY REMEMBERS =====================
--
-- **THROTTLE THE RECOMPUTE.** Without a minimum interval, an agent that cannot
-- reach its goal recomputes every tick forever — and `ComputeAsync` failures
-- log. In the game this came from, a bot shuffling against a wall produced a
-- console full of pathfinding errors that buried everything else in it. The
-- throttle is not an optimisation; it is what keeps the log readable.
--
-- **RE-ANCHOR A LIVE ROUTE PERIODICALLY.** A route is computed from where you
-- were. Follow it long enough — pushed off course, knocked back, walking a
-- moving platform — and the waypoints describe a journey you are no longer on.
-- Recomputing from where you ACTUALLY are, on a slow timer, costs one path and
-- fixes the whole class.
--
-- **RECOMPUTE WHEN THE GOAL MOVES, not when the goal changes.** A chasing agent
-- has a target that moves every frame; treating any change as a new goal is the
-- unthrottled case again. A drift threshold is the difference.
--
-- **NOTHING TELLS YOU A ROUTE WENT BAD, SO RE-ANCHOR ON A TIMER.** When a door
-- shuts across a computed route the waypoints do not change, the humanoid keeps
-- walking, and the agent grinds against the obstruction looking like broken AI.
-- `Path.Blocked` is documented for exactly this and the follower does subscribe
-- to it -- but it DID NOT FIRE in testing, in either Edit or a running Server,
-- five seconds after a computed route was sealed with a colliding part. Treat
-- it as a bonus, not a mechanism.
--
-- What actually recovers the agent is the re-anchor above: recomputing from
-- where it really is, once a second by default. Proven on live geometry -- a
-- route through the near doorway became a route around by the far one. So the
-- worst case for a shut door is `refresh_seconds`, and that number, not the
-- Blocked signal, is the one to tune if an agent looks slow to react.
--
-- **A STUCK AGENT NEEDS A DIFFERENT ANSWER, not another path.** If the route is
-- fine and the agent is not moving, computing the same route again changes
-- nothing. Something has to break the symmetry — a jump, a sidestep — and that
-- is the last resort rather than the first.
--
-- ====================== AND ONE THAT IS NOT ABOUT PATHS ===================
--
-- A wandering agent must HOLD its goal. Re-rolling a random destination every
-- tick leaves it shuffling in place, which every stuck detector correctly reads
-- as stuck — and then answers with the recompute storm above. That bug looks
-- like a pathfinding bug and is not one.

export type Options = {
	agent_radius: number?,
	agent_height: number?,
	-- Passed through to the router. Without these the routing options were
	-- unreachable from here: `follow` forwarded the two agent dimensions and
	-- nothing else, so a caller could not ask for a walk-only route, could not
	-- turn off the candidate retries, and could not tune the cache -- and the
	-- cache silently ran on `os.clock` while the follower ran on whatever clock
	-- it was given, which is two different clocks inside one agent.
	allow_jump_retry: boolean?,
	retry_candidates: boolean?,
	costs: { [string]: number }?,
	cache_cell: number?,
	cache_ttl: number?,
	cache_miss_ttl: number?,
	cache_key: string?,
	-- Studs to a waypoint before advancing to the next.
	waypoint_range: number?,
	-- Recompute when the goal has moved this far from the one the route was
	-- built for.
	goal_drift: number?,
	-- Minimum seconds between computes. See the throttle rule above.
	recompute_interval: number?,
	-- Ceiling for the backoff after repeated failures. A goal that cannot be
	-- reached stops being asked about several times a second.
	max_recompute_interval: number?,
	-- Re-anchor a live route from the agent's real position this often.
	refresh_seconds: number?,
	-- Within this many studs of the goal (ignoring height) the agent counts as
	-- arrived, and the stuck machinery stands down.
	arrive_range: number?,
	-- Below this speed for `stuck_after` seconds counts as stuck.
	stuck_speed: number?,
	stuck_after: number?,
	-- Called when the agent is stuck and a recompute has not helped. Default is
	-- a jump. Return true if you handled it.
	on_stuck: ((humanoid: Humanoid) -> boolean)?,
	-- Replace the clock. Everything this module decides is a decision about
	-- TIME -- throttle, refresh, backoff, how long the agent has been slow --
	-- and none of it was checkable without waiting real seconds, so the spec
	-- for it had to sidestep timing entirely with intervals of 0 and 1e6. An
	-- injected clock is the same seam `util/numbers/weighted-random` opens for
	-- its RNG, and for the same reason: a rule about time that cannot be tested
	-- in time is a rule that regresses quietly.
	clock: (() -> number)?,
	-- Replace the routing call. For a game with its own navmesh or waypoint
	-- graph -- and it is also the only seam through which the decision logic
	-- below (throttle, drift, waypoint advance, stuck) can be exercised
	-- headlessly, since PathfindingService cannot be.
	route: ((from: Vector3, to: Vector3, options: any) -> (any, string))?,
}

export type Agent = {
	-- Call every tick with the live target. Returns whether it is following a
	-- real route (false means it is walking straight at the goal as a fallback).
	move_to: (goal: Vector3) -> boolean,
	stop: () -> (),
	is_pathing: () -> boolean,
	-- Last status from `compute`, for logging a persistent failure.
	last_status: () -> string,
	-- Whether the agent is standing on its goal. A caller that keeps driving an
	-- arrived agent is normal; the follower has to cope with it rather than
	-- treat standing still as a fault.
	has_arrived: () -> boolean,
	-- True when the current route only reaches the closest reachable point, not
	-- the goal. Following it is still the right move; believing you arrived is
	-- not.
	is_partial: () -> boolean,
	-- Consecutive failed computes. Non-zero means the goal has been
	-- unreachable for a while and the recompute interval is backing off.
	failures: () -> number,
}

local function follow(humanoid: Humanoid, options: Options?): Agent
	const opts = options or {}
	const waypoint_range = opts.waypoint_range or 3
	const goal_drift = opts.goal_drift or 8
	const recompute_interval = opts.recompute_interval or 0.4
	const refresh_seconds = opts.refresh_seconds or 1
	const stuck_speed = opts.stuck_speed or 1
	const stuck_after = opts.stuck_after or 1.5
	const max_recompute_interval = opts.max_recompute_interval or 4
	const arrive_range = opts.arrive_range or 4
	const clock = opts.clock or os.clock

	-- Built once. The router is called on a throttle, but rebuilding this table
	-- per compute would allocate for nothing, and assembling it in one place is
	-- what makes "did that option actually reach the router" answerable.
	const route_options = {
		agent_radius = opts.agent_radius,
		agent_height = opts.agent_height,
		allow_jump_retry = opts.allow_jump_retry,
		retry_candidates = opts.retry_candidates,
		costs = opts.costs,
		cache_cell = opts.cache_cell,
		-- A cached route must not outlive the interval on which this agent
		-- re-anchors, or the re-anchor is handed back the very route it exists
		-- to replace.
		cache_ttl = opts.cache_ttl or refresh_seconds,
		cache_miss_ttl = opts.cache_miss_ttl,
		cache_key = opts.cache_key,
		-- The SAME clock the follower uses, so a cache entry cannot expire on a
		-- different timeline from the throttle that decides when to ask for it.
		clock = clock,
	}

	local waypoints: { PathWaypoint }? = nil
	local index = 1
	local routed_for: Vector3? = nil
	-- NEGATIVE INFINITY, NOT ZERO. These are "when did this last happen", and
	-- the honest answer before it has ever happened is "never", not "at time
	-- zero". Zero only looked right because `os.clock()` returns a large number,
	-- so `now - 0` cleared any interval on the first tick by accident. Hand the
	-- agent a clock that starts near zero -- an injected one in a spec, or a
	-- run-relative clock in a game -- and the first compute is deferred by a
	-- whole interval, which reads as "pathfinding does nothing for half a
	-- second after it spawns". Found the moment the clock became injectable.
	local last_compute_at = -math.huge
	local last_refresh_at = -math.huge
	local status = "NotComputed"

	local partial = false
	local arrived = false
	local failures = 0
	-- Set from the engine's Blocked signal, acted on in `move_to`. Deliberately
	-- a flag rather than a recompute in the handler: that callback runs on the
	-- engine's schedule, and computing a route from inside it would put a
	-- yield-capable call somewhere the follower does not control.
	local blocked_ahead = false
	local release_route: (() -> ())? = nil

	-- Stuck detection accumulates DISTANCE and TIME rather than sampling a
	-- per-tick speed. Two reasons, and the second is the one that bit: a single
	-- frame's displacement is noisy, and Studio's frame delta is not wall time
	-- when the window is backgrounded, so anything that divides one by the
	-- other reports nonsense in exactly the session you are debugging in.
	local slow_for = 0
	local moved_while_slow = 0
	local last_position: Vector3? = nil
	local last_tick_at: number? = nil

	local function root(): BasePart?
		return humanoid.RootPart
	end

	-- Drop the current route AND everything hanging off it. The Blocked
	-- subscription and the Path itself both belong to the route, so anything
	-- that abandons a route has to come through here or they accumulate --
	-- one dead connection and one Path per recompute, several times a second,
	-- for as long as the agent lives.
	local function clear()
		if release_route then
			release_route()
			release_route = nil
		end
		waypoints = nil
		index = 1
		routed_for = nil
		partial = false
		blocked_ahead = false
	end

	local function recompute(from: Vector3, goal: Vector3, now: number): boolean
		last_compute_at = now
		last_refresh_at = now
		-- CACHED BY DEFAULT. `ComputeAsync` yields, and a dozen agents asking
		-- for a route in the same tick is a dozen scheduler round trips even
		-- when they are all walking to the same door. `cache.route` is a
		-- drop-in for `compute` with a few seconds of memory and eviction on
		-- Blocked; pass `route = pathfinding.compute` to opt out.
		const router = opts.route or cache.route
		const result, last = router(from, goal, route_options)
		status = last

		-- Release the OLD route before adopting or discarding, never after: the
		-- early return below is exactly the path on which a leak hides.
		clear()

		if not result then
			failures += 1
			return false
		end

		failures = 0
		waypoints = result.waypoints
		partial = result.partial == true
		-- Waypoint 1 is (near) where we already stand; starting there makes the
		-- agent walk to its own feet before setting off.
		index = 2
		routed_for = goal

		local disconnect: (() -> ())? = nil
		if result.on_blocked then
			disconnect = result.on_blocked(function(blocked_index: number)
				-- BEHIND US DOES NOT COUNT. The engine reports the waypoint
				-- that stopped being walkable, and a door closing in the
				-- corridor already walked is not this agent's problem --
				-- reacting to it would throw away a perfectly good route and,
				-- for an agent being followed through a closing door, do it
				-- repeatedly.
				if blocked_index >= index then
					blocked_ahead = true
				end
			end)
		end
		const destroy = result.destroy
		release_route = function()
			if disconnect then
				disconnect()
			end
			if destroy then
				destroy()
			end
		end
		return true
	end

	local function move_to(goal: Vector3): boolean
		const part = root()
		if not part then
			return false
		end
		const now = clock()
		const position = part.Position

		-- Stuck detection runs on ACTUAL displacement, not on whether a
		-- waypoint was reached: an agent pressed against geometry is following
		-- its route perfectly and going nowhere.
		--
		-- Accumulated over a window rather than judged per tick. The version
		-- this replaces compared one tick's displacement against a threshold
		-- that GREW with how long the agent had been slow, so an agent that had
		-- been stuck for a second needed to cover a full stud in a single frame
		-- to be considered moving again -- it could enter the stuck state and
		-- not leave it under its own power.
		if last_position and last_tick_at then
			const dt = now - last_tick_at
			if dt > 0 then
				slow_for += dt
				moved_while_slow += (position - last_position).Magnitude
				-- Covered enough ground over the window to count as moving.
				if moved_while_slow > stuck_speed * slow_for then
					slow_for = 0
					moved_while_slow = 0
				end
			end
		end
		last_position = position
		last_tick_at = now

		-- Stuck for long enough that the route is not the problem. Another
		-- identical path would change nothing, so break the symmetry instead.
		--
		-- CHECKED BEFORE THE ROUTE BRANCHES, and that placement is the fix to a
		-- real hole. This used to sit at the bottom, after the follower had
		-- committed to a waypoint -- so it was reached ONLY while a route
		-- existed. Every path that returns early skipped it: no route computed,
		-- route exhausted, target off the navmesh. Those are the same paths
		-- that fall back to walking in a straight line at the goal, which is
		-- precisely when an agent is most likely to be grinding against
		-- geometry -- so the detector was absent from the case it was written
		-- for. Found by a spec that walked an agent to the end of its route and
		-- then stopped dead.
		-- ARRIVAL IS NOT BEING STUCK, and conflating them is a bug you watch
		-- rather than read about. Driven to a goal it was already standing on,
		-- the agent is by definition not moving, so the detector fires -- and
		-- the default handler jumps. Live, an agent that had reached its goal
		-- called `on_stuck` ten times in twelve seconds; with the stock handler
		-- that is a hop every 1.5 s, forever, which reads as a broken AI and is
		-- the follower misreading success as failure.
		--
		-- Flat distance, like the waypoint advance: an agent on a goal one
		-- floor below is not there.
		-- Arriving RESETS the window, and that reset is the whole mechanism --
		-- there is deliberately no second `not arrived` guard on the check
		-- below. One was written, and a mutation removing it changed nothing,
		-- because a zeroed window can never exceed the threshold. Redundant
		-- belt-and-braces that no test can kill is just a second thing to keep
		-- true.
		arrived = (Vector3.new(goal.X, position.Y, goal.Z) - position).Magnitude <= arrive_range
		if arrived then
			slow_for = 0
			moved_while_slow = 0
		end

		if slow_for > stuck_after then
			slow_for = 0
			moved_while_slow = 0
			clear()
			const handled = if opts.on_stuck then opts.on_stuck(humanoid) else false
			if not handled then
				humanoid.Jump = true
			end
		end

		-- A blockage reported ahead of us retires the route immediately. The
		-- recompute still has to wait for the base interval below -- a door
		-- flickering open and shut would otherwise be a compute per flicker --
		-- but it does NOT wait out the failure backoff, because a blocked route
		-- is not evidence that the goal is unreachable.
		local blocked_now = false
		if blocked_ahead then
			blocked_now = true
			clear()
		end

		const stale_goal = routed_for == nil or (goal - routed_for).Magnitude > goal_drift
		const needs_refresh = now - last_refresh_at > refresh_seconds

		-- BACKOFF. Each consecutive failure doubles the wait, to a ceiling.
		-- Without it an unreachable goal is a compute every 0.4s forever, and
		-- `ComputeAsync` failures log -- which is how a bot shuffling at a wall
		-- fills a console and buries everything else in it.
		const interval = if blocked_now or failures == 0
			then recompute_interval
			else math.min(recompute_interval * 2 ^ math.min(failures, 6), max_recompute_interval)
		const may_compute = now - last_compute_at > interval

		if may_compute and (blocked_now or stale_goal or needs_refresh or waypoints == nil) then
			recompute(position, goal, now)
		end

		const route = waypoints
		if not route then
			-- FALLBACK, and a real one: a target off the navmesh (airborne, or
			-- in geometry that has not streamed in yet) has no route and still
			-- needs the agent to try. Walking straight at it is worse than a
			-- route and much better than standing still.
			humanoid:MoveTo(goal)
			return false
		end

		local waypoint = route[index]
		while
			waypoint
			and (Vector3.new(waypoint.Position.X, position.Y, waypoint.Position.Z) - position).Magnitude
				< waypoint_range
		do
			index += 1
			waypoint = route[index]
		end
		if not waypoint then
			clear()
			humanoid:MoveTo(goal)
			return false
		end

		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)

		return true
	end

	return table.freeze {
		move_to = move_to,
		stop = function()
			clear()
			const part = root()
			if part then
				humanoid:MoveTo(part.Position)
			end
		end,
		is_pathing = function(): boolean
			return waypoints ~= nil
		end,
		has_arrived = function(): boolean
			return arrived
		end,
		is_partial = function(): boolean
			return partial
		end,
		failures = function(): number
			return failures
		end,
		last_status = function(): string
			return status
		end,
	}
end

return table.freeze {
	follow = follow,
	-- The uncached router, for a caller that wants exactly one ComputeAsync per
	-- call: `follow(humanoid, { route = pathfinding.compute })`.
	compute = compute,
	-- `cache.clear()` on a place teardown, `cache.stats()` to see whether the
	-- cell size suits how your agents actually move.
	cache = cache,
}
