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
	--
	-- Prefixed DEBUG: on purpose. These come back through the same toast a real
	-- alert uses, and in a Studio session full of them the one thing you want to
	-- know at a glance is which lines are the game talking and which are you.
	debug = {
		-- A command that writes to the save reports the write, not the intent:
		-- a silent failure here looks exactly like a command that did nothing,
		-- and the usual cause is Studio API access being off.
		SAVE_FAILED = "DEBUG: SAVE FAILED -- SEE THE OUTPUT WINDOW",
		DATA_WIPED = "DEBUG: SAVE WIPED TO A FRESH ONE",
		GOD_ON = "DEBUG: GOD MODE ON",
		GOD_OFF = "DEBUG: GOD MODE OFF",
	},

	-- COMMERCE. Product and pass names and descriptions, by the same KEY as
	-- `settings.commerce.PRODUCTS`, and the line shown when a purchase is granted.
	commerce = {},

	-- LEADERBOARDS. Board titles, column headings, and the three states a board
	-- can be in besides ready: loading, empty, unavailable.
	leaderboards = {},

	-- DAILY REWARDS. Reward names and the reminder notification parameters.
	daily = {},

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
