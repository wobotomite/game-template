const HttpService = game:GetService "HttpService"
const MemoryStoreService = game:GetService "MemoryStoreService"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const ServerScriptService = game:GetService "ServerScriptService"

const assets = require(ReplicatedStorage.Shared.assets)
const rules = require(ReplicatedStorage.Shared.economy["daily-rewards"])

const S = require(ReplicatedStorage.Shared.settings).daily
const R = S.REMINDER

-- "Your daily reward is ready" -- an experience notification, sent while the
-- player is not in the game.
--
-- OFF BY DEFAULT, AND SILENT ABOUT IT. A notification needs a string authored on
-- the Creator Dashboard (`assets.notifications.DAILY_READY`) and the Open Cloud
-- package in ServerScriptService, neither of which a template can ship. With the
-- id unset this module schedules nothing and starts nothing, which is why the
-- claim path can call `schedule` unconditionally.
--
-- WHY A MEMORYSTORE AND NOT A `task.delay`. The reminder is due a day after the
-- claim; a Roblox server lives for minutes. The due time has to outlive the
-- server that set it, be visible to whichever server is running a day later, and
-- be delivered exactly once between all of them. A sorted map keyed by user id,
-- with the DUE TIME AS THE SORT KEY, is all three: "what is due now" is a range
-- read from the start of the map up to now.
--
-- WHY A LEASE. Every server in the game polls the same map, and they will see
-- the same due item in the same second. Taking the item means an `UpdateAsync`
-- that writes a GUID into it and pushes its sort key into the future; only the
-- server whose GUID survives that write sends. Without it, a player with a
-- twenty-server game gets twenty notifications, and Roblox rate limits the
-- account rather than the mistake.

-- What is queued for one player: which streak day the reminder is about, when it
-- stops being worth sending, and the lease held on it right now.
type Reminder = { day: number, ends: number, token: string? }

-- The slice of the Open Cloud package this file uses. Typed structurally rather
-- than by require, because the package is not there at all in most places.
type Sender = { createUserNotification: (number, any) -> any }

-- `false` means "looked, and there is nothing" -- distinct from `nil`, which
-- means "have not looked yet". Without that distinction a game with no
-- notification set repeats the whole search on every single poll.
local loaded_sender: Sender | false | nil = nil
local store: MemoryStoreSortedMap? = nil

function sender(): Sender?
	if loaded_sender ~= nil then
		return loaded_sender or nil
	end
	loaded_sender = false

	if assets.notifications.DAILY_READY == "" then
		-- Not an error and not a warning: no notification string is the default
		-- state of a new game, and saying so every minute would train everyone
		-- to ignore this file's output.
		return nil
	end

	const package = ServerScriptService:FindFirstChild "OpenCloud"
	const version = package and package:FindFirstChild "V2"
	const module = version and version:FindFirstChild "UserNotification"
	if not (module and module:IsA "ModuleScript") then
		-- This one IS worth a warning: somebody set the id, so they meant to
		-- turn this on, and the missing package is the only reason it is not.
		warn "[daily-reminders] DAILY_READY is set but ServerScriptService.OpenCloud.V2.UserNotification is missing"
		return nil
	end

	const ok, api = pcall(require, module)
	if not ok or typeof(api) ~= "table" or typeof(api.createUserNotification) ~= "function" then
		warn(`[daily-reminders] could not load the OpenCloud package: {tostring(api)}`)
		return nil
	end
	loaded_sender = api
	return api
end

-- Memoised: `GetSortedMap` is a handle, and one per call would be one per poll.
function reminders(): MemoryStoreSortedMap
	const existing = store
	if existing then
		return existing
	end
	const created = MemoryStoreService:GetSortedMap(R.MAP)
	store = created
	return created
end

-- Queues a reminder for the player who just claimed day `day`. Does not yield:
-- the write is spawned, because a claim must not wait on a MemoryStore call, and
-- a reminder that fails to queue is worth strictly less than the claim it would
-- have delayed.
function schedule(user_id: number, day: number, now: number)
	if sender() == nil then
		return
	end

	const today = rules.day_of(now)
	-- Two days out: the reward day after tomorrow is the one the streak dies on
	-- (with the default `GRACE_DAYS = 1`), so past this the reminder is about a
	-- streak that has already gone, and the item expires rather than being sent.
	const ends = (today + 2) * S.DAY_SECONDS
	-- A day from now, but never before the next reward day starts -- a claim
	-- made at 23:00 would otherwise remind them an hour AFTER they could have
	-- claimed again -- and never so late that there is no time to act on it.
	const due = math.clamp(now + R.DUE_AFTER, (today + 1) * S.DAY_SECONDS, ends - R.LEAD)

	const reminder: Reminder = {
		-- Which day the NEXT claim will be, asked of the same rules the claim
		-- will use rather than by adding one here: what the notification
		-- promises and what the claim pays are then the same number by
		-- construction. `today + 1` is the day it is being claimed on.
		day = rules.tier(rules.next_day({ streak = day, last_day = today }, today + 1)),
		ends = ends,
	}

	task.spawn(function()
		const ok, err = pcall(function()
			-- Expiry and sort key are both set here: the item cleans itself up
			-- if nothing ever sends it, and sorts by when it is due.
			reminders():SetAsync(tostring(user_id), reminder, ends - now, due)
		end)
		if not ok then
			warn(`[daily-reminders] could not schedule {user_id}: {tostring(err)}`)
		end
	end)
end

-- Takes one due item, and sends it if the lease is ours. YIELDS.
function deliver(api: Sender, item: { key: string, value: any, sortKey: any }, now: number)
	const value = item.value
	const user_id = tonumber(item.key)
	-- Shape-checked because this came out of a shared store that any version of
	-- this game may have written, and `now >= ends` is a reminder that sat in the
	-- queue past the streak it was about.
	if user_id == nil or typeof(value) ~= "table" or typeof(value.ends) ~= "number" or now >= value.ends then
		return
	end

	const token = HttpService:GenerateGUID(false)
	const leased: Reminder? = reminders():UpdateAsync(
		item.key,
		function(old: Reminder?, sort_key: any): (Reminder?, number?)
			-- Every check is re-run INSIDE the update, against the value the update
			-- actually read. The range read above is a snapshot, and between it and
			-- this line another server has had time to take the item, send it and
			-- push its sort key forward -- `sort_key > now` is that other server's
			-- lease, and returning nil here aborts rather than steals it.
			if old == nil or typeof(sort_key) ~= "number" or sort_key > now or now >= old.ends then
				return nil
			end
			if typeof(old.day) ~= "number" or S.SCHEDULE[old.day] == nil then
				-- A day the schedule no longer has: the schedule was shortened
				-- while this was queued. Dropping it is better than sending a
				-- notification about a reward that does not exist.
				return nil
			end
			return { day = old.day, ends = old.ends, token = token }, now + R.LEASE_SECONDS
		end,
		value.ends - now
	)

	-- `UpdateAsync` returns what is in the map, which is not necessarily what we
	-- wrote: another server's write can land first and ours is then discarded.
	-- The token is how that is told apart from success.
	if leased == nil or leased.token ~= token then
		return
	end

	const result = api.createUserNotification(user_id, {
		payload = {
			messageId = assets.notifications.DAILY_READY,
			type = "MOMENT",
			-- The dashboard string declares these names; a string that uses one
			-- this does not send renders with the placeholder still in it.
			parameters = {
				day = { stringValue = tostring(leased.day) },
				reward = { stringValue = rules.reward_text(leased.day) },
			},
			analyticsData = { category = R.CATEGORY },
		},
	})

	const status = if typeof(result) == "table" then result.statusCode else nil
	if typeof(status) ~= "number" or status >= 500 then
		-- Their fault, so it is worth trying again: the item is NOT marked done,
		-- and the lease expires on its own in `LEASE_SECONDS`.
		warn(`[daily-reminders] notification for {user_id} failed with {tostring(status)}, retrying later`)
		return
	end
	if status ~= 200 then
		-- Our fault (a bad message id, a parameter the string does not declare,
		-- a player who has notifications off). Retrying would fail identically
		-- every time, so it is marked done below and said out loud here.
		const problem = if typeof(result.error) == "table" then result.error.message else nil
		warn(`[daily-reminders] notification for {user_id} refused with {status}: {tostring(problem)}`)
	end

	reminders():UpdateAsync(item.key, function(old: Reminder?): (Reminder?, string?)
		-- Only OUR lease is marked done. If it expired and another server has
		-- since taken the item, that server owns what happens to it now.
		if old == nil or old.token ~= token then
			return nil
		end
		-- A string sort key sorts after every numeric one, so a sent item is
		-- past the end of every "due by now" range read without being deleted --
		-- it still expires on its own.
		return old, R.DONE
	end, math.max(leased.ends - os.time(), 1))
end

function poll(api: Sender)
	const now = os.time()
	-- Everything from the start of the map up to now: due, and not leased by
	-- somebody else (a lease pushes the sort key past `now`).
	for _, item in reminders():GetRangeAsync(Enum.SortDirection.Ascending, R.BATCH, nil, { sortKey = now }) do
		-- One pcall per item rather than one for the batch: a single malformed
		-- item must not stop the forty-nine behind it.
		const ok, err = pcall(deliver, api, item, now)
		if not ok then
			warn(`[daily-reminders] could not remind {item.key}: {tostring(err)}`)
		end
	end
end

local started = false
function start()
	if started then
		return
	end
	started = true

	const api = sender()
	if api == nil then
		return
	end

	task.spawn(function()
		while true do
			-- The jitter is not cosmetic: every server in the game starts its
			-- loop at roughly the same moment (a game update restarts them all),
			-- and a fixed interval keeps them in step forever -- so every poll
			-- is a thundering herd on one map, and all but one of them does no
			-- work. Waiting FIRST also means a server that is about to be shut
			-- down again does not poll at all.
			task.wait(R.POLL_SECONDS + math.random() * R.POLL_JITTER)
			const ok, err = pcall(poll, api)
			if not ok then
				warn(`[daily-reminders] poll failed: {tostring(err)}`)
			end
		end
	end)
end

return table.freeze {
	schedule = schedule,
	start = start,
}
