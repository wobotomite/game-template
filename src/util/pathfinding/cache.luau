const compute_route = require(script.Parent.compute)

-- A short-lived, shared cache in front of `compute`.
--
--   const result, status = cached(from, to, { agent_radius = 2 })
--
-- Same signature as `util/pathfinding/compute`, so it drops in wherever that
-- was used -- which is what `util/pathfinding` now does by default.
--
-- ========================== WHY THIS IS WORTH IT ==========================
--
-- `ComputeAsync` YIELDS. That is the cost that matters, and it is easy to
-- mis-measure: benchmarked in Studio, a long route across clutter, a 25-stud
-- hop, and forty different goals all came back at 99.98 ms per call -- the same
-- number to two decimal places, which is a scheduler tick, not pathfinding
-- work. (The control: an unreachable target that THREW instead of yielding
-- returned in 0.047 ms, and `CreatePath` plus `Destroy` on its own is 0.004
-- ms.) So the honest claim is not "a route costs 100 ms of CPU" -- I did not
-- measure CPU -- it is that every route costs a yield, and yields are what turn
-- twelve NPCs asking for a route in the same tick into twelve scheduler round
-- trips.
--
-- A cache hit costs none of that. It is a table lookup.
--
-- ======================= WHAT MAKES IT SAFE TO SHARE ======================
--
-- A stale route is worse than no cache: handing an agent a path through a door
-- that has since closed is precisely the failure the blocked handling exists to
-- prevent, and a cache is a machine for doing it at scale. Three things stop
-- that:
--
-- **A SHORT TTL.** Seconds, not minutes. The world moves.
--
-- **BLOCKED EVICTS, IF IT FIRES.** The cache subscribes to each cached route's
-- `Blocked` signal ONCE -- not once per follower -- and drops the entry when the
-- engine says it stopped being walkable, telling every follower on that route.
-- When it fires, the first agent to discover a shut door fixes it for everyone
-- still to ask.
--
-- It did not fire in testing (see the note in `compute`), so this is the second
-- line, not the first. The TTL above is the first: it bounds how stale a served
-- route can be no matter what the engine does or does not report.
--
-- **THE KEY INCLUDES THE AGENT.** A route computed for a 2-stud radius is not
-- a route for a 6-stud one, and a walking route is not a jumping one. Sharing
-- across differently-shaped agents would route the big one through a gap only
-- the small one fits.
--
-- Positions are quantised to a cell, because two agents standing 3 studs apart
-- asking to reach the same door do not need two routes. The follower skips
-- waypoint 1 (it is your own feet) so a start that is a cell off is already
-- handled by the code that consumes this.
--
-- NOT CACHED: a call carrying `costs`, unless the caller also supplies
-- `cache_key`. Labelled navmesh costs change the route and cannot be compared
-- cheaply, and a cache that silently ignores part of its input is a wrong-answer
-- machine.

export type Options = {
	agent_radius: number?,
	agent_height: number?,
	allow_jump_retry: boolean?,
	retry_candidates: boolean?,
	costs: { [string]: number }?,
	-- Studs per cache cell. Bigger shares more and fits worse.
	cache_cell: number?,
	-- Seconds a successful route stays usable.
	cache_ttl: number?,
	-- Seconds a FAILURE stays remembered. Shorter on purpose: a failure is a
	-- statement about a door that may be about to open, and remembering it too
	-- long is how an agent stands still after the way is clear. Non-zero
	-- because without it every agent in a party pays the yield to learn the
	-- same "no" in the same tick.
	cache_miss_ttl: number?,
	-- Disambiguates entries when `costs` are in play. Without it, a call with
	-- costs bypasses the cache entirely.
	cache_key: string?,
	-- Seams. `clock` is injected for the same reason the follower injects one:
	-- everything here is a decision about time.
	clock: (() -> number)?,
	compute: ((Vector3, Vector3, any) -> (any, string))?,
}

const DEFAULT_CELL = 4
-- ONE SECOND, AND IT IS NOT ARBITRARY: it matches the follower's default
-- re-anchor interval, and a cache entry that outlives that interval makes the
-- re-anchor a no-op. The follower recomputes from where it actually is once a
-- second precisely so a stale route gets replaced -- and if the cache answers
-- that recompute from a three-second-old entry, the route it was trying to
-- replace is the route it gets back. The cache must never be the more stale of
-- the two. `follow` passes its own `refresh_seconds` for the same reason.
--
-- A second is still the whole win. The point is not remembering routes for a
-- long time, it is that a dozen agents asking in the same tick pay one yield
-- between them.
const DEFAULT_TTL = 1
const DEFAULT_MISS_TTL = 0.5
-- A ceiling so a wandering crowd cannot grow this without bound. Evicting the
-- expired first and then the oldest keeps the live working set.
const MAX_ENTRIES = 256

type Listener = (number) -> ()

type Entry = {
	waypoints: { any },
	status: string,
	partial: boolean,
	jumped: boolean,
	expires_at: number,
	-- nil for a remembered failure, and for a router that has no Path to give.
	path: any,
	disconnect: (() -> ())?,
	listeners: { [Listener]: true },
}

const entries: { [string]: Entry } = {}
local count = 0
local hits = 0
local misses = 0

local function cell(value: number, size: number): number
	return math.floor(value / size)
end

local function drop(key: string)
	const entry = entries[key]
	if not entry then
		return
	end
	entries[key] = nil
	count -= 1
	if entry.disconnect then
		entry.disconnect()
	end
	-- The Path is the cache's to release: handouts never touch it, they talk to
	-- the entry. So destroying it here cannot pull the rug from a follower
	-- still holding a result -- its waypoints are a plain array and stay valid.
	if entry.path then
		pcall(function()
			entry.path:Destroy()
		end)
	end
end

local function sweep(now: number)
	for key, entry in entries do
		if now >= entry.expires_at then
			drop(key)
		end
	end
end

-- Hand the entry out as something shaped like a compute Result. `on_blocked`
-- and `destroy` address the ENTRY, never the Path, which is what lets one
-- subscription serve every follower using this route.
local function view(entry: Entry): any
	return {
		waypoints = entry.waypoints,
		jumped = entry.jumped,
		status = entry.status,
		partial = entry.partial,
		on_blocked = function(callback: Listener): () -> ()
			entry.listeners[callback] = true
			return function()
				entry.listeners[callback] = nil
			end
		end,
		-- Nothing to release: the Path belongs to the cache, and the
		-- subscription was already dropped by the disconnect above. Present
		-- because the follower calls it on every route it retires, and a
		-- cached route should not be a special case there.
		destroy = function() end,
	}
end

local function remember(key: string, entry: Entry)
	if count >= MAX_ENTRIES then
		-- Full: expired entries first, and if none are expired take the one
		-- closest to expiring rather than an arbitrary key.
		local oldest_key, oldest_at = nil, math.huge
		for k, e in entries do
			if e.expires_at < oldest_at then
				oldest_key, oldest_at = k, e.expires_at
			end
		end
		if oldest_key then
			drop(oldest_key)
		end
	end
	entries[key] = entry
	count += 1
end

local function route(from: Vector3, to: Vector3, options: any?): (any, string)
	const opts = options or {}
	const now = (opts.clock or os.clock)()
	const router = opts.compute or compute_route

	-- Labelled costs change the route and cannot be compared cheaply.
	if opts.costs and not opts.cache_key then
		return router(from, to, opts)
	end

	const size = opts.cache_cell or DEFAULT_CELL
	const key = table.concat({
		opts.cache_key or "",
		cell(from.X, size),
		cell(from.Y, size),
		cell(from.Z, size),
		cell(to.X, size),
		cell(to.Y, size),
		cell(to.Z, size),
		opts.agent_radius or 2,
		opts.agent_height or 5,
		if opts.allow_jump_retry == false then "walk" else "jump",
	}, ":")

	const existing = entries[key]
	if existing then
		if now < existing.expires_at then
			hits += 1
			-- A remembered failure is a cache hit that returns nothing, which
			-- is the point: the caller learns "no" without paying the yield.
			if #existing.waypoints == 0 then
				return nil, existing.status
			end
			return view(existing), existing.status
		end
		drop(key)
	end

	misses += 1
	sweep(now)

	const result, status = router(from, to, opts)

	if not result then
		remember(key, {
			waypoints = {},
			status = status,
			partial = true,
			jumped = false,
			expires_at = now + (opts.cache_miss_ttl or DEFAULT_MISS_TTL),
			path = nil,
			disconnect = nil,
			listeners = {},
		})
		return nil, status
	end

	const entry: Entry = {
		waypoints = result.waypoints,
		status = result.status,
		partial = result.partial == true,
		jumped = result.jumped == true,
		expires_at = now + (opts.cache_ttl or DEFAULT_TTL),
		path = nil,
		disconnect = nil,
		listeners = {},
	}

	-- ONE subscription per route, held by the cache. When it fires, every
	-- follower currently on this route hears about it and the entry goes, so
	-- the next asker recomputes instead of being handed the blocked route
	-- again.
	if result.on_blocked then
		entry.disconnect = result.on_blocked(function(index: number)
			for listener in entry.listeners do
				task.spawn(listener, index)
			end
			drop(key)
		end)
	end
	-- The cache owns the Path from here; `destroy` on the original result is
	-- deliberately not called, because the Path has to stay alive for the
	-- subscription above.
	if result.destroy then
		entry.path = { Destroy = result.destroy }
	end

	remember(key, entry)
	return view(entry), status
end

return table.freeze {
	-- Drop-in for `compute`: same arguments, same two return values.
	route = route,

	-- Forget everything. For a place teardown, and for a spec that must not
	-- inherit another spec's entries -- this module's state is per-process, so
	-- without it the second test in a file reads the first one's cache.
	clear = function()
		for key in entries do
			drop(key)
		end
		hits = 0
		misses = 0
	end,

	-- Hits, misses and live entries. Worth logging once in a while: a hit rate
	-- near zero means the cell size is too small for how the callers actually
	-- move, and the cache is pure overhead.
	stats = function(): { hits: number, misses: number, entries: number }
		return { hits = hits, misses = misses, entries = count }
	end,
}
