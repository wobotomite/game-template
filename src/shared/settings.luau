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
	commerce = {
		-- DEVELOPER PRODUCTS, as SHAPE. The ids live in `assets.products`, the
		-- names and descriptions in `strings.commerce.PRODUCTS`, and
		-- `src/shared/records/products.luau` joins the three by KEY.
		--
		-- `grants` maps a currency key from `src/shared/records/currencies.luau`
		-- to an amount, and the receipt service adds it to the save. A product
		-- that grants something else -- a consumable, an unlock -- is served by
		-- registering an `apply` with the receipt service rather than by growing
		-- this shape, because only the game knows what its own save looks like.
		--
		-- BOTH ROWS ARE EXAMPLES. Their ids in `assets.products` are `0`, so the
		-- products record leaves them out of its id lookup and nothing can be
		-- bought until real ids are pasted in. Rename them; do not ship them.
		PRODUCTS = {
			{ key = "COINS_SMALL", category = "coins", icon = "", grants = { coins = 100 } },
			{ key = "COINS_LARGE", category = "coins", icon = "", grants = { coins = 1000 } },
		},

		-- The purchase-id ledger each save carries, so a receipt Roblox delivers
		-- twice is granted ONCE. Roblox re-delivers a receipt -- across servers,
		-- across sessions -- until some server answers PurchaseGranted, so "have
		-- I already granted this" is a question only saved data can answer.
		--
		-- CAPPED BECAUSE IT IS SAVED DATA. An unbounded array grows for the life
		-- of the account and eventually eats into the profile's size budget. The
		-- OLDEST entry is evicted first, so an evicted id is one Roblox stopped
		-- retrying long ago; 200 is far more than can ever be in flight at once.
		RECEIPT_LEDGER_MAX = 200,

		-- Player attribute name per pass key, so a LocalScript can gate UI on
		-- ownership without asking the server. Keyed by the same KEY as
		-- `assets.passes`; a pass with no entry here simply gets no attribute.
		PASS_ATTRIBUTES = {},

		-- `UserOwnsGamePassAsync` fails transiently, and a failure is NOT "does
		-- not own". Treating one as the other takes a paid feature away from
		-- somebody who paid for it, which is the worst bug this section can
		-- cause, so the pass service retries and reports UNKNOWN rather than
		-- false.
		PASS_CHECK_ATTEMPTS = 3,
		PASS_CHECK_RETRY_SECONDS = 5,
	},

	-- BADGES. Retry budget for `BadgeService`, which fails transiently and must not
	-- be hammered. The badge ids themselves are in `assets.badges`.
	--
	-- Read by the badge service.
	badges = {
		-- `BadgeService` fails transiently under load, and an award it drops is
		-- never retried by the engine -- the badge is simply never granted.
		-- Three attempts two seconds apart rides out a blip without turning one
		-- award into a retry storm from every server at once.
		ATTEMPTS = 3,
		RETRY_SECONDS = 2,
	},

	-- LEADERBOARDS. Which saved counters become global boards, how often a board is
	-- read and written, and the OrderedDataStore budgets the worker stays inside.
	--
	-- Read by the leaderboard service.
	leaderboards = {
		-- WHICH SAVED COUNTERS BECOME BOARDS, in display order. Every name here is
		-- a field of the `progress` struct in `datastore/datastore-schema.luau`, and
		-- it must be a counter that only ever GROWS: a board cell is written with
		-- `math.max`, so a value that can go down would stick at its high-water mark
		-- and never come back down. A board for something that falls (a best TIME)
		-- stores its negation, or a large constant minus it.
		--
		-- An empty list turns the whole subsystem off: no stores are opened, no
		-- worker writes, no boards are published.
		ORDER = { "best_score" },

		-- The OrderedDataStore behind each board, by the same key.
		--
		-- THE NAME IS THE BOARD. Renaming one does not move or clear anything: the
		-- old scores sit untouched under the old name and the new name starts
		-- empty. That is how a season is reset -- bump the suffix -- and it is also
		-- the accident that silently wipes a live board, so treat these as
		-- published values rather than labels.
		STORES = {
			best_score = "GlobalBestScore_v1",
		},

		-- Rows fetched and published per board. 100 is the engine's page size for
		-- `GetSortedAsync`; 50 is more than a screen of names and half the traffic,
		-- and every row costs a username lookup on top of the read.
		LIMIT = 50,

		-- How long a board may be out of date. Every refresh is one OrderedRead per
		-- board for every SERVER, so this number is multiplied by the server count
		-- against a budget that is not -- two minutes keeps a hundred servers well
		-- inside it, and nobody watching a top-50 board notices the difference
		-- between that and ten seconds.
		REFRESH_SECONDS = 120,

		-- How long a new personal best is held before it is written out. A player
		-- who beats their score five times in a minute costs ONE write instead of
		-- five, and the delay is invisible because their own number comes from
		-- their save, not from the board.
		WRITE_SECONDS = 30,

		-- How long a failed write waits before it is tried again. Writes fail when
		-- the request budget is spent, and retrying immediately spends the budget
		-- that the retry needs.
		RETRY_SECONDS = 30,

		-- How often the write worker wakes. It does nothing at all unless a score
		-- is due, so this is the granularity of `WRITE_SECONDS` rather than a cost.
		WORKER_SECONDS = 1,

		-- The budget the shutdown flush gives itself. Roblox allows a server about
		-- thirty seconds inside `BindToClose` before it kills it regardless, and
		-- the save's own close has to happen inside that too -- so this leaves
		-- headroom rather than claiming the lot.
		CLOSE_SECONDS = 25,

		-- In Studio the boards are served from this server's own memory (see the
		-- service), so a refresh costs nothing and can be fast enough to watch a
		-- score appear on the board while testing.
		STUDIO_REFRESH_SECONDS = 5,

		-- The largest score that may be published: 2^53 - 1, the biggest integer a
		-- double holds EXACTLY. Past it, arithmetic starts rounding and two
		-- different scores compare equal -- and a value that big is a corrupted
		-- save or an exploit rather than a player, so the board refuses it instead
		-- of immortalising it at the top.
		MAX_VALUE = 9007199254740991,

		-- USERNAME CACHE. A board holds user ids; the names are fetched and kept.
		--
		-- How long a fetched name is trusted. Names change rarely and a stale one
		-- is a cosmetic wrong, so six hours trades correctness nobody sees for
		-- calls nobody has to make.
		NAME_TTL = 21600,

		-- How long after a failed lookup before that id is asked about again. Two
		-- minutes, because the failure is almost always a throttle and asking again
		-- straight away is what caused it.
		NAME_RETRY = 120,

		-- Ids kept in the cache. Each entry is two short strings and three numbers;
		-- two thousand of them is well under a megabyte and far more than the
		-- distinct ids a set of top-50 boards can show.
		NAME_CACHE_LIMIT = 2000,

		-- Ids per `GetUserInfosByUserIdsAsync` call. 100 is the engine's limit for
		-- that call; a larger batch is not slower, it throws.
		NAME_BATCH_SIZE = 100,

		-- The shortest gap between two of those calls. The endpoint is rate limited
		-- per server, and a cold cache facing several boards at once is exactly the
		-- moment that limit is hit -- so the batches are spaced rather than the
		-- failures retried.
		NAME_BATCH_INTERVAL = 30,
	},

	-- DAILY REWARDS. The streak schedule, the length of a "day", the grace window,
	-- and the reminder queue that tells a player a reward is ready.
	--
	-- Read by the daily reward rules and the reminder scheduler.
	daily = {
		-- The length of a reward "day", in seconds. The save holds a day NUMBER
		-- (unix time floored by this), not a timestamp, so every rule in
		-- `src/shared/economy/daily-rewards.luau` is integer comparison and the
		-- rollover is the same instant for every player and every server --
		-- midnight UTC. A shorter day here is a legitimate way to test the whole
		-- streak flow without waiting a day, and it changes the meaning of every
		-- `last_day` already saved, so it is not something to tune on a live game.
		DAY_SECONDS = 86400,

		-- What each day of the streak pays. Index = the day being claimed, and
		-- each entry is `{ [currency] = amount }` against the names in
		-- `datastore-schema`'s `currency` struct -- a key that is not a currency
		-- there is credited into the save and read by nothing.
		--
		-- EXAMPLE VALUES, rising so the seventh day is worth coming back for.
		-- Past the end of this list the LAST entry repeats forever (see `tier`),
		-- which is the shape that rewards a long streak; a game that would rather
		-- the week start over says so in that one function.
		SCHEDULE = {
			{ coins = 50 },
			{ coins = 75 },
			{ coins = 100 },
			{ coins = 150 },
			{ coins = 200 },
			{ coins = 300 },
			{ coins = 500 },
		},

		-- How many whole days a player may MISS without losing the streak. 1
		-- means yesterday and the day before both continue it, so a player who
		-- misses a single day is not punished for a timezone or a late shift --
		-- the streak is meant to bring them back, and breaking it on the first
		-- miss is what stops it doing that. 0 makes the streak strictly daily.
		GRACE_DAYS = 1,

		-- Rate limit on the claim remote: at most CLAIM_RATE claims per
		-- CLAIM_WINDOW seconds per player. Generous, because a claim is idempotent
		-- (the second one this day answers "already claimed" out of the save) and
		-- this is only here to stop a modified client spending the server's
		-- DataStore budget on a loop.
		CLAIM_RATE = 3,
		CLAIM_WINDOW = 10,

		-- THE REMINDER QUEUE. Optional, and idle until
		-- `assets.notifications.DAILY_READY` is set to a real notification string
		-- id. It schedules one experience notification per player for when their
		-- next reward comes due.
		REMINDER = {
			-- The MemoryStoreSortedMap that holds the queue. The name IS the
			-- queue: changing it abandons every reminder already scheduled.
			MAP = "DailyRewardReminders",

			-- How long after a claim the next reminder is due. One day, so the
			-- reminder lands when the next reward actually becomes claimable --
			-- clamped below to the start of the next reward day, because a claim
			-- made at 23:00 would otherwise remind them an hour after they could
			-- already have claimed again.
			DUE_AFTER = 86400,

			-- How long before the streak would BREAK the reminder must land, at
			-- the latest. Four hours of margin, so a reminder that is delivered
			-- late is still delivered in time to be acted on.
			LEAD = 14400,

			-- How often a server looks for due reminders, plus a random spread so
			-- that every server in the game does not poll the same map on the same
			-- second.
			POLL_SECONDS = 60,
			POLL_JITTER = 15,

			-- Reminders read per poll. The map is shared by every server, so this
			-- is a page size rather than a per-server workload.
			BATCH = 50,

			-- How long a server's claim on one reminder lasts. A server that takes
			-- an item and then dies mid-send has to release it eventually or that
			-- player is never reminded; ten minutes is far longer than a send takes
			-- and short enough that the reminder is still worth sending afterwards.
			LEASE_SECONDS = 600,

			-- The sort key a sent reminder is moved to. Sort keys order the map and
			-- the poll reads everything up to "now", so a sent item needs a key
			-- that sorts after every real due time; a string sorts after every
			-- number in a MemoryStore sorted map.
			DONE = "sent",

			-- The Open Cloud notification's category, for the analytics on the
			-- Creator Dashboard.
			CATEGORY = "daily_reward",
		},
	},

	-- VOICE. Names the per-player audio input the server attaches when the project
	-- turns the default voice pipeline off.
	--
	-- Read by the voice service.
	voice = {
		-- Name given to the `AudioDeviceInput` the voice service parents to each
		-- player. Named rather than left as the class default so a mixer graph
		-- can find every player's microphone by name, and so a second input
		-- created by something else is distinguishable from this one.
		INPUT_NAME = "Voice",
	},

	-- AUDIO. Bus volumes, the cue engine's voice budget and distance culling, and
	-- the named sound profiles cues are played through.
	--
	-- Read by `src/client/audio`.
	audio = {
		-- PER-BUS STARTING VOLUME, by the bus names in
		-- `src/client/audio/sound-groups.luau`. A group's volume MULTIPLIES with
		-- each sound's own, so this is the mix BETWEEN families of sound, not a
		-- master fader.
		--
		-- Music and ambience sit under the cues on purpose. Both are continuous
		-- and a cue is a moment; with every bus at 1 the only way to make a
		-- pickup chime audible over a bed is to keep pushing the chime up, and
		-- then it is too loud the moment the bed stops.
		BUS_VOLUME = {
			SFX = 1,
			UI = 1,
			AMBIENCE = 0.7,
			MUSIC = 0.5,
		},

		-- MUSIC. The crossfading playlist in `src/client/audio/music-player.luau`.
		music = {
			-- Long enough that a change of track reads as a transition rather
			-- than a cut, short enough that the two tracks are not audibly
			-- fighting for most of it.
			FADE = 1.6,
			-- Under the cue mix even after the bus volume above, because music
			-- is the thing a player stops hearing and cues are the thing they
			-- must not miss.
			VOLUME = 0.35,
			-- How long a track gets to load before it is written off. Generous:
			-- this is a streamed multi-megabyte asset on a cold client, and
			-- giving up early on a slow connection would skip through the whole
			-- playlist on join.
			LOAD_TIMEOUT = 20,
		},

		-- THE CUE ENGINE. Voice limiting, distance culling and the decay of a
		-- held bed, all of it in `Client.audio.cue`.
		cue = {
			-- The voice budget. Every cue past this preempts a lower-priority
			-- one or is dropped. A budget exists because a fight spawns cues in
			-- bursts and an unbounded engine turns that into a wall of noise
			-- with the important line buried in it -- the same reason a mixing
			-- desk has a finite number of faders.
			MAX_VOICES = 12,
			-- RollOffMinDistance as a fraction of a cue's radius: inside this
			-- the cue is at full volume, outside it falls off. Roblox attenuates
			-- by Min/distance with Min defaulting to 10 studs regardless of how
			-- far away the sound is meant to be audible, so a cue with a 200
			-- stud radius and no Min set is effectively silent at 30.
			NEAR_FRACTION = 0.1,
			-- Pitch multiplier at the very edge of a cue's radius, lerped in
			-- from 1 at the listener. Distance reads as dullness, so a far cue
			-- that is merely quieter reads as a quiet cue nearby.
			FAR_PITCH = 0.92,
			-- Default random pitch spread, when a spec does not carry its own.
			-- Without it a cue fired ten times in two seconds is audibly ONE
			-- sample played ten times, which is what makes a rapid action sound
			-- mechanical.
			JITTER = 0.05,
			-- How long a held bed takes to reach its level when it opens. A bed
			-- that snaps to full volume reads as a click.
			BED_FADE_IN = 0.35,
			-- How long after the last `hold` call a bed keeps its level before
			-- it starts decaying. Callers drive a bed from per-frame code, so a
			-- dropped frame or a slow step must not chop the sound -- the grace
			-- is what makes "stopped asking" different from "missed a frame".
			HOLD_GRACE = 0.5,
			-- The bed sweeper's period, and what a bed's gain is multiplied by
			-- on each pass once its grace has run out. Together they set how
			-- long a released bed takes to fall away: it is a fade, not a stop,
			-- because a caller that simply stops asking (its object destroyed,
			-- its state left) should not cut the sound off mid-note.
			SWEEP_INTERVAL = 0.25,
			SWEEP_DECAY = 0.5,
			-- When a fired voice is checked for having ever arrived. `Ended`
			-- never fires for an asset that failed to load, so without this a
			-- bad id leaks a Sound per play and holds a slot in the voice budget
			-- forever. Four seconds, because a cue that late has already missed
			-- the moment it was for.
			LOAD_DEADLINE = 4,
			-- Extra seconds past a voice's own length before it is swept. The
			-- sweep is a backstop for `Ended` never arriving, and taking a sound
			-- at exactly its length cuts the decay -- which reads as the audio
			-- glitching rather than as a timer.
			SWEEP_SLACK = 1,
			-- The volume a decaying bed is finally destroyed at, as a FRACTION
			-- of that bed's own volume rather than an absolute -- a quiet bed
			-- and a loud one should disappear at the same point in their own
			-- fade, not at the same number. Above zero because the decay is a
			-- halving and so never actually reaches silence; without a floor a
			-- bed nobody is asking for any more stays alive forever at an
			-- inaudible volume, holding its Sound and its sweep.
			HOLD_FLOOR = 0.01,
		},

		-- NAMED CUE MIXES, by the file that fires them. Each entry is a whole
		-- cue spec minus its asset id, so the levels of a family of sounds are
		-- readable together rather than one number per call site.
		cues = {
			-- The widget kit's own sounds. Every one is 2D (`radius = 0`): a
			-- button lives on the screen, not in the world.
			--
			-- `min_interval` is what keeps a dragged cursor or a held key from
			-- machine-gunning the same sample; the hover interval is the longest
			-- because hover is the one a moving mouse fires without being asked.
			ui = {
				HOVER = { volume = 0.035, pitch = 1, jitter = 0, min_interval = 0.09, radius = 0 },
				CLICK = { volume = 0.09, pitch = 1, jitter = 0, min_interval = 0.06, radius = 0 },
				-- Opening is pitched up against the identical close sample, so
				-- the two directions are distinguishable with one asset.
				OPEN = { volume = 0.055, pitch = 1.1, jitter = 0, min_interval = 0.12, radius = 0 },
				CLOSE = { volume = 0.045, pitch = 1, jitter = 0, min_interval = 0.12, radius = 0 },
				-- Loudest of the set: a purchase is the one UI moment a player
				-- is allowed to be sure about.
				PURCHASE = { volume = 0.28, pitch = 1, jitter = 0, min_interval = 0.08, radius = 0 },
				-- An alert is a line the game shouts at the player, so it is
				-- rarer and louder than a click, and it may not be swallowed by
				-- a burst of them.
				ALERT = { volume = 0.2, pitch = 1, jitter = 0, min_interval = 0.15, radius = 0 },
			},
		},

		-- PER-ASSET TRIM, by the key in `assets.sounds`. Two different problems,
		-- one table:
		--
		--   gain            library uploads are mastered at wildly different
		--                   levels, so the same `volume` in a spec is not the
		--                   same loudness for two ids. This is the per-asset
		--                   correction, so a spec's volume means what it says.
		--   start / finish  the usable part of an asset that has silence, a
		--                   count-in, or three more takes after the one you
		--                   wanted. Trimming here beats re-uploading and beats
		--                   every call site knowing the offsets.
		--
		-- Empty is the correct state for a fresh game: an id with no profile
		-- plays whole at gain 1.
		profiles = {},
	},

	-- BOOT. How long the client waits for data and a character before it stops
	-- waiting, and what the preloader is handed.
	--
	-- Read by `src/client/boot`.
	boot = {
		-- How often the "am I actually in yet" wait polls. Every UI script gates
		-- on that wait, so a slower interval is dead time on screen after the
		-- data has already landed. Twenty wakeups a second, only while loading,
		-- costs nothing.
		POLL_SECONDS = 0.05,
		-- The longest the client waits for a CHARACTER before it stops waiting
		-- and carries on. The wait used to be unbounded, which meant a spawn
		-- that never completed took the client's ENTIRE UI with it: no HUD, no
		-- menus, and a loading cover that never comes down. A player with no
		-- body and a working menu can at least see that something went wrong.
		SPAWN_WAIT_SECONDS = 20,
	},

	-- TRANSITION. The loading cover shown from ReplicatedFirst: its colours, fade
	-- times, and the longest it may stay up before it is removed regardless.
	--
	-- Read through the `TransitionSettings` alias in `default.project.json`, which
	-- maps this same file into ReplicatedFirst so the cover can read it before
	-- ReplicatedStorage has replicated. That is a SECOND ModuleScript instance: the
	-- values are equal, the tables are not the same objects.
	transition = {
		-- Above every other ScreenGui. The cover's whole job is to be the ONLY
		-- thing on screen, and a DisplayOrder a game picks for a HUD layer is
		-- exactly what would otherwise draw a half-built interface in front of
		-- it. Four digits so there is room to sit a game's own overlays under it.
		DISPLAY_ORDER = 1300,

		-- THE COVER COMES DOWN NO MATTER WHAT. It is dismissed by the client boot
		-- script (see DISMISS_ATTRIBUTE), and a boot that never finishes -- a
		-- profile that will not load, an error thrown before the hand-off -- would
		-- otherwise leave the player looking at a title card forever, with no way
		-- to tell that from a slow connection. After this the cover removes
		-- itself and the player at least sees the game, broken or not.
		FAILSAFE_SECONDS = 30,

		-- How long the cover takes to fade out once it is dismissed. Long enough
		-- to read as a transition rather than a cut, short enough that nobody is
		-- waiting on it.
		FADE_SECONDS = 0.6,

		-- THE INDETERMINATE BAR. With no fraction to show, the fill sweeps across
		-- the track on a loop: one pass every PULSE_SECONDS, the fill SIGNAL_WIDTH
		-- of the track wide. It says "still working" and promises nothing, which
		-- is the honest thing to draw when the boot has no progress number -- a
		-- bar that pretends to be at 40% and then sits there is worse than no bar.
		PULSE_SECONDS = 2.4,
		SIGNAL_WIDTH = 0.22,

		-- THE CONTENT BLOCK is authored at exactly this size in pixels and then
		-- scaled to fit, rather than laid out in scale units. Offsets keep the
		-- title and the bar in proportion to each other on every screen; a scale
		-- layout stretches the gap between them on a wide monitor and crushes it
		-- on a phone. VIEW_MARGIN is the breathing room left around the block, and
		-- MIN_SCALE the point past which shrinking further would be unreadable --
		-- below it the block is allowed to overflow instead.
		WIDTH = 620,
		HEIGHT = 106,
		VIEW_MARGIN = 40,
		MIN_SCALE = 0.35,

		-- Layout inside that block, top-left origin. The title band is
		-- TITLE_SIZE + RULE_GAP tall, which leaves RULE_GAP of air under the text
		-- before the bar at BAR_Y. BAR_Y + BAR_HEIGHT is HEIGHT: the bar is the
		-- bottom edge of the block.
		TITLE_Y = 0,
		TITLE_SIZE = 48,
		RULE_GAP = 28,
		BAR_Y = 100,
		BAR_HEIGHT = 6,

		-- COLOURS, AND THEY ARE A PLACEHOLDER. The cover is the first thing a
		-- player sees and it has to look like something before the game has a
		-- palette -- and it deliberately does NOT read `settings.ui`, because the
		-- widget kit's theme is a game's own look and the cover has to draw
		-- before any of it exists. So these four are picked for contrast and
		-- nothing else: a dark ground, light text, a track dark enough to read as
		-- empty, and a fill that is the same ink as the title because a template
		-- has no brand colour. This is the first block a game should overwrite.
		GROUND = Color3.fromRGB(16, 16, 18),
		INK = Color3.fromRGB(235, 235, 238),
		TRACK = Color3.fromRGB(42, 42, 48),
		ACCENT = Color3.fromRGB(235, 235, 238),

		-- HOW THE TWO SCRIPTS TALK. The cover lives in ReplicatedFirst and the
		-- boot that dismisses it lives in the client tree; they are separate
		-- scripts, started at different times, sharing no module state -- which is
		-- the whole point of ReplicatedFirst, and the reason the cover can draw
		-- before ReplicatedStorage has replicated. An attribute on the
		-- ReplicatedFirst service is the one channel both can reach without either
		-- having to exist yet: the boot sets it whenever it gets there, and the
		-- cover reads it once and then listens, so neither order is a race.
		DISMISS_ATTRIBUTE = "LoadingCoverDismissed",
	},

	-- EFFECTS. Defaults for the shared effect primitives under
	-- `src/effects/shared` -- particle bursts, rings, display ghosts.
	--
	-- Read by `src/effects`.
	effects = {
		-- THE PARTICLE BURST primitive (`src/effects/shared/burst.luau`). Only
		-- the three values every burst falls back on live here; everything else
		-- about a burst -- how many, how fast, what colour -- is the moment's
		-- own and is passed in by the effect that spawns it.
		burst = {
			-- The full hemisphere, so a burst with no direction given sprays
			-- everywhere. A caller that wants a cone passes one; a caller that
			-- forgot gets something that reads as an explosion rather than as a
			-- line of particles going one way for no reason.
			DEFAULT_SPREAD_DEG = 180,
			-- Studs. Small, because the default is for sparks and specks -- the
			-- bursts that want a big particle (smoke, mist) are the ones that
			-- always pass their own size anyway.
			DEFAULT_SIZE = 0.25,
			-- The transparency curve over a particle's life: opaque at birth,
			-- gone at death. Without a curve every particle in the burst
			-- vanishes at full opacity on the frame its lifetime ends, and a
			-- burst ending is a visible pop rather than a fade.
			FADE = NumberSequence.new {
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			},
		},

		-- THE EXPANDING RING primitive (`src/effects/shared/ring.luau`): a band
		-- that grows from one radius to another and fades out. Impacts,
		-- shockwaves, landings, anything that wants to say "from here,
		-- outwards".
		ring = {
			-- A circle drawn as this many straight boxes. The cost of a ring is
			-- linear in this number and a ring is on screen for well under a
			-- second, so the trade is roundness against parts-per-moment rather
			-- than against a frame budget that has to hold.
			SEGMENTS = 24,
			-- Each segment's height as a fraction of its width, so a ring is a
			-- flat BAND rather than a tube: it reads as a wave travelling along
			-- the ground instead of as a pipe lying on it.
			THICKNESS = 0.4,
			-- Where the fade starts. Not zero: a Neon band at full opacity reads
			-- as a solid object, and a ring is meant to read as light.
			TRANSPARENCY = 0.15,
			-- The fade runs on `alpha ^ FADE_POWER`, and this is above 1 on
			-- purpose: the ring holds its brightness through the first half of
			-- its expansion and goes in the last part. A linear fade spends the
			-- whole life half-visible, which reads as a ring that is dim rather
			-- than as one that is leaving.
			FADE_POWER = 1.6,
		},
	},

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
