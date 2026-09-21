const DataStoreService = game:GetService "DataStoreService"
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const atoms = require(ReplicatedStorage.Shared.atoms["leaderboard-atoms"])
const schema = require(ReplicatedStorage.Shared.datastore["datastore-schema"])
const rules = require(ReplicatedStorage.Shared.settings).leaderboards
const names = require(script.Parent["name-cache"])

-- Global leaderboards: the saved counters in `settings.leaderboards.ORDER`,
-- written to one OrderedDataStore each and read back as the published boards in
-- `src/shared/atoms/leaderboard-atoms.luau`.
--
-- THE ONE RULE THIS FILE IS BUILT AROUND: NEVER PUBLISH A SCORE THAT IS NOT
-- SAVED. A player's own numbers live in their lyra save; the board is a second,
-- separate copy in a DataStore lyra knows nothing about. Those two can
-- disagree, and only in one direction matters:
--
--   * board behind save -- the next write fixes it, nobody notices
--   * board AHEAD of save -- permanent. A score written to the board when the
--     save that produced it was still in memory survives a server crash that
--     rolls the save back. The player is then on the board with a number they
--     have never had and can never reproduce, there is no way to take it off
--     without wiping the board, and the only witness is a confused player.
--
-- So a score goes through three states, and the three tables below are those
-- states. `known` is what this server has SEEN, `confirmed` is what it has
-- watched being SAVED, and `pending` is what is waiting to be written out. Only
-- a value that has reached `confirmed` is ever written to a store; a value that
-- never gets there is rolled back by `discard_unsaved` when the player leaves.
--
-- `src/server/data/datastore/init.luau` is the other half: it feeds every
-- change into `queue`, every completed save into `confirm_saved`, and hands us
-- the `set_checkpoint` callback that asks it to save a player NOW.
--
-- WHAT A GAME CHANGES HERE: nothing. The boards are `settings.leaderboards` --
-- which saved field, which store name, how many rows.

type Schema = typeof(schema:type())
type Scores = { [string]: number }
type Pending = { scores: Scores, at: number }
type Row = { user_id: number, value: number }

-- In Studio the boards are served from this server's own memory instead of the
-- live stores (see `studio_rows`). WHY: a test session must never write into a
-- board real players are on -- a debug command that sets a score to a million
-- would be permanent -- and the boards still want to be visible while building
-- the UI that shows them.
const studio = RunService:IsStudio()

const stores: { [string]: OrderedDataStore } = {}
const pending: { [number]: Pending } = {}
const known: { [number]: Scores } = {}
const confirmed: { [number]: Scores } = {}

local started = false
local closing = false
local writing = false
local checkpoint: ((number) -> boolean)? = nil

-- Reads the board-worthy numbers out of a save. Anything that is not a real,
-- positive, in-range integer is DROPPED rather than clamped: a NaN, an infinity
-- or a negative is a corrupted save or an exploit, and publishing a repaired
-- version of it puts a made-up score on a permanent board.
--
-- `value == value` is the NaN check -- NaN is the only value not equal to
-- itself, and it beats every comparison it is put through, so an unfiltered one
-- reaches the top of a board and stays there.
function board_values(data: Schema): Scores
	const progress = data.progress :: any
	const out: Scores = {}
	for _, key in rules.ORDER do
		const value = progress[key]
		if type(value) == "number" and value == value and value > 0 and value <= rules.MAX_VALUE then
			-- OrderedDataStore values are integers. A fraction is not an error
			-- here, it is simply not storable, so it is floored rather than
			-- refused.
			out[key] = math.floor(value)
		end
	end
	return out
end

-- Valid as an OrderedDataStore key AND as a user id. Guest and negative ids
-- exist, and a fractional one can only come from a corrupted call.
function usable_id(user_id: number): boolean
	return user_id > 0 and user_id % 1 == 0
end

-- Every change to a player's save arrives here. Records any new high-water mark
-- and schedules it to be written out.
--
-- HIGH-WATER MARK, NOT LAST VALUE: `queue` is called for every change to the
-- whole save, including ones that have nothing to do with these counters, and
-- including the load itself. Taking only increases means a save whose counter
-- was rolled back (a refund, a reset, a migration) cannot pull a board down,
-- and that a hundred unrelated changes cost nothing.
function queue(user_id: number, data: Schema)
	if not usable_id(user_id) then
		return
	end
	const scores = known[user_id] or {}
	const changed: Scores = {}
	for key, value in board_values(data) do
		if value > (scores[key] or 0) then
			scores[key] = value
			changed[key] = value
		end
	end
	known[user_id] = scores

	if next(changed) == nil or studio then
		return
	end
	const entry = pending[user_id]
	if entry then
		-- Already waiting to be written: fold the new values in and let the
		-- existing deadline stand, so a player who improves repeatedly is still
		-- one write rather than one per improvement.
		for key, value in changed do
			entry.scores[key] = math.max(entry.scores[key] or 0, value)
		end
	else
		pending[user_id] = { scores = changed, at = os.clock() + rules.WRITE_SECONDS }
	end
end

-- Called once a save has actually been WRITTEN. Everything in it is now allowed
-- onto the boards.
function confirm_saved(user_id: number, data: Schema)
	-- A save that completed may carry values this server never saw change --
	-- most obviously the load, which is where a returning player's existing
	-- scores come from.
	queue(user_id, data)
	if not usable_id(user_id) then
		return
	end

	const saved = confirmed[user_id] or {}
	for key, value in board_values(data) do
		saved[key] = math.max(saved[key] or 0, value)
	end
	confirmed[user_id] = saved

	-- If they have already left, there is no later save coming: let whatever is
	-- pending go out on the next pass instead of waiting out `WRITE_SECONDS` on
	-- a player who is gone, and forget them entirely if nothing is pending.
	if not Players:GetPlayerByUserId(user_id) then
		const entry = pending[user_id]
		if entry then
			entry.at = 0
		else
			known[user_id] = nil
			confirmed[user_id] = nil
		end
	end
end

-- Registered by the datastore module: "save this player's data right now, and
-- tell me whether you did". Called from `flush_once` when a score is due to be
-- written but has not been confirmed saved yet.
function set_checkpoint(callback: (number) -> boolean)
	checkpoint = callback
end

-- The rollback. Called when a player's session ends WITHOUT their latest
-- numbers having been saved -- the crash case, and the reason `known` and
-- `confirmed` are two tables instead of one.
function discard_unsaved(user_id: number)
	const saved = confirmed[user_id] or {}
	const entry = pending[user_id]
	if entry then
		for key, value in entry.scores do
			if value > (saved[key] or 0) then
				-- Drop back to the saved value, which may be nil -- meaning this
				-- key has nothing publishable at all and the entry goes empty.
				entry.scores[key] = saved[key]
			end
		end
		if next(entry.scores) == nil then
			pending[user_id] = nil
		end
	end
	if Players:GetPlayerByUserId(user_id) or pending[user_id] then
		-- Still here (or still owed a write), so keep tracking them -- but from
		-- the saved numbers, so the unsaved ones cannot be re-queued as a "new"
		-- high-water mark.
		known[user_id] = table.clone(saved)
	else
		known[user_id] = nil
		confirmed[user_id] = nil
	end
end

-- One pass of the write worker. Yields (DataStore calls do), and is never run
-- twice at once -- see `write_pending`.
function flush_once()
	const ids: { number } = {}
	for user_id in pending do
		table.insert(ids, user_id)
	end

	for _, user_id in ids do
		const entry = pending[user_id]
		-- Re-read rather than captured above: this loop yields, and a player can
		-- be dropped from `pending` while it does.
		if entry == nil or os.clock() < entry.at then
			continue
		end

		-- A snapshot, because `entry.scores` can grow while the writes below
		-- yield and a value that arrived mid-pass has not been through the
		-- confirmation check.
		const candidates = table.clone(entry.scores)
		const saved = confirmed[user_id]

		local needs_save = false
		for key, value in candidates do
			if value > (if saved then saved[key] or 0 else 0) then
				needs_save = true
				break
			end
		end
		-- Something is due that has not been saved yet. Ask the datastore to save
		-- it now; that is what moves it into `confirmed` (through
		-- `confirm_saved`) and makes it publishable on this same pass. Skipped
		-- while closing, because the shutdown is already saving everything and a
		-- second save would compete with it for the remaining seconds.
		const save_now = checkpoint
		if needs_save and save_now and not closing then
			const ok, err = pcall(save_now, user_id)
			if not ok then
				warn(`[leaderboards] checkpoint for {user_id} failed: {tostring(err)}`)
			end
		end

		for key, value in candidates do
			-- STILL not confirmed saved -- the checkpoint above declined or
			-- failed. Leave it pending; it is retried, and it is never published
			-- from memory.
			if value > (if confirmed[user_id] then confirmed[user_id][key] or 0 else 0) then
				continue
			end
			-- Each write is an OrderedWrite and a read of the previous value.
			-- Out of budget means the next call would THROTTLE (block for
			-- seconds, then fail anyway), so the pass stops here and the rest
			-- stays pending.
			if
				DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedWrite) < 1
				or DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedRead) < 1
			then
				break
			end

			const ok, err = pcall(function()
				stores[key]:UpdateAsync(tostring(user_id), function(previous)
					-- `math.max` against what is already there, because another
					-- server may hold a higher score for this player (they were
					-- teleported, or two sessions overlapped) and the board must
					-- not go backwards.
					return math.max(if type(previous) == "number" then previous else 0, value)
				end)
			end)
			if ok then
				-- Only clear what was actually written: `queue` may have raised
				-- this key while the call yielded, and that newer value is still
				-- owed a write.
				if entry.scores[key] == value then
					entry.scores[key] = nil
				end
			else
				warn(`[leaderboards] write {key}/{user_id} failed: {tostring(err)}`)
			end
		end

		if next(entry.scores) == nil then
			-- Guarded because `pending[user_id]` may have been replaced entirely
			-- while this pass yielded.
			if pending[user_id] == entry then
				pending[user_id] = nil
			end
			if not pending[user_id] and not Players:GetPlayerByUserId(user_id) then
				known[user_id] = nil
				confirmed[user_id] = nil
			end
		else
			entry.at = os.clock() + rules.RETRY_SECONDS
		end
	end
end

-- The worker's entry point. `writing` is a re-entrancy guard, not a lock: the
-- worker loop and the shutdown flush both call this, and two passes at once
-- would each see the other's half-written `pending` and double up the writes.
function write_pending()
	if writing or studio then
		return
	end
	writing = true
	const ok, err = pcall(flush_once)
	writing = false
	if not ok then
		warn(`[leaderboards] write pass failed: {tostring(err)}`)
	end
end

-- The Studio stand-in for a store read: the board, built from the scores this
-- server happens to know about. Enough to see rows, names and sorting in a test
-- session without a single live call.
function studio_rows(key: string): { Row }
	const rows: { Row } = {}
	for user_id, scores in known do
		const value = scores[key] or 0
		if value > 0 then
			table.insert(rows, { user_id = user_id, value = value })
		end
	end
	-- Ties broken by user id so the order is stable between refreshes; a board
	-- that reshuffles equal scores every two minutes reads as a bug.
	table.sort(rows, function(a, b)
		return if a.value == b.value then a.user_id < b.user_id else a.value > b.value
	end)
	while #rows > rules.LIMIT do
		table.remove(rows)
	end
	return rows
end

-- Reads every board and publishes them. Yields.
function refresh()
	const rows_by_key: { [string]: { Row } } = {}
	const ids: { number } = {}
	const seen: { [number]: true } = {}

	for _, key in rules.ORDER do
		local rows: { Row }? = nil
		if studio then
			rows = studio_rows(key)
		elseif DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedList) >= 1 then
			const ok, result = pcall(function()
				-- `false` is descending: the highest score is rank 1. Page 1 of
				-- `LIMIT` rows is the whole board.
				return stores[key]:GetSortedAsync(false, rules.LIMIT, 1):GetCurrentPage()
			end)
			if ok then
				rows = {}
				for _, entry in result do
					const user_id = tonumber(entry.key)
					-- A key that is not a user id was written by something that is
					-- not this file. Skipped rather than shown as user 0.
					if user_id and usable_id(user_id) then
						table.insert(rows :: { Row }, { user_id = user_id, value = entry.value })
					end
				end
			else
				warn(`[leaderboards] read {key} failed: {tostring(result)}`)
			end
		end
		if rows then
			rows_by_key[key] = rows
			for _, row in rows do
				if not seen[row.user_id] then
					seen[row.user_id] = true
					table.insert(ids, row.user_id)
				end
			end
		end
	end

	-- One name lookup for every board at once: the same player is usually on
	-- more than one of them.
	const resolved = names.resolve(ids)

	const snapshot: { [string]: atoms.Board } = {}
	for _, key in rules.ORDER do
		const rows = rows_by_key[key]
		const previous = atoms.boards()[key]
		if not rows then
			-- This board could not be read. KEEP THE OLD ROWS and say they are
			-- stale: last refresh's real scores are worth more than a blank
			-- board, and a display can say so. Only a board that has never been
			-- read at all is "unavailable".
			snapshot[key] = {
				entries = if previous then previous.entries else {},
				updated_at = if previous then previous.updated_at else 0,
				status = if previous and previous.updated_at > 0 then "stale" else "unavailable",
			}
			continue
		end
		const entries: { atoms.Entry } = {}
		for _, row in rows do
			const user = resolved[row.user_id]
			-- An unresolved name is sent as empty rather than dropping the row:
			-- the rank and the score are right, and the name arrives next
			-- refresh. Dropping it would silently shorten the board.
			table.insert(entries, {
				user_id = row.user_id,
				username = if user then user.username else "",
				display_name = if user then user.display_name else "",
				value = row.value,
			})
		end
		snapshot[key] = { entries = entries, updated_at = os.time(), status = "ready" }
	end
	-- Written as ONE snapshot: a client that reads during a refresh sees every
	-- board from the same moment, never half of the new ones.
	atoms.boards(snapshot)
end

-- Shutdown, part one: stop the worker loops and say how long the flush may take.
-- Called from `src/server/data/lifecycle.luau` BEFORE the save's own close, so
-- that the saves happening in there are not competing with a write pass.
function begin_close(): number
	closing = true
	return os.clock() + rules.CLOSE_SECONDS
end

-- Shutdown, part two: write out what is left, after the saves have finished.
-- By this point every pending score either reached `confirmed` during the close
-- or never will, so this publishes exactly the ones that are durable.
function close(deadline: number)
	closing = true
	for _, entry in pending do
		entry.at = 0
	end
	-- `writing` still guards each pass; the deadline is what stops this loop
	-- from being the reason Roblox kills the server mid-write.
	while next(pending) ~= nil and os.clock() < deadline do
		write_pending()
		task.wait(rules.WORKER_SECONDS)
	end
end

function start()
	if started then
		return
	end
	started = true

	-- An empty ORDER turns the whole subsystem off: no stores, no workers, no
	-- published boards. `queue` and `confirm_saved` stay callable and do
	-- nothing, so the datastore module does not need to know.
	if #rules.ORDER == 0 then
		return
	end

	if not studio then
		for _, key in rules.ORDER do
			stores[key] = DataStoreService:GetOrderedDataStore((rules.STORES :: { [string]: string })[key])
		end
	end

	-- Published before the first read finishes, so a client that opens the board
	-- UI in the first two minutes gets "loading" rather than a missing key it
	-- has to invent a meaning for.
	const initial: { [string]: atoms.Board } = {}
	for _, key in rules.ORDER do
		initial[key] = { entries = {}, updated_at = 0, status = "loading" }
	end
	atoms.boards(initial)

	Players.PlayerRemoving:Connect(function(player)
		-- Same reasoning as the tail of `confirm_saved`: no later save is coming,
		-- so stop waiting on one.
		const entry = pending[player.UserId]
		if entry then
			entry.at = 0
		else
			known[player.UserId] = nil
			confirmed[player.UserId] = nil
		end
	end)

	task.spawn(function()
		while not closing do
			write_pending()
			task.wait(rules.WORKER_SECONDS)
		end
	end)

	task.spawn(function()
		while not closing do
			const ok, err = pcall(refresh)
			if not ok then
				warn(`[leaderboards] refresh failed: {tostring(err)}`)
			end
			task.wait(if studio then rules.STUDIO_REFRESH_SECONDS else rules.REFRESH_SECONDS)
		end
	end)
	-- EVERY server refreshes, because in a single-place game every server has
	-- players who can see the boards. A game where only one place shows them
	-- (a lobby, a hub) should gate this loop on `place_context.is "lobby"` --
	-- see `src/shared/place-context.luau` -- since the read budget is spent per
	-- server and a place that shows nothing should not spend it.
end

return table.freeze {
	queue = queue,
	confirm_saved = confirm_saved,
	discard_unsaved = discard_unsaved,
	set_checkpoint = set_checkpoint,
	begin_close = begin_close,
	close = close,
	start = start,
}
