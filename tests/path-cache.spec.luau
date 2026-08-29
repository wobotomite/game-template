--!nocheck
-- util/pathfinding/cache: what it shares, and what it refuses to share.
-- Run with:
--   lune run tests/path-cache.spec.luau
--
-- WHY THIS EXISTS. A path cache is a machine for handing out stale routes at
-- scale. Every case below is about the line between "two agents walking to the
-- same door do not need two ComputeAsync yields" and "an agent was handed a
-- route through a door that closed". The first is the whole point; the second
-- is worse than having no cache, because it is wrong in a way that looks like
-- the AI is broken rather than like the cache is.
--
-- The seams are `compute` (so nothing here calls PathfindingService) and
-- `clock` (so a TTL can be tested without waiting seconds).

local h = require "./harness"
local env = require "./roblox-env"
local roblox = require "@lune/roblox"
local Vector3 = roblox.Vector3

h.title "path cache:"

local cache = env.load "ReplicatedStorage.Util.pathfinding.cache"

-- A stand-in router. Counts calls, and hands back something shaped like a
-- compute Result including a Blocked hook we can fire on demand.
local function fake_compute(mode: string?)
	local state = { calls = 0, blocked_listeners = {}, destroys = 0 }
	local fn = function(from, to, _options)
		state.calls += 1
		if mode == "fail" then
			return nil, "NoPath"
		end
		local index = state.calls
		return {
			waypoints = { { Position = from }, { Position = to } },
			jumped = false,
			status = "Success",
			partial = false,
			on_blocked = function(callback)
				state.blocked_listeners[index] = callback
				return function()
					state.blocked_listeners[index] = nil
				end
			end,
			destroy = function()
				state.destroys += 1
			end,
		},
			"Success"
	end
	return fn, state
end

local function fake_clock()
	local t = 0
	return function()
		return t
	end, function(by: number)
		t += by
	end
end

local A = Vector3.new(0, 0, 0)
local B = Vector3.new(100, 0, 0)

-- ================================ hits ====================================

do
	cache.clear()
	local compute, state = fake_compute()
	local now = fake_clock()
	local opts = { compute = compute, clock = now }

	cache.route(A, B, opts)
	cache.route(A, B, opts)
	cache.route(A, B, opts)
	h.equals("three identical requests compute once", state.calls, 1)
	h.equals("and the rest are hits", cache.stats().hits, 2)
end

do
	cache.clear()
	local compute, state = fake_compute()
	local now = fake_clock()
	local opts = { compute = compute, clock = now, cache_cell = 4 }

	cache.route(A, B, opts)
	-- Two agents standing 3 studs apart, asking for the same door. Same cell.
	cache.route(Vector3.new(3, 0, 0), B, opts)
	h.equals("a start inside the same cell shares the route", state.calls, 1)

	-- ...and one standing a cell away does not.
	cache.route(Vector3.new(40, 0, 0), B, opts)
	h.equals("a start in a different cell does not", state.calls, 2)
end

-- ============================ what must NOT share =========================

do
	cache.clear()
	local compute, state = fake_compute()
	local now = fake_clock()

	cache.route(A, B, { compute = compute, clock = now, agent_radius = 2 })
	cache.route(A, B, { compute = compute, clock = now, agent_radius = 6 })
	-- A gap a 2-stud agent fits through is not a route for a 6-stud one.
	h.equals("a different agent radius computes its own route", state.calls, 2)

	cache.route(A, B, { compute = compute, clock = now, agent_radius = 2, allow_jump_retry = false })
	h.equals("and so does a walk-only request", state.calls, 3)
end

do
	cache.clear()
	local compute, state = fake_compute()
	local now = fake_clock()
	-- Labelled navmesh costs change the route and cannot be compared cheaply,
	-- so a call carrying them must not be answered from a key that ignores
	-- them. Bypassing is the safe answer; a wrong shared route is not.
	local opts = { compute = compute, clock = now, costs = { Water = 20 } }
	cache.route(A, B, opts)
	cache.route(A, B, opts)
	h.equals("costs bypass the cache entirely", state.calls, 2)

	-- Unless the caller names the variant, at which point sharing is their call.
	local keyed = { compute = compute, clock = now, costs = { Water = 20 }, cache_key = "watery" }
	cache.route(A, B, keyed)
	cache.route(A, B, keyed)
	h.equals("a supplied cache_key opts back in", state.calls, 3)
end

-- ================================= TTL ====================================

do
	cache.clear()
	local compute, state = fake_compute()
	local now, advance = fake_clock()
	local opts = { compute = compute, clock = now, cache_ttl = 3 }

	cache.route(A, B, opts)
	advance(2)
	cache.route(A, B, opts)
	h.equals("inside the TTL it is still a hit", state.calls, 1)

	advance(2)
	cache.route(A, B, opts)
	h.equals("past the TTL it recomputes", state.calls, 2)
end

do
	-- A failure is remembered too, briefly: without it every agent in a party
	-- pays a yield to learn the same "no" in the same tick. Briefly, because a
	-- failure is a statement about a door that may be about to open.
	cache.clear()
	local compute, state = fake_compute "fail"
	local now, advance = fake_clock()
	local opts = { compute = compute, clock = now, cache_miss_ttl = 0.5 }

	local first = cache.route(A, B, opts)
	h.equals("a failure returns nothing", first, nil)
	local second = cache.route(A, B, opts)
	h.equals("and is remembered rather than retried", state.calls, 1)
	h.equals("the remembered failure still returns nothing", second, nil)

	advance(1)
	cache.route(A, B, opts)
	h.equals("but only for cache_miss_ttl", state.calls, 2)
end

-- ============================ blocked evicts ==============================

do
	-- THE CASE THE WHOLE DESIGN TURNS ON. One agent discovering a shut door has
	-- to fix it for everyone still to ask, or the cache multiplies the failure
	-- instead of the route.
	cache.clear()
	local compute, state = fake_compute()
	local now = fake_clock()
	local opts = { compute = compute, clock = now }

	local first = cache.route(A, B, opts)
	local heard: { number } = {}
	first.on_blocked(function(index)
		table.insert(heard, index)
	end)
	-- A second follower on the same cached route.
	local second = cache.route(A, B, opts)
	second.on_blocked(function(index)
		table.insert(heard, index)
	end)
	h.equals("both followers share one computed route", state.calls, 1)

	-- The engine reports the blockage. One subscription, held by the cache.
	h.check("the cache subscribed to the route", state.blocked_listeners[1] ~= nil)
	state.blocked_listeners[1](4)

	h.equals("every follower on that route is told", #heard, 2)

	cache.route(A, B, opts)
	h.equals("and the blocked entry is gone, so the next asker recomputes", state.calls, 2)
end

do
	-- Retiring a route must not leave the follower subscribed: the cache
	-- outlives any one agent, and a listener per dead follower is a leak with a
	-- long fuse.
	cache.clear()
	local compute, state = fake_compute()
	local now = fake_clock()
	local opts = { compute = compute, clock = now }

	local result = cache.route(A, B, opts)
	local heard = 0
	local disconnect = result.on_blocked(function()
		heard += 1
	end)
	disconnect()
	result.destroy()

	state.blocked_listeners[1](2)
	h.equals("a disconnected follower hears nothing", heard, 0)
end

-- ================================ upkeep ==================================

do
	cache.clear()
	local compute = fake_compute()
	local now = fake_clock()
	cache.route(A, B, { compute = compute, clock = now })
	h.check("an entry is held", cache.stats().entries > 0)
	cache.clear()
	h.equals("clear empties it", cache.stats().entries, 0)
	h.equals("and resets the counters", cache.stats().hits, 0)
end

h.done()
