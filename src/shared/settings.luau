-- Every tunable in the game, as data. No functions, no requires, no Instances.
--
-- WHY ONE FILE. A number that lives beside the code that reads it gets tuned by
-- whoever happens to be in that file, against nothing. Here a designer reads one
-- section top to bottom and sees every value that shapes a feature, a balance
-- pass is one diff, and two systems that must agree on a number (a hold time and
-- the bar that draws it) read the SAME constant instead of two that drift.
--
-- THE THREE FILES. `settings` holds numbers and shapes, `assets` holds ids that
-- point at something uploaded (`src/shared/assets.luau`), `strings` holds every
-- word a player reads (`src/shared/strings.luau`). A record that needs all three
-- joins them by key; the products record under `src/shared/records` is the
-- worked example.
--
-- NO TYPE ANNOTATIONS, ON PURPOSE. The type of `settings.commerce.LEDGER_MAX` is
-- inferred from the literal, so a wrong type at a read site is an analyzer error
-- for free. What the analyzer does NOT catch is a misspelled KEY read through an
-- alias (`const S = settings.audio`, then `S.VOLUMEE`): that is `nil` at run
-- time and silent in `scripts/analyze.sh`. After renaming a key, grep the old
-- name and expect zero hits.
--
-- HOW TO READ IT. Alias the section once at require time and index the alias:
--
--   const AUDIO = require(ReplicatedStorage.Shared.settings).audio
--
-- Every comment here says why the value is what it is. A bare number with no
-- reason is a number nobody will dare change.
--
-- FROZEN RECURSIVELY at the bottom, so a consumer cannot tune the game for
-- everyone by writing into a table it was handed.
function deep(t)
	for _, value in t do
		if type(value) == "table" then
			deep(value)
		end
	end
	table.freeze(t)
end

const SETTINGS = {
	-- NETWORK. Remote rate limits and payload ceilings that more than one handler
	-- shares. A limit used by exactly one handler stays beside that handler, where
	-- the reason for it is.
	--
	-- Read by `src/server/net`.
	net = {},

	-- ALERTS. The toast stack: how many are visible at once, how long one lives,
	-- and the keyword colouring `src/shared/services/alert.luau` applies to a
	-- shouted line.
	--
	-- Read by `src/shared/services/alert.luau` and the client alert page.
	alerts = {
		-- Words the alert service colours wherever they appear in a line, as
		-- WORD AND COLOUR TOGETHER rather than split across `strings` and here:
		-- a word with no colour matches nothing and a colour with no word
		-- colours nothing, so adding a highlight would otherwise be an edit in
		-- two files that silently half-works if you forget one. These are not
		-- lines a player reads either -- they are matching rules run against a
		-- line somebody else wrote.
		--
		-- UPPER CASE, because the service raises the line before it matches, so
		-- an entry in mixed case can never match anything.
		--
		-- ORDER IS LONGEST FIRST: the first entry that matches at a position
		-- wins, so a multi-word phrase has to come before any single word
		-- inside it ("FREE COINS" before "COINS") or the shorter one takes the
		-- front of the phrase and leaves the rest plain. Singular and plural
		-- are separate entries, and their order does not matter -- the
		-- service's word boundaries stop "COIN" matching inside "COINS".
		--
		-- The colour here is the coins colour from
		-- `src/shared/records/currencies.luau`; keep the two in step, or a
		-- reward line and the currency bar above it disagree about what coins
		-- look like.
		HIGHLIGHTS = {
			{ text = "COINS", color = Color3.fromRGB(255, 200, 0) },
			{ text = "COIN", color = Color3.fromRGB(255, 200, 0) },
		},
	},

	-- DEBUG. Studio-only commands and the menu that fires them. Nothing in this
	-- section is read in a published server: the remotes that would carry it do not
	-- exist there (`src/shared/network.luau`, the `debug` group).
	--
	-- Read by the debug command script and the debug menu.
	debug = {
		-- How often god mode tops a character's health back up, in seconds.
		--
		-- A POLL, not a `Humanoid.HealthChanged` handler, because damage is not
		-- the only way to die: a fall, a void, or anything that sets Health to 0
		-- outright kills between two of the events you would have hooked. A
		-- quarter second is short enough that nothing in a test survives long
		-- enough to matter and long enough that the loop is free.
		GOD_PERIOD = 0.25,
	},

	-- CHARACTER. Rig and ragdoll numbers shared by the server and client halves of
	-- character setup, so a death looks the same from both sides of the wire.
	--
	-- Read by `src/server/players/setup-ragdolls.luau`, its client twin, and
	-- `src/server/anticheat`.
	character = {
		-- Angular impulse applied to the root part the instant the humanoid dies,
		-- in the character's own frame: 90 about X is a forward topple, which
		-- reads as falling rather than as the body switching off.
		--
		-- Applied on the SERVER, in the frame before network ownership is handed
		-- back to the dying player's client, so the velocity replicates with the
		-- pose. Scale it with the rig: this is sized for a standard R15, and a
		-- heavier assembly barely moves under it.
		DEATH_SPIN = Vector3.new(90, 0, 0),

		-- The fastest a LEGITIMATE player is ever meant to travel, studs/s, by
		-- any means the server does not express as `Humanoid.WalkSpeed`: a
		-- vehicle, a launcher, a conveyor, a swim or sprint multiplier applied
		-- to the assembly rather than to the humanoid. The anticheat multiplies
		-- it by its own slack to get the speed below which it never flags, so
		-- this is the ONE number a game has to revisit when it adds a fast
		-- loadout -- and the only thing standing between that loadout and a kick.
		--
		-- 28 is a sprint over the default 16 walk, and 28 x the anticheat's 1.6
		-- slack is the 45 that used to be written into the anticheat itself.
		-- Raise it for the fast thing; do not raise it "to be safe", because
		-- every stud of headroom is a stud a speed hack gets for free.
		TOP_SPEED = 28,
	},

	-- COMMERCE. Developer products and game passes as SHAPE: what a product grants,
	-- how many times an ownership check retries. The ids are in `assets`, the names
	-- and descriptions in `strings`; the products record joins them.
	--
	-- Read by the receipt and pass services.
	commerce = {},

	-- BADGES. Retry budget for `BadgeService`, which fails transiently and must not
	-- be hammered. The badge ids themselves are in `assets.badges`.
	--
	-- Read by the badge service.
	badges = {},

	-- LEADERBOARDS. Which saved counters become global boards, how often a board is
	-- read and written, and the OrderedDataStore budgets the worker stays inside.
	--
	-- Read by the leaderboard service.
	leaderboards = {},

	-- DAILY REWARDS. The streak schedule, the length of a "day", the grace window,
	-- and the reminder queue that tells a player a reward is ready.
	--
	-- Read by the daily reward rules and the reminder scheduler.
	daily = {},

	-- VOICE. Names the per-player audio input the server attaches when the project
	-- turns the default voice pipeline off.
	--
	-- Read by the voice service.
	voice = {},

	-- AUDIO. Bus volumes, the cue engine's voice budget and distance culling, and
	-- the named sound profiles cues are played through.
	--
	-- Read by `src/client/audio`.
	audio = {},

	-- BOOT. How long the client waits for data and a character before it stops
	-- waiting, and what the preloader is handed.
	--
	-- Read by `src/client/boot`.
	boot = {},

	-- TRANSITION. The loading cover shown from ReplicatedFirst: its colours, fade
	-- times, and the longest it may stay up before it is removed regardless.
	--
	-- Read through the `TransitionSettings` alias in `default.project.json`, which
	-- maps this same file into ReplicatedFirst so the cover can read it before
	-- ReplicatedStorage has replicated. That is a SECOND ModuleScript instance: the
	-- values are equal, the tables are not the same objects.
	transition = {},

	-- EFFECTS. Defaults for the shared effect primitives under
	-- `src/effects/shared` -- particle bursts, rings, display ghosts.
	--
	-- Read by `src/effects`.
	effects = {},

	-- UI. The widget kit's theme: colours, metrics, text sizes, motion. Every
	-- visual value a widget uses comes from here, so reskinning a game is this
	-- section and `assets.fonts`, not a sweep through the widgets.
	--
	-- Read by `src/client/ui`.
	ui = {},

	-- CONTROLS. Key, gamepad and touch bindings, and the thresholds gesture
	-- recognition uses (how far is a swipe, how long is a hold).
	--
	-- Read by `src/client/input` and the input labels in the widget kit.
	controls = {},
}

deep(SETTINGS)

return SETTINGS
