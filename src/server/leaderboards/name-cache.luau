const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserService = game:GetService "UserService"

const rules = require(ReplicatedStorage.Shared.settings).leaderboards

-- User id -> username, cached.
--
-- WHY THIS EXISTS. An OrderedDataStore stores numbers against string keys, so a
-- board comes back as fifty user ids and nothing else. Turning those into names
-- is a web call, the call is rate limited per server, and the same fifty ids
-- come back every refresh for hours -- so the answer is cached, the misses are
-- batched, and the batches are spaced.
--
-- THE THREE THINGS THAT GO WRONG WITHOUT IT, all of which look like a working
-- leaderboard until a real server load arrives:
--
--   * one call per row per refresh, which trips the rate limit and returns
--     nothing -- a board of blank names, with no error anywhere
--   * a cache that never evicts, which is a leak keyed by strangers' user ids
--   * a retry on every failure, which is what caused the rate limit
--
-- WHAT IS NOT CACHED: a player who is in this server. Their name is on their
-- Player instance, it is free, and it cannot be out of date.

export type Names = { username: string, display_name: string }

type Entry = {
	-- nil until a lookup has succeeded. An entry with no names still exists so
	-- that `retry_at` survives -- that is what stops a failed id being asked
	-- about again on the very next refresh.
	names: Names?,
	fetched_at: number,
	retry_at: number,
	-- The value of `access_count` when this entry was last used. See `touch`.
	accessed: number,
}

-- One caller's request, sitting in the queue until the drainer answers it.
type Request = {
	user_ids: { number },
	done: boolean,
	result: { [number]: Names },
	failure: string?,
	-- Threads parked in `resolve`, waiting for this request to be answered.
	waiters: { thread },
}

const cache: { [number]: Entry } = {}
const requests: { Request } = {}

local cache_size = 0
local access_count = 0
local next_batch_at = 0
local running = false

-- Marks `user_id` as just used, creating its entry and evicting the
-- least-recently-used one if the cache is full. Returns the entry.
--
-- LRU BY COUNTER, NOT BY CLOCK. `accessed` is a monotonic tick rather than a
-- timestamp so that two entries touched in the same frame still have an order,
-- and so eviction cannot be confused by a clock that does not move (Studio
-- paused, a server stepping slowly under load).
--
-- The eviction scan is a full walk of the cache, which happens only on a MISS
-- against a full cache -- at most once per new id, over at most
-- `NAME_CACHE_LIMIT` entries, off the render path entirely.
function touch(user_id: number): Entry
	access_count += 1
	const existing = cache[user_id]
	if existing then
		existing.accessed = access_count
		return existing
	end
	if cache_size >= rules.NAME_CACHE_LIMIT then
		local oldest_id: number? = nil
		local oldest_access = math.huge
		for id, entry in cache do
			if entry.accessed < oldest_access then
				oldest_id = id
				oldest_access = entry.accessed
			end
		end
		if oldest_id then
			cache[oldest_id] = nil
			cache_size -= 1
		end
	end
	const entry: Entry = { fetched_at = 0, retry_at = 0, accessed = access_count }
	cache[user_id] = entry
	cache_size += 1
	return entry
end

-- The actual work: answer from the cache where possible, fetch the rest in
-- spaced batches. YIELDS. Only ever called by `drain`, one call at a time --
-- which is what makes `next_batch_at` a correct rate limiter rather than a
-- value several threads race on.
function resolve_ids(user_ids: { number }): { [number]: Names }
	const result: { [number]: Names } = {}
	const pending: { number } = {}
	const seen: { [number]: true } = {}

	for _, user_id in user_ids do
		-- NaN, infinity and fractions cannot be user ids, and NaN in particular
		-- would be a cache key that never matches itself -- one leaked entry per
		-- lookup, forever. Negative ids are legal (Roblox uses them for its own
		-- accounts) and are cached, but are never sent to the web call below.
		if user_id ~= user_id or math.abs(user_id) == math.huge or user_id % 1 ~= 0 or seen[user_id] then
			continue
		end
		seen[user_id] = true

		const entry = touch(user_id)
		const player = Players:GetPlayerByUserId(user_id)
		const now = os.clock()
		if player then
			-- Free, and authoritative: a player in this server carries their own
			-- current name. This also refreshes the cache for everyone else's
			-- boards while they are here.
			entry.names = table.freeze { username = player.Name, display_name = player.DisplayName }
			entry.fetched_at = now
			entry.retry_at = 0
		end
		if entry.names then
			result[user_id] = entry.names
		end
		-- Fetch if we have no name at all, or the one we have has aged out -- but
		-- never before the backoff a previous failure set.
		if user_id > 0 and (not entry.names or now - entry.fetched_at >= rules.NAME_TTL) and now >= entry.retry_at then
			table.insert(pending, user_id)
		end
	end

	for first = 1, #pending, rules.NAME_BATCH_SIZE do
		const batch: { number } = {}
		const requested: { [number]: true } = {}
		for index = first, math.min(first + rules.NAME_BATCH_SIZE - 1, #pending) do
			const user_id = pending[index]
			table.insert(batch, user_id)
			requested[user_id] = true
		end

		-- The rate limiter. Re-checked in a loop rather than waited once because
		-- `task.wait` returns after at least that long, not exactly.
		while os.clock() < next_batch_at do
			task.wait(next_batch_at - os.clock())
		end
		next_batch_at = os.clock() + rules.NAME_BATCH_INTERVAL

		const ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(batch)
		end)
		const now = os.clock()

		-- Back off EVERY id in the batch, including on success. On failure that is
		-- the point; on success it is because an id the endpoint did not return
		-- (deleted account, or simply absent) would otherwise be re-requested on
		-- every single refresh for as long as it sits on the board.
		for _, user_id in batch do
			touch(user_id).retry_at = now + rules.NAME_RETRY
		end

		if ok then
			for _, info in infos do
				-- Only ids we asked for. The endpoint is not contractually limited
				-- to the batch, and an unasked-for id would be cached under
				-- somebody else's slot.
				if not requested[info.Id] then
					continue
				end
				const names: Names = table.freeze { username = info.Username, display_name = info.DisplayName }
				const entry = touch(info.Id)
				entry.names = names
				entry.fetched_at = now
				entry.retry_at = 0
				result[info.Id] = names
			end
		end
		-- A failed batch is not raised: the ids simply have no names this time,
		-- the board shows their rows with empty names, and the backoff above
		-- decides when to try again. Losing a name is not worth losing a board.
	end

	return result
end

-- Answers every queued request, one at a time, then stops. Runs in its own
-- thread; `running` says whether that thread is alive.
function drain()
	while #requests > 0 do
		const request = table.remove(requests, 1) :: Request
		const ok, result = pcall(resolve_ids, request.user_ids)
		if ok then
			request.result = result
		else
			request.failure = tostring(result)
		end
		request.done = true
		-- Each waiter is resumed on ITS OWN thread rather than inline. A waiter
		-- carries on with whatever it was doing the moment it wakes -- `refresh`
		-- goes straight into a DataStore read -- and resuming it inline would
		-- park this drainer inside that work, holding up every request behind it
		-- for as long as it took.
		for _, thread in request.waiters do
			task.spawn(thread)
		end
		table.clear(request.waiters)
	end
	running = false
end

-- Names for these user ids. YIELDS. Ids with no name available are simply
-- absent from the result; the caller decides what to show instead.
--
-- WHY A QUEUE RATHER THAN JUST DOING THE WORK HERE. Two callers at once (a
-- board refresh and, say, a UI request from a client) would each start their own
-- batching run, and the two runs would race on the spacing that keeps them
-- inside the rate limit -- the exact failure the cache exists to prevent. One
-- drainer means the spacing is a single number read and written by one thread.
function resolve(user_ids: { number }): { [number]: Names }
	const request: Request = {
		-- Cloned: the caller owns its array and is free to reuse it, and this one
		-- is read later, from another thread.
		user_ids = table.clone(user_ids),
		done = false,
		result = {},
		waiters = {},
	}
	table.insert(requests, request)
	if not running then
		running = true
		-- Deferred rather than spawned so that several callers in the same frame
		-- are all in the queue before the drainer looks at it.
		task.defer(drain)
	end

	-- The drainer cannot have answered this yet (it only runs once this thread
	-- yields), but the check is what makes the handshake safe to read: a
	-- `coroutine.yield` for a request that is already done would park this
	-- thread forever, and nothing would report it.
	if not request.done then
		table.insert(request.waiters, coroutine.running())
		coroutine.yield()
	end

	if request.failure then
		-- Level 0: the message already names where it came from, and pointing at
		-- this line instead would hide that.
		error(request.failure, 0)
	end
	return request.result
end

return table.freeze {
	resolve = resolve,
}
