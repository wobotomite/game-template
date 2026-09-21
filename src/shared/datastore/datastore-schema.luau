local ReplicatedStorage = game:GetService "ReplicatedStorage"

local greentea = require(ReplicatedStorage.Packages.greentea)

-- The shape of one player's saved profile, as a runtime-checked type.
--
-- Every field here needs a matching default in
-- `src/shared/datastore/datastore-template.luau` and, once the game is live, a
-- migration step in `src/server/data/datastore/migrations.luau`: the template
-- only fills a profile being created for the FIRST time, so a field added later
-- is simply absent on every existing save until a migration adds it, and this
-- schema then rejects the load.
return greentea.build(greentea.struct {
	currency = greentea.struct {
		coins = greentea.number(),
	},

	-- COMMERCE. `granted` is the purchase-id ledger the receipt service writes
	-- so a receipt Roblox re-delivers is granted once; see
	-- `settings.commerce.RECEIPT_LEDGER_MAX`. Purchase ids are held as STRINGS
	-- because a Roblox PurchaseId is larger than a double represents exactly,
	-- and two ids that round to the same number is how a ledger quietly stops
	-- catching duplicates.
	commerce = greentea.struct {
		granted = greentea.array(greentea.string()),
	},

	-- PROGRESS. Counters that only ever go up, and where global leaderboards
	-- read from: `settings.leaderboards.ORDER` names keys IN HERE.
	--
	-- `best_score` is an EXAMPLE, wired up out of the box so the board works
	-- before a game has invented its own metric. Rename it in three places
	-- together -- here, the template, and `settings.leaderboards` -- or the
	-- board reads nil and publishes nothing.
	progress = greentea.struct {
		best_score = greentea.number(),
	},

	-- DAILY REWARDS. `last_day` is a day NUMBER (unix time floored by
	-- `settings.daily.DAY_SECONDS`), not a timestamp, so the claim rules compare
	-- integers rather than clocks.
	daily = greentea.struct {
		streak = greentea.number(),
		last_day = greentea.number(),
		best_streak = greentea.number(),
	},
})
