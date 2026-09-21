-- Every word a player reads, as data. See the header of
-- `src/shared/settings.luau` for why the three data files exist and how they
-- are read.
--
-- WHY. Copy scattered through UI code cannot be proof-read, cannot be
-- translated, and gets two spellings of the same button. Here it is one file an
-- editor can read top to bottom, and the tone of the whole game is visible at
-- once.
--
-- `fill` IS THE ONE FUNCTION IN THE DATA FILES. It substitutes `{name}`
-- placeholders:
--
--   strings.fill(strings.commerce.GRANTED, { amount = 500 })
--
-- An unknown placeholder is LEFT IN PLACE, braces and all, rather than replaced
-- with "nil" or an empty string: a missing variable should be visible on screen
-- in a playtest, not read as a plausible sentence with a hole in it.
function deep(t)
	for _, value in t do
		if type(value) == "table" then
			deep(value)
		end
	end
	table.freeze(t)
end

function fill(template: string, vars: { [string]: any }): string
	const filled = template:gsub("{([%a_][%w_]*)}", function(name: string): string
		const value = vars[name]
		return if value == nil then "{" .. name .. "}" else tostring(value)
	end)
	return filled
end

const STRINGS = {
	-- The function rides in the same table so a call site needs one require.
	fill = fill,

	-- ALERTS. Lines the server shouts at a player through
	-- `src/shared/services/alert.luau` that are not owned by a feature below.
	alerts = {},

	-- DEBUG. What the Studio-only commands report back. Never seen by a player,
	-- kept here so the debug menu and the command script agree on the text.
	debug = {},

	-- COMMERCE. Product and pass names and descriptions, by the same KEY as
	-- `settings.commerce.PRODUCTS`, and the line shown when a purchase is granted.
	commerce = {
		-- Shouted at the buyer once the grant is SAVED, not when the receipt
		-- arrives: a line that says the purchase landed before it is durable is
		-- a line the player can be shown twice, or shown for a grant that was
		-- then lost.
		GRANTED = "<b>PURCHASE RECEIVED</b> · {name}",

		-- By the same KEY as `settings.commerce.PRODUCTS`. Both rows here are
		-- the examples that section ships; rename them together or the products
		-- record will assert on the mismatch at boot, which is the point.
		PRODUCTS = {
			COINS_SMALL = { name = "100 COINS", description = "A handful of coins." },
			COINS_LARGE = { name = "1,000 COINS", description = "A pile of coins." },
		},

		-- By the same KEY as `assets.passes`. Empty until the game has a pass.
		PASSES = {},
	},

	-- LEADERBOARDS. Board titles, column headings, and the three states a board
	-- can be in besides ready: loading, empty, unavailable.
	leaderboards = {
		-- One title per key in `settings.leaderboards.ORDER`. A board whose key is
		-- missing here has no words at all, so a display should fall back to the
		-- key rather than show nothing.
		TITLES = {
			best_score = "BEST SCORE",
		},

		-- Column headings. Shared by every board: boards differ in what the number
		-- MEANS -- which is what the title says -- not in their shape.
		RANK = "#",
		PLAYER = "PLAYER",
		SCORE = "SCORE",

		-- What a display shows instead of rows. These line up with the `status`
		-- field of a board in `src/shared/atoms/leaderboard-atoms.luau`, except
		-- EMPTY: an empty board is "ready" and correct, it just has nobody on it
		-- yet, and saying so is friendlier than a blank rectangle.
		LOADING = "Loading scores...",
		EMPTY = "No scores yet. Be the first.",
		UNAVAILABLE = "Scores are unavailable right now.",

		-- Shown ALONGSIDE the rows rather than instead of them: a stale board is
		-- last refresh's real scores, which is worth more than an empty one.
		STALE = "Scores may be out of date.",
	},

	-- DAILY REWARDS. Reward names and the reminder notification parameters.
	daily = {
		-- ONE ALERT PER VERDICT of a claim. Every path through the claim says
		-- something: a claim that answers with silence reads as a broken button,
		-- and the player presses it again.
		REWARDED = "<b>DAY {day} CLAIMED</b> · +{reward}",
		ALREADY_CLAIMED = "<b>ALREADY CLAIMED</b> · COME BACK TOMORROW",
		-- Only reachable once a game registers a gate with `set_gate`; with no
		-- gate the rewards are open to everyone and this is never shown.
		LOCKED = "<b>NOT YET</b> · DAILY REWARDS AREN'T OPEN TO YOU YET",
		FAILED = "<b>COULD NOT CLAIM</b> · TRY AGAIN LATER",

		-- ONE REWARD, IN WORDS. Used in the alert above and in the reminder
		-- notification, so `{currency}` is the key from the save -- "coins" --
		-- rather than a display name. A game with a currency called something
		-- else than its key writes that mapping here.
		REWARD = "{amount} {currency}",
		-- Between two rewards paid on the same day. Only seen by a game whose
		-- `settings.daily.SCHEDULE` pays more than one currency at once.
		REWARD_JOIN = ", ",

		-- A claim panel's own labels (a title, the day cells, the button) belong
		-- here too; the template ships no panel, so it ships none of them.
	},

	-- LOADING. The cover shown from ReplicatedFirst. Read through the
	-- `TransitionStrings` alias in `default.project.json`; see `settings.transition`.
	loading = {},

	-- UI. Words the widget kit itself shows: confirm, cancel, close, hold to
	-- confirm. A feature's own copy goes in that feature's section.
	ui = {},

	-- CONTROLS. Names of inputs as shown in a prompt ("HOLD", "TAP"), and the
	-- labels on touch buttons.
	controls = {},
}

deep(STRINGS)

return STRINGS
