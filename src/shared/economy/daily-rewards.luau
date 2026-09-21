const ReplicatedStorage = game:GetService "ReplicatedStorage"

const strings = require(ReplicatedStorage.Shared.strings)

const S = require(ReplicatedStorage.Shared.settings).daily
const T = strings.daily

-- The daily reward RULES, and nothing else: what day a streak is on, whether it
-- may be claimed, and what that day pays.
--
-- PURE, AND THAT IS THE POINT. Every function here takes the save's `daily`
-- record and the current day as arguments and touches no engine API, no clock
-- and no player -- so the claim server, a UI that previews tomorrow, and
-- `tests/daily-rewards.spec.luau` all get the same answers from the same
-- arithmetic. The version of this that reads `os.time()` internally cannot be
-- tested at a day boundary at all, which is exactly where it goes wrong.
--
-- DAYS ARE NUMBERS, NOT TIMESTAMPS. `day_of` floors unix time by
-- `settings.daily.DAY_SECONDS`, and the save holds the result. Comparing whole
-- days rather than clocks is what makes "did they claim today" a `>=` instead of
-- a question about timezones -- the rollover is midnight UTC, the same instant
-- for every player and every server in the game.

-- The `daily` struct in `datastore-schema`. `best_streak` is optional HERE only
-- so that a caller can ask about a record it has built itself (the reminder
-- scheduler does) without inventing a value it does not know.
export type Record = { streak: number, last_day: number, best_streak: number? }

-- What one day of the streak pays: `{ [currency] = amount }`, against the
-- currency names in the save.
export type Reward = { [string]: number }

-- Which reward day the unix time `time` falls in.
function day_of(time: number): number
	return time // S.DAY_SECONDS
end

-- Which SCHEDULE entry a streak day claims.
--
-- The clamp is the rule for a streak longer than the schedule: day 8 and every
-- day after it repeat the last entry, so a long streak keeps paying its best
-- rate rather than dropping back to day 1's. A game that would rather the week
-- start over replaces this one line with `(day - 1) % #S.SCHEDULE + 1`.
--
-- `math.floor` because a day arrives from the save, and a save is a file a
-- previous version of the game wrote.
function tier(day: number): number
	return math.clamp(math.floor(day), 1, #S.SCHEDULE)
end

-- The longest streak this record has ever reached. Reads the CURRENT streak too:
-- `best_streak` is only written at a claim, so mid-streak the live one is
-- already ahead of it.
function best(record: Record): number
	return math.max(record.best_streak or 0, record.streak or 0, 0)
end

-- Has this record already claimed on day `today`?
--
-- `>=`, not `==`: a `last_day` in the FUTURE means the day number moved
-- backwards under the save -- a clock correction, or `DAY_SECONDS` changed --
-- and refusing the claim until the calendar catches up is the safe direction to
-- be wrong in. `==` would pay out every day until it did.
function claimed(record: Record, today: number): boolean
	return record.last_day >= today
end

-- Which day of the streak a claim made on `today` would be.
--
-- THE GRACE WINDOW IS THIS COMPARISON. The streak continues when the last claim
-- was strictly before today (an unclaimed day exists) and no earlier than
-- `GRACE_DAYS` whole days before yesterday; anything older starts again at 1.
-- With the default `GRACE_DAYS = 1` that is "yesterday or the day before".
--
-- Moving either end of that window by one is the change this file's spec
-- watches for: it is invisible in normal play (a daily player never leaves the
-- window at all) and it silently either forgives a break or breaks a streak
-- somebody kept.
function next_day(record: Record, today: number): number
	if record.last_day < today and record.last_day >= today - 1 - S.GRACE_DAYS then
		return record.streak + 1
	end
	return 1
end

-- The day a display should show, and whether it is already claimed. One call
-- rather than two so that a UI cannot show "day 4" beside a claim button that
-- would pay day 5.
--
-- `math.max(streak, 1)`: a claimed record always has a streak of at least 1, and
-- the floor is for a save from before this feature existed.
function current(record: Record, today: number): (number, boolean)
	if claimed(record, today) then
		return math.max(record.streak, 1), true
	end
	return next_day(record, today), false
end

-- What day `day` pays.
function reward(day: number): Reward
	return S.SCHEDULE[tier(day)]
end

-- What day `day` pays, in words -- "50 coins".
--
-- HERE RATHER THAN AT EITHER CALL SITE because there are already two of them --
-- the alert a claim sends and the reminder notification -- and a UI that lists
-- the week is a third. The same sentence written twice is the same sentence
-- until somebody edits one of them.
--
-- THE KEYS ARE SORTED. Iteration order over a Luau table is not stable between
-- runs, so a two-currency reward would otherwise read "50 coins, 3 gems" one day
-- and the other way round the next -- which looks like a bug in the reward.
function reward_text(day: number): string
	const paid = reward(day)
	const currencies: { string } = {}
	for currency, amount in paid do
		if amount ~= 0 then
			table.insert(currencies, currency)
		end
	end
	table.sort(currencies)

	const parts: { string } = {}
	for _, currency in currencies do
		table.insert(parts, strings.fill(T.REWARD, { amount = paid[currency], currency = currency }))
	end
	return table.concat(parts, T.REWARD_JOIN)
end

return table.freeze {
	day_of = day_of,
	tier = tier,
	best = best,
	claimed = claimed,
	next_day = next_day,
	current = current,
	reward = reward,
	reward_text = reward_text,
}
