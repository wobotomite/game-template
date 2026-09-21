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

	-- ALERTS. The keyword colouring `src/shared/services/alert.luau` applies to a
	-- shouted line. How the toast stack LOOKS (how many are visible, how long one
	-- lives) is the client page's, in `ui.ALERTS` below.
	--
	-- Read by `src/shared/services/alert.luau`.
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

		-- THE RAGDOLL'S JOINT LIMITS, read by
		-- `src/client/character/setup-ragdolls.luau`.
		--
		-- A BallSocketConstraint with `LimitsEnabled` off is free in all three axes.
		-- A rig assembled entirely out of free sockets is a physics object rather than
		-- a body: elbows fold the wrong way, a forearm spins around its own length,
		-- and the head rotates past the shoulders. The limits are what make the same
		-- simulation produce a pose a player reads as a person.
		--
		-- Degrees. `UpperAngle` is the half-angle of the cone the socket may swing
		-- within; the twist pair is rotation about the joint's own axis, written
		-- symmetrically (-twist, +twist) because no joint on a stock rig is lopsided.
		--
		-- THE THREE GROUPS exist because one number cannot serve all of them. The
		-- geometry, not a preference:
		--
		--   torso   the least swing, the most twist. Give the waist a limb's 70-degree
		--           cone and the body folds in half at the middle.
		--   limbs   the most swing, the least twist. A limb's range IS its swing arc;
		--           twist along the bone is the axis it barely has.
		--   neck    tighter than either, and tighter again when the far side of the
		--           joint is the Head -- which is the part a viewer is looking at, and
		--           so the one where an impossible angle is unmistakable.
		--
		-- The figures themselves are carried over unchanged from the game this came
		-- from; they are a starting point that produced a readable corpse on a stock
		-- rig, not a derivation. Retune them per game.
		RAGDOLL_JOINT = {
			TORSO_TWIST = 45,
			TORSO_SWING = 35,
			LIMB_TWIST = 20,
			LIMB_SWING = 70,
			NECK_TWIST = 30,
			NECK_SWING = 30,
			HEAD_SWING = 25,
		},
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
	ui = {
		-- COLOURS. Seven names, and the whole kit reads one of them: no widget
		-- under `src/client/ui/kit` writes a literal colour. A reskin is this
		-- table plus `assets.fonts`, which is the only reason the kit is worth
		-- copying into a second game.
		--
		-- The defaults are a dark console palette: near-black panels, one bright
		-- outline hue that doubles as the "pressed" fill, and text a long way off
		-- pure white so an outline still reads against it.
		COLORS = {
			-- Body text. Not `Color3.new(1, 1, 1)`: pure white against a near
			-- black panel is the one pairing that makes a 1px text outline
			-- invisible, and the outline is what keeps HUD text legible over
			-- the world.
			TEXT = Color3.fromRGB(200, 225, 250),
			-- Secondary text -- captions, unselected labels, key caps. Dimmer
			-- than TEXT by enough to rank at a glance, not so much that it
			-- reads as disabled.
			TEXT_DIM = Color3.fromRGB(155, 181, 205),

			-- Panel fill. Also the text colour of an INVERTED button, where
			-- background and foreground swap, so it has to stay dark enough to
			-- read on top of OUTLINE.
			PANEL_BG = Color3.fromRGB(2, 6, 12),
			-- Button fill at rest, a shade up from the panel it sits on so a
			-- button is findable before it is hovered.
			BUTTON_BG = Color3.fromRGB(5, 16, 32),

			-- Every border, rule and divider, and the fill of a hovered or
			-- held button. One hue doing both jobs is what makes the kit look
			-- like one system.
			OUTLINE = Color3.fromRGB(60, 160, 255),
			-- The selection highlight: the hotbar diamond behind the chosen
			-- slot. Kept separate from OUTLINE so a game can make "chosen"
			-- louder than "bordered" without touching every border.
			ACCENT = Color3.fromRGB(90, 190, 255),
			-- Destructive actions only -- the button that wipes something.
			-- Warm, because every other colour here is cold and the contrast is
			-- the warning.
			DANGER = Color3.fromRGB(255, 80, 70),
		},

		-- METRICS. Sizes in DESIGN pixels: every one is passed through
		-- `util/ui/hooks/px`, which scales it for the viewport, so these are
		-- read at the 1280x832 base resolution and never as final pixels.
		METRICS = {
			-- The icon source grid. `kit/icon` and `kit/lock-icon` snap to an
			-- INTEGER multiple of this, so a 32px sprite drawn at 80px shows as
			-- 64px centred rather than as a blurred 2.5x. Change it only with
			-- the art.
			ICON_NATIVE_SIZE = 32,
			-- Padding from a window's border to its contents.
			INSET = 12,
			-- The single gap between stacked things -- list rows, button
			-- columns, hotbar slots. One number, so nothing in the kit can
			-- disagree with anything else about spacing.
			GAP = 6,
			-- Default label size, and the caption size of every button.
			TEXT = 18,

			-- Button height. Fixed rather than hugging the text, because a
			-- footer row of buttons with different captions must line up.
			ACTION_HEIGHT = 44,
			-- Left and right padding inside a button that hugs its text. Also
			-- the inset a hold-button's fill starts from, so the fill covers
			-- the padding rather than stopping short of it.
			BUTTON_PAD = 10,

			-- The title plate: text size and the height of the plate itself.
			-- The plate straddles the window's top border -- half of
			-- TITLE_HEIGHT is above it -- so the window reserves exactly
			-- TITLE_HEIGHT / 2 of headroom, and these two move together.
			TITLE_TEXT = 22,
			TITLE_HEIGHT = 32,
			-- Window border thickness, in the same design pixels; the border is
			-- drawn inside the frame, so the sheet is inset by it on each side.
			WINDOW_STROKE = 2,
			-- How fast a window wipes open and shut, as an exponential
			-- approach rate (see `util/numbers/approach`): the gap left after a
			-- second is exp(-rate), so 16 is "instant but not a pop".
			WIPE_RATE = 16,

			-- HOTBAR SLOTS. A slot is a fixed box; everything inside it is
			-- positioned off these, and the whole bar is laid out by a list
			-- layout at METRICS.GAP.
			SLOT_WIDTH = 96,
			SLOT_HEIGHT = 124,
			-- The key-cap corner: its box and its text.
			SLOT_KEY_TEXT = 16,
			SLOT_KEY_HEIGHT = 20,
			-- The right-hand badge (a count, a charge, a cooldown). Wide
			-- enough for three digits at SLOT_BADGE_TEXT.
			SLOT_BADGE_WIDTH = 40,
			SLOT_BADGE_TEXT = 16,
			-- The slot's own name label under the icon.
			SLOT_NAME_TEXT = 20,
			-- Padding inside the slot box, so neighbouring slots do not touch
			-- when the bar is full.
			SLOT_INSET = 6,
			-- How far the selected (or hovered) slot's contents rise. Small on
			-- purpose: the lift is a confirmation, not an animation to watch.
			SLOT_LIFT = 4,
			-- Approach rate for the lift and the diamond's turn. High enough
			-- that switching slots feels like a switch and not a slide.
			SLOT_RESPONSE = 18,
			-- The rotated square behind a selected slot. ANGLE is the resting
			-- 45 degrees that makes a square a diamond; TURN is the extra
			-- rotation applied while selected, so selection reads even in
			-- greyscale.
			SLOT_DIAMOND_SIZE = 64,
			SLOT_DIAMOND_ANGLE = 45,
			SLOT_DIAMOND_TURN = -10,
			-- The diamond is a wash behind the icon, never a solid plate: at 0
			-- it hides the icon it is meant to be highlighting.
			SLOT_DIAMOND_TRANSPARENCY = 0.2,
		},

		-- STYLE. The kit's surface treatment -- strokes, transparencies, the
		-- blink -- as opposed to the SIZES in METRICS. Split from METRICS
		-- because a reskin usually wants one and not the other.
		STYLE = {
			-- When an eased value is close enough to its target to be SNAPPED
			-- to it and the per-frame step disconnected. Exponential approach
			-- never arrives (see `util/numbers/approach`), so without a
			-- settle threshold every eased value in the kit holds a
			-- RenderStepped connection forever.
			SETTLED = 0.002,

			-- Border thickness in design pixels, and the two transparencies a
			-- border is drawn at: SOFT at rest, DIM when the control is
			-- disabled. A hovered control passes 0 (fully opaque) explicitly.
			STROKE = 1,
			STROKE_SOFT = 0.35,
			STROKE_DIM = 0.75,
			-- Rules and dividers sit a step fainter than a resting border, so a
			-- divider inside a panel does not compete with the panel's own edge.
			RULE_SOFT = 0.55,
			-- The rule between a window's body and its footer buttons, in design
			-- pixels. Its own key because the window RESERVES this height when
			-- it measures the footer; a divider that draws thicker than the
			-- space reserved for it clips the top button.
			WINDOW_RULE = 1,

			-- Text outline: colour, thickness, and how far it is faded. Darker
			-- than PANEL_BG so the outline reads as a shadow rather than as a
			-- second colour.
			TEXT_OUTLINE = Color3.fromRGB(1, 3, 6),
			TEXT_OUTLINE_PX = 1,
			TEXT_OUTLINE_SOFT = 0.65,
			-- HUD text is drawn over the WORLD rather than over a panel, so it
			-- needs a heavier outline than panel text does. Anything the kit
			-- draws outside a window passes this instead.
			HUD_TEXT_OUTLINE_PX = 2,

			-- Panels are slightly see-through, so a window never fully hides
			-- what the player was looking at. Only slightly: text has to stay
			-- readable over whatever is behind it.
			BG_TRANSPARENCY = 0.15,

			-- Cursor blink half-period, in seconds. 0.53 is the DEC VT100's,
			-- which is where every terminal cursor since got it from.
			BLINK_PERIOD = 0.53,

			-- The hotbar's icon box and the label strip under it. In STYLE
			-- rather than METRICS because they size ART, not layout: swapping
			-- to a denser icon set moves these two and nothing else.
			ICON_SIZE = 80,
			SLOT_LABEL_HEIGHT = 26,
		},

		-- TEXT. Line box arithmetic.
		TEXT = {
			-- Extra height added to a text size to get its line box, so stacked
			-- single-line labels do not touch. A label sized by its FONT rather
			-- than by its box gets clipped descenders at some scales; this is
			-- the leading that prevents it.
			LINE_LEAD = 4,
		},

		-- BUTTON HOTKEYS. The key-cap badge a button draws when it has a
		-- keyboard or gamepad shortcut, and the two keys the kit treats as
		-- MEANINGS rather than as bindings.
		BUTTON_HOTKEY = {
			-- PRIMARY and CANCEL are the kit's two roles. A button declaring
			-- one of these keyboard keys is understood by the gamepad layer as
			-- "this is the confirm button" / "this is the back button" and is
			-- bound to the pad's own confirm/cancel instead. Any other key is
			-- carried through literally.
			PRIMARY = Enum.KeyCode.E,
			CANCEL = Enum.KeyCode.C,
			-- Priority of the InputContext a hotkey badge creates. Above
			-- gameplay bindings, so a panel's E beats the world's E while the
			-- panel is on screen; below the gamepad navigation context, which
			-- has to be able to take the same buttons back.
			PRIORITY = 1000,
			-- The key cap: its square, the gap it leaves between itself and the
			-- button's caption, and its own text size.
			SIZE = 24,
			GAP = 8,
			TEXT_SIZE = 18,
			-- The cap is a faint plate rather than a filled box, so a row of
			-- caps does not out-shout the captions beside them.
			BACKGROUND_ALPHA = 0.15,
		},

		-- HOLD BUTTONS. A button that must be held for `hold` seconds before it
		-- fires. Used for anything destructive, where a misclick is expensive.
		HOLD_BUTTON = {
			-- How fast the fill drains when the player lets go, as a MULTIPLE
			-- of the fill rate: 3 means a released hold empties in a third of
			-- the time it took to fill. Fast enough that letting go reads as a
			-- cancel, slow enough to see that it cancelled.
			DRAIN_RATE = 3,
			-- The fill is a wash over the button, not a replacement for it: the
			-- caption stays readable the whole way across.
			FILL_TRANSPARENCY = 0.35,
			-- Floor on `hold`, in seconds. A zero or negative hold divides by
			-- zero in the fill arithmetic and fires on the frame it is pressed,
			-- which is a plain button with extra steps.
			MIN_HOLD = 0.05,
		},

		-- DIALOGS. A dialog is a window with a fixed width and centred lines.
		DIALOG = {
			-- Narrow on purpose: a dialog is one question, and a wide one
			-- invites paragraphs.
			WIDTH = 380,
		},

		-- MENU BACKDROP. The blur and dim behind an open menu, driven by
		-- `src/client/ui/menu-state`.
		MENU_BACKDROP = {
			-- Blur radius at full menu. Enough that the world stops competing
			-- for attention, not so much that the player loses their place.
			BLUR = 12,
			-- Default brightness offset. NEGATIVE: the world darkens, so light
			-- panel text keeps its contrast. A menu may ask for a darker value
			-- than this, never a lighter one -- `menu-state` takes the MINIMUM
			-- across open menus, so nesting a panel inside another cannot
			-- brighten the backdrop back up.
			BRIGHTNESS = -0.12,
			-- Approach rate for both, so the backdrop arrives with the window
			-- rather than after it. Slower than METRICS.WIPE_RATE, because a
			-- full-screen blur snapping in is a flash.
			FADE_RATE = 14,
		},

		-- SCALE. The floor `util/ui/hooks/px` clamps its scale factor to, set
		-- once at boot by `src/client/ui/app`.
		SCALE = {
			-- 0.75 rather than the hook's own 0.4 default, because this kit's
			-- densest screen is a window full of body text: below about
			-- three quarters, 18px body text on a phone stops being readable.
			-- A game whose densest screen is icons can lower it.
			MINIMUM = 0.75,
		},

		-- SURFACE PANELS. `kit/surface` mounts a UI onto every part carrying a
		-- tag, as a SurfaceGui -- a screen in the world rather than on the HUD.
		SURFACE = {
			-- Canvas size in surface pixels. Fixed rather than derived from the
			-- part, so the same UI is the same size on a big part and a small
			-- one; the part's own size decides how much wall it covers.
			SIZE = Vector2.new(1024, 640),
			-- Studs. Doubles as the SurfaceGui's MaxDistance and as the range
			-- check that enables it, so the panel is never drawn just outside
			-- the distance at which it would be legible.
			DISTANCE = 60,
			-- Unlit (0) and over-bright, so a world panel reads at night and
			-- inside a dark room. A lit panel is invisible exactly where a
			-- glowing screen is most useful.
			LIGHT = 0,
			BRIGHTNESS = 1.5,
			-- Seconds between range checks. A distance test does not need a
			-- frame: at 0.25 s a player walking away sees the panel switch off
			-- a quarter second late, and nobody notices.
			POLL = 0.25,
		},

		-- ALERTS. The toast stack drawn by `src/client/ui/pages/alerts` over the
		-- message atom in `src/shared/services/alert.luau`.
		ALERTS = {
			-- DisplayOrder. Deliberately enormous: a toast is the last thing
			-- the game says before something goes wrong, and it has to survive
			-- a panel that picked an optimistic layer of its own.
			LAYER = 900000,
			TEXT_SIZE = 22,
			-- Toast column width, and the margin it keeps from the screen edge.
			-- The column is CLAMPED to the viewport minus two margins, so a
			-- phone shows a narrower column rather than a clipped one.
			WIDTH = 700,
			MARGIN = 20,
			-- Hard cap on visible toasts. Without it a burst -- a party of four
			-- all earning something at once -- stacks off the top of the screen
			-- and the newest, which is the one that matters, is the one pushed
			-- out of view.
			MAX_VISIBLE = 4,
			-- Seconds a toast lives, and how long its scale-in and fade-out
			-- take. LIFESPAN is measured from the toast appearing, so the fade
			-- starts at LIFESPAN - ANIMATION_TIME and the two end together.
			LIFESPAN = 3,
			ANIMATION_TIME = 0.2,
		},
	},

	-- CONTROLS. Key, gamepad and touch bindings, and the thresholds gesture
	-- recognition uses (how far is a swipe, how long is a hold).
	--
	-- Read by `src/client/input` and the input labels in the widget kit.
	controls = {
		-- GAMEPAD. The two buttons every pad agrees on, plus the numbers the
		-- menu navigator in `src/client/ui` runs on. Gameplay bindings belong
		-- to the game, not to the kit; only the menu layer is here.
		GAMEPAD = {
			-- A confirms and B goes back, on every pad Roblox reports, because
			-- that is the layout the console the player learned on used. The
			-- kit maps a button's keyboard hotkey onto these rather than asking
			-- each button for a pad binding of its own.
			CONFIRM = Enum.KeyCode.ButtonA,
			CANCEL = Enum.KeyCode.ButtonB,
			-- Shoulder buttons step a list or a carousel sideways, leaving the
			-- stick free to move the focus within a page.
			CAROUSEL_PREVIOUS = Enum.KeyCode.ButtonL1,
			CAROUSEL_NEXT = Enum.KeyCode.ButtonR1,
			-- The left stick moves the selection. Read as a whole Vector2
			-- action rather than as four directions, so a diagonal picks one
			-- neighbour instead of firing two steps.
			MOVE = Enum.KeyCode.Thumbstick1,

			-- Stick magnitude a menu step needs. MUCH larger than a gameplay
			-- dead zone (which is about 0.18): moving a cursor is discrete, so
			-- a stick resting a little off centre must not walk the selection,
			-- and the player has to mean it.
			MENU_DEADZONE = 0.6,
			-- Held-stick auto-repeat: the pause before the second step, then
			-- the interval between the rest. The long first delay is what lets
			-- a single flick move exactly one item.
			REPEAT_DELAY = 0.6,
			REPEAT_INTERVAL = 0.3,

			-- How much harder it is to move ACROSS the stick's direction than
			-- along it, when picking the next thing to focus. At 3, a candidate
			-- three times further sideways than a rival loses even if it is
			-- nearer in a straight line -- which is how "press right" lands on
			-- the thing to the right rather than on the nearest thing that
			-- happens to be up and to the right.
			NAV_AXIS_BIAS = 3,
			-- The navigation InputContext's priority, and it sinks. Above every
			-- gameplay context and above a panel's own hotkeys
			-- (`ui.BUTTON_HOTKEY.PRIORITY`), because while a menu is being
			-- driven by a pad, A and B belong to the menu.
			NAV_PRIORITY = 3000,
		},

		-- TOUCH. Sizes for the on-screen buttons in `src/client/input`, and the
		-- thresholds the gesture recogniser there classifies a touch by.
		--
		-- REAL VIEWPORT PIXELS, not design pixels -- these are the one group of
		-- sizes in the file that is NOT scaled through `util/ui/hooks/px` the
		-- way `ui.METRICS` is. A thumb is the same size on every phone, so a
		-- touch target that shrank with the viewport would be hardest to hit on
		-- exactly the smallest screens, and a drift threshold that shrank with
		-- it would call a deliberate drag a tap.
		TOUCH = {
			-- A touch button's square, and the gap between buttons. 54 design
			-- px is about 9 mm on a phone: the smallest square still reliably
			-- hit by a thumb that is also holding the device.
			BUTTON = 54,
			GAP = 8,
			TEXT = 14,
			-- DisplayOrder for the touch layer. Above panels (which sit near
			-- 1000) so a button is never buried, below `ui.ALERTS.LAYER`.
			LAYER = 1250,
			-- Seconds between re-measurements of the Roblox touch controls the
			-- buttons anchor themselves off. Those live in CoreGui and give no
			-- change signal, so the only way to follow them is to look; 0.05 s
			-- is fast enough that a rotation is not seen as a jump.
			POLL = 0.05,

			-- Thumbstick magnitude below which movement reads as zero. Lower
			-- than a gamepad's, because a virtual stick has no spring to return
			-- it and no physical centre to rest at.
			DEADZONE = 0.08,

			-- What separates a TAP from a drag or a hold: a touch that lifts
			-- within TAP_SECONDS, never drifted further than TAP_DRIFT pixels
			-- from where it landed, and did not turn the camera by more than
			-- TAP_CAMERA_DEGREES. The camera test is the one that matters:
			-- on a phone the whole screen is also the look control, so a short
			-- flick to look around is otherwise indistinguishable from a tap on
			-- the world.
			TAP_SECONDS = 0.3,
			TAP_DRIFT = 12,
			TAP_CAMERA_DEGREES = 2,

			-- Fraction of the viewport width at which the right side begins.
			-- Each touch is stamped with the side it STARTED on, so a gesture
			-- beginning under the movement thumbstick is never mistaken for one
			-- aimed at the world.
			RIGHT_SIDE_START = 0.5,

			-- Where each touch button sits, by the id the game registers it
			-- under, as a grid cell COUNTED BACK from the jump button: X steps
			-- left, Y steps up, in whole BUTTON + GAP squares. Measured from
			-- the jump button rather than from the screen corner because that
			-- is the one control Roblox moves for us across phone sizes,
			-- notches and orientations, so the game's buttons follow it.
			--
			-- Empty here: touch buttons are the game's actions, not the kit's.
			-- A button whose id is missing from this table falls back to cell
			-- (0, 0) and warns once, which puts it on top of jump where it
			-- cannot be missed.
			SLOTS = {},
		},
	},
}

deep(SETTINGS)

return SETTINGS
