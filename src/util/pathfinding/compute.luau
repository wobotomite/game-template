const PathfindingService = game:GetService "PathfindingService"

-- Compute a navmesh route, safely.
--
--   const waypoints = compute(from, to, { agent_radius = 2, agent_height = 5 })
--   if waypoints then ... end
--
-- This is the half of pathfinding with no state in it. `util/pathfinding` is
-- the follower that drives a humanoid along what this returns.
--
-- ===================== WHY THIS IS NOT A ONE-LINER ========================
--
-- `PathfindingService:CreatePath():ComputeAsync()` looks like a one-liner and
-- behaves like four separate hazards. Every rule below came from a live
-- session, not from the documentation.
--
-- **ComputeAsync THROWS.** Not "returns a failed status" — throws. A bare call
-- takes down whatever thread it was on, and in an AI tick that is the entity's
-- whole brain. Probed live: a target 50,000 studs out THREW, while a NaN target
-- returned `NoPath` cleanly. An earlier version of this comment had that
-- backwards and named NaN as the throwing case -- the guard below is still
-- worth keeping (a NaN target is a bug upstream and "the target was NaN" is a
-- better report than a route to nowhere), but the throw it protects against is
-- the out-of-range one.
--
-- **Success is a STATUS, not the absence of a throw.** A call that returns
-- cleanly can still be one of five failures. The full set, read off the live
-- enum: Success, ClosestNoPath, ClosestOutOfRange, FailStartNotEmpty,
-- FailFinishNotEmpty, NoPath.
--
-- **A PARTIAL ROUTE IS WORTH MORE THAN NO ROUTE.** This used to return nil for
-- anything but `Success`, which handed the follower a choice between standing
-- still and walking in a straight line at a target it cannot reach -- into the
-- wall between them. `ClosestNoPath` and `ClosestOutOfRange` mean "here is the
-- way to the nearest point I could reach", which is exactly what something
-- chasing a target behind a locked door should walk. So any result with two or
-- more waypoints is usable; `partial` says whether it actually arrives.
--
-- Honesty about the evidence: the throw and the status list are measured, but
-- I could not produce a live `ClosestNoPath` in the place I had -- the geometry
-- probe degenerated into pathing across Terrain. The partial branch is written
-- from the documented meaning of those statuses, not from a capture, and the
-- follower treats a partial route as best-effort rather than trusting it.
--
-- **A route with one waypoint is not a route.** Waypoint 1 is (near) where you
-- already stand, so a path of length 1 means "you are there" and following it
-- moves nothing.
--
-- **WaypointSpacing default is far denser than useful.** Measured on one route
-- in a live place: `math.huge` gave **5** waypoints, the default gave **13**,
-- and `-1` gave **419**. Waypoints only where the path bends or acts is what
-- you want for a follower; the dense versions cost a table of hundreds of
-- Vector3s per recompute and make the agent visibly stair-step.
--
-- **THE PATH OBJECT HAS TO OUTLIVE THIS CALL.** `Path.Blocked` fires when a
-- computed route stops being walkable -- a door shuts, a part moves across it
-- -- and it is the only notification you get. An earlier version computed a
-- route, read the waypoints and dropped the Path on the floor, so nothing could
-- subscribe and a blocked agent kept walking into the obstruction until a stuck
-- timer noticed a second and a half later. The Path now comes back with the
-- result, and the caller is handed `destroy` to release it.
--
-- (The method is the `Blocked` SIGNAL. There is no `ConnectToBlocked` -- probed
-- on a live Path, it is absent, and indexing it throws.)--
-- MEASURED, AND IT DID NOT FIRE. Sealing a computed route with an anchored,
-- colliding part and waiting five seconds produced NO `Blocked` callback --
-- neither in Edit nor in a running Server datamodel, against the real service.
-- So this subscription must NOT be treated as the thing that saves an agent
-- from a shut door. It is kept because it costs one connection per route and is
-- correct if the signal does fire (conditions under which it does were not
-- established), but the load-bearing recovery is the periodic RE-ANCHOR:
-- recomputing from where the agent actually is, once a second by default.
--
-- That path is proven, on the same geometry. Before sealing, the route ran
-- through the near doorway (3 waypoints, x = 0,-2,0); after sealing, a
-- recompute returned Success with 4 waypoints at x = 0,40,40,0 -- around by the
-- far doorway. Recompute is what routes around an obstacle; Blocked is at best
-- what makes it prompt.
--
-- **THE START AND THE GOAL ARE BOTH ALLOWED TO BE UNROUTABLE, and usually the
-- start is the one that is.** An agent pressed against a wall or a prop has its
-- agent cylinder overlapping geometry, and ComputeAsync fails instantly with
-- `FailStartNotEmpty` -- at exactly the moment a route matters most. Goals fail
-- the same way for duller reasons: a door slab's centre is several studs inside
-- solid wood, and a hovering target is off the navmesh entirely.
--
-- So a failure is not the answer, it is the first attempt. A step back off
-- whatever is being leaned on, a step up out of the floor, the goal flattened
-- to the caller's own height, the goal pulled a few studs back toward them --
-- each addresses a specific status, and each is tried only when that status
-- says so rather than as a blanket cross product. The retries came from the
-- ghost game's test bot, where they were arrived at against live geometry.
--
-- **Jump-free first, jump second.** `AgentCanJump = true` produces routes over
-- lips and railings that look wrong for most characters and can drop an agent
-- somewhere it cannot get back from. Ask for a walk-only route first and only
-- retry with jumping when there is none.

export type Options = {
	agent_radius: number?,
	agent_height: number?,
	-- Tried in order. Default: a walking route first, then one that may jump.
	allow_jump_retry: boolean?,
	-- Retry a failed compute from a nudged start / relaxed goal. On by default;
	-- turn it off for a caller that wants exactly one ComputeAsync per call.
	retry_candidates: boolean?,
	-- Passed through to CreatePath for callers with labelled navmesh costs.
	costs: { [string]: number }?,
}

export type Result = {
	waypoints: { PathWaypoint },
	-- Whether the route that succeeded needed jumping. Worth knowing: a
	-- follower has to set Humanoid.Jump on a Jump waypoint, and a caller may
	-- prefer to refuse a jumping route entirely.
	jumped: boolean,
	status: string,
	-- True when this route does not reach the goal, only the closest point the
	-- navmesh could offer. Follow it, but do not believe arriving means success.
	partial: boolean,
	-- Subscribe to the engine telling you this route just stopped being
	-- walkable. Returns a disconnect. Absent when the router has no such
	-- notion -- a custom navmesh, or a stand-in in a spec.
	on_blocked: ((callback: (waypoint_index: number) -> ()) -> () -> ())?,
	-- Release the underlying Path. Call it when done with the route; the
	-- follower does this on every recompute and on stop.
	destroy: (() -> ())?,
}

-- Waypoints only where the path bends or acts. See the measurement above.
const SPACING = math.huge

local function make_path(options: Options, can_jump: boolean): Path
	return PathfindingService:CreatePath {
		AgentRadius = options.agent_radius or 2,
		AgentHeight = options.agent_height or 5,
		AgentCanJump = can_jump,
		WaypointSpacing = SPACING,
		Costs = options.costs,
	}
end

-- How far to step back off an obstacle, and how far to pull a goal toward the
-- caller. Both from the test bot's live tuning.
const NUDGE_BACK = 3
const GOAL_BACK_OFF = 4
const NUDGE_UP = 2

-- Returns nil when there is no usable route, with the last status for logging.
-- Never throws.
return function(from: Vector3, to: Vector3, options: Options?): (Result?, string)
	const opts = options or {}
	local last_status = "NotComputed"

	-- Guard the inputs rather than handing them on. A NaN reaching here means
	-- something upstream divided by zero, and "the target was NaN" is a more
	-- useful report than a route to nowhere.
	if to ~= to or from ~= from then
		return nil, "NaN"
	end

	const function wrap(path: Path, waypoints: { PathWaypoint }, can_jump: boolean, status: string): Result
		return {
			waypoints = waypoints,
			jumped = can_jump,
			status = status,
			partial = status ~= "Success",
			on_blocked = function(callback: (number) -> ()): () -> ()
				const connection = path.Blocked:Connect(callback)
				return function()
					connection:Disconnect()
				end
			end,
			destroy = function()
				path:Destroy()
			end,
		}
	end

	-- The candidates, in the order a failure makes them worth trying. The plain
	-- one is always first and is the only one most calls ever use.
	const flat = (to - from) * Vector3.new(1, 0, 1)
	const away = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zero
	const grounded = Vector3.new(to.X, from.Y, to.Z)

	const candidates: { { from: Vector3, to: Vector3 } } = { { from = from, to = to } }
	if opts.retry_candidates ~= false then
		-- Start problems (FailStartNotEmpty): back off, then step up.
		table.insert(candidates, { from = from - away * NUDGE_BACK, to = to })
		table.insert(candidates, { from = from + Vector3.new(0, NUDGE_UP, 0), to = to })
		-- Goal problems: flatten it to our height, then pull it toward us --
		-- open floor in front of a door instead of inside the slab.
		table.insert(candidates, { from = from, to = grounded })
		table.insert(candidates, { from = from, to = grounded - away * GOAL_BACK_OFF })
	end

	-- The best route that did not reach the goal, kept in case nothing does.
	-- Held rather than destroyed, so its Path is still alive to return.
	local fallback: Result? = nil

	const tiers = if opts.allow_jump_retry == false then { false } else { false, true }
	for _, can_jump in tiers do
		for _, candidate in candidates do
			-- A Path per attempt rather than one reused across candidates:
			-- `ComputeAsync` overwrites the waypoints of the path it is called
			-- on, so a reused Path would invalidate the partial route held in
			-- `fallback` the moment the next candidate ran.
			const path = make_path(opts, can_jump)
			-- pcall, because ComputeAsync throws on degenerate input (a target
			-- far outside the world does). A failed compute must cost this
			-- attempt and nothing else.
			const ok = pcall(function()
				path:ComputeAsync(candidate.from, candidate.to)
			end)
			last_status = if ok then path.Status.Name else "Threw"

			local waypoints: { PathWaypoint } = {}
			if ok then
				-- Guarded too: GetWaypoints is only meaningful on a computed
				-- path, and this is reached with five different failure
				-- statuses.
				pcall(function()
					waypoints = path:GetWaypoints()
				end)
			end

			-- One waypoint means "you are already there", which is not a route.
			if #waypoints >= 2 then
				if last_status == "Success" then
					if fallback and fallback.destroy then
						fallback.destroy()
					end
					return wrap(path, waypoints, can_jump, last_status), last_status
				end
				-- Usable but incomplete. Keep the FIRST -- candidates are
				-- ordered by how little they distort the request, and the
				-- walking tier runs before the jumping one.
				if not fallback then
					fallback = wrap(path, waypoints, can_jump, last_status)
					continue
				end
			elseif ok and last_status == "Success" then
				last_status = "TooShort"
			end

			path:Destroy()
		end
	end

	if fallback then
		return fallback, fallback.status
	end
	return nil, last_status
end
