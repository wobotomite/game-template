const ReplicatedStorage = game:GetService "ReplicatedStorage"

const lyra = require(ReplicatedStorage.Packages.lyra)

-- Migration steps, applied IN ORDER to a profile older than the schema.
--
-- WHY THIS EXISTS AT ALL. `datastore-template.luau` fills a profile being
-- created for the FIRST time and nothing else. A field added to
-- `datastore-schema.luau` after a game is live is therefore missing on every
-- save that already exists, the schema check rejects the load, and
-- `src/server/data/lifecycle.luau` turns that into a kick. So: schema field,
-- template default, migration step. All three, or none of it works.
--
-- THE ID IS PERMANENT. lyra records which step ids a profile has already seen,
-- so renaming one re-runs it and deleting one leaves profiles claiming a step
-- that no longer exists. Append; never edit or reorder what has shipped. Dating
-- an id is the cheap way to keep that honest.
--
-- `addFields` only writes keys that are ABSENT, so it is safe on a profile that
-- already has them; `transform` takes the whole table and is the escape hatch
-- for a rename or a reshape.
--
-- A GAME THAT HAS NOT SHIPPED YET needs none of this: change the schema and the
-- template, and every profile is new. These three exist because the fields they
-- add arrived after the template's first profile shape, and they cost nothing
-- to keep.
return table.freeze {
	lyra.MigrationStep.addFields("2026-09-21-add-receipt-ledger", {
		commerce = { granted = {} },
	}),

	lyra.MigrationStep.addFields("2026-09-21-add-progress", {
		progress = { best_score = 0 },
	}),

	lyra.MigrationStep.addFields("2026-09-21-add-daily-rewards", {
		daily = { streak = 0, last_day = 0, best_streak = 0 },
	}),
}
