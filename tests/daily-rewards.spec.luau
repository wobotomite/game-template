--!nocheck
-- shared/economy/daily-rewards: the streak rules.
-- Run with:
--   lune run tests/daily-rewards.spec.luau
--
-- WHY THIS MODULE HAS A SPEC. Everything it decides is an integer comparison
-- one character wide, and every one of them is invisible in a playtest: a
-- playtest claims once, on one day, and gets day 1. The two that go wrong are
-- the WINDOW EDGE -- which day is the last one that still continues a streak --
-- and the DAY WRAP, where two claims seconds apart either side of midnight are
-- a legal consecutive pair and two claims twenty-three hours apart inside one
-- day are not. Both are only visible on the day they are wrong, to the player
-- whose streak it was, weeks after the edit that did it.
--
-- WHAT IS NOT COVERED: `src/server/players/daily-rewards.luau`, which is the
-- transaction, and `daily-reminders.luau`, which is a MemoryStore queue. Those
-- are the engine's behaviour, not arithmetic; what this file pins is the part
-- they both ask rather than decide.

local h = require "./harness"
local env = require "./roblox-env"

h.title "daily rewards:"

local rules = env.load "ReplicatedStorage.Shared.economy.daily-rewards"
local S = env.load("ReplicatedStorage.Shared.settings").daily

-- Blindness guards. Every case below is computed FROM the settings, so an empty
-- schedule or a zero-length day would make most of them vacuously true.
h.saw("days in the schedule", #S.SCHEDULE, 1)
h.check("a day has a length", S.DAY_SECONDS > 0)
h.check("the grace window is a whole number of days", S.GRACE_DAYS % 1 == 0 and S.GRACE_DAYS >= 0)

-- ============================== the day wrap ===============================

do
	-- A day NUMBER, not a timestamp: the whole point is that these are integers.
	h.equals("time zero is day zero", rules.day_of(0), 0)
	h.equals("one second before the rollover is still today", rules.day_of(S.DAY_SECONDS - 1), 0)
	h.equals("the rollover second is tomorrow", rules.day_of(S.DAY_SECONDS), 1)
	h.equals("and a fraction of a second into it still is", rules.day_of(S.DAY_SECONDS + 0.5), 1)

	-- TWO CLAIMS SECONDS APART are consecutive days when the rollover falls
	-- between them. This is the case a rule written against elapsed TIME gets
	-- wrong -- "a day since your last claim" refuses this one.
	local before = 3 * S.DAY_SECONDS - 1
	local after = 3 * S.DAY_SECONDS + 1
	local claimed_yesterday = { streak = 4, last_day = rules.day_of(before), best_streak = 4 }
	h.check("a claim two seconds later is a new day", not rules.claimed(claimed_yesterday, rules.day_of(after)))
	h.equals("and continues the streak", rules.next_day(claimed_yesterday, rules.day_of(after)), 5)

	-- AND THE OTHER DIRECTION: most of a day later, still the same day.
	local nearly_a_day = 2 * S.DAY_SECONDS + math.floor(S.DAY_SECONDS * 0.95)
	local claimed_today = { streak = 4, last_day = rules.day_of(2 * S.DAY_SECONDS), best_streak = 4 }
	h.check("twenty-odd hours later is still claimed", rules.claimed(claimed_today, rules.day_of(nearly_a_day)))
end

-- ============================ the window edge ==============================

do
	local today = 500

	-- The window is "claimed before today, and no earlier than GRACE_DAYS whole
	-- days before yesterday". Written out from the setting rather than hard
	-- coded, so that a game which changes GRACE_DAYS gets these cases moved for
	-- it instead of a spec that disagrees with its own settings.
	local last_inside = today - 1 - S.GRACE_DAYS
	local first_outside = last_inside - 1

	h.equals("yesterday continues the streak", rules.next_day({ streak = 3, last_day = today - 1 }, today), 4)
	h.equals(
		`the oldest day inside the window ({S.GRACE_DAYS} missed) still continues it`,
		rules.next_day({ streak = 3, last_day = last_inside }, today),
		4
	)

	-- THE EDIT THIS CASE EXISTS FOR. Moving either end of that comparison by one
	-- day is a one-character change that forgives a break or breaks a streak
	-- somebody kept, and nothing else in the repo would notice.
	h.equals(
		"one day further back starts again at 1",
		rules.next_day({ streak = 3, last_day = first_outside }, today),
		1
	)

	h.equals("a save that never claimed starts at 1", rules.next_day({ streak = 0, last_day = 0 }, today), 1)

	-- A `last_day` in the FUTURE is a clock that moved backwards. It must not
	-- pay out, and it must not be read as a continued streak either.
	h.check("a future last_day counts as claimed", rules.claimed({ streak = 3, last_day = today + 1 }, today))
	h.equals("and does not continue the streak", rules.next_day({ streak = 3, last_day = today + 1 }, today), 1)
end

-- ============================ what it shows ================================

do
	local today = 500

	local day, already = rules.current({ streak = 3, last_day = today }, today)
	h.equals("a claimed record shows the day it claimed", day, 3)
	h.check("and says so", already)

	local next_day, pending = rules.current({ streak = 3, last_day = today - 1 }, today)
	h.equals("an unclaimed record shows the day on offer", next_day, 4)
	h.check("and says it is not claimed", not pending)

	h.equals(
		"best streak reads the live one when it is ahead",
		rules.best { streak = 9, last_day = today, best_streak = 4 },
		9
	)
end

-- ============================== the payout =================================

do
	-- By CONTENTS rather than by identity: whether two loads of `settings` hand
	-- back the same table is the harness's business, and a spec that depends on
	-- it is one that breaks for a reason that has nothing to do with rewards.
	local function same(got: any, want: any): boolean
		if typeof(got) ~= "table" or typeof(want) ~= "table" then
			return false
		end
		for key, value in want do
			if got[key] ~= value then
				return false
			end
		end
		for key in got do
			if want[key] == nil then
				return false
			end
		end
		return true
	end

	h.check("day 1 pays the first entry", same(rules.reward(1), S.SCHEDULE[1]))

	-- PAST THE END OF THE SCHEDULE the last entry repeats. The alternative --
	-- wrapping to day 1 -- is a deliberate choice a game makes in `tier`, and
	-- either way the answer must be a reward and never nil: `reward` feeds a
	-- credit loop and a notification, and nil there is a claim that pays nothing
	-- while still marking the day as claimed.
	local past_the_end = #S.SCHEDULE + 3
	h.check(
		"a streak longer than the schedule keeps its last day",
		same(rules.reward(past_the_end), S.SCHEDULE[#S.SCHEDULE])
	)
	h.check("and day 0 is clamped up, not indexed out", same(rules.reward(0), S.SCHEDULE[1]))

	-- The words. Only that they name the amount and the currency -- the sentence
	-- itself is `strings.daily.REWARD` and a game is free to rewrite it.
	local text = rules.reward_text(1)
	local currency, amount = next(S.SCHEDULE[1])
	h.check(
		`the reward reads as words ("{text}")`,
		text:find(tostring(amount), 1, true) ~= nil and text:find(currency, 1, true) ~= nil
	)
end

h.done()
