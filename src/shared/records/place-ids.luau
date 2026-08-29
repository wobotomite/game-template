const ReplicatedStorage = game:GetService "ReplicatedStorage"

const const_record = require(ReplicatedStorage.Util.tables["const-record"])

-- The published place id of every place in this universe, keyed by the ROLE
-- that place plays. `shared/place-context` matches `game.PlaceId` against these
-- to decide what a given server or client is at runtime.
--
-- ONE BUILD SERVES EVERY PLACE. Rojo publishes the same tree everywhere, so a
-- script cannot know which place it is in from its own contents — the place id
-- is the only runtime truth. That is what this record is for.
--
-- A single-place game leaves this exactly as it is: nothing matches, everything
-- resolves to `main`, and nothing about places ever comes up.
--
-- A multi-place game adds a role per place and fills in each id AFTER
-- publishing that place. An unfilled id is 0, which never matches a real
-- PlaceId, so a half-configured universe degrades to "everything is `main`"
-- rather than to a wrong answer. See docs/multi-place.md.
return const_record {
	-- The fallback. Any place id not listed here resolves to this role, so a
	-- role named `main` should be the experience players start in.
	main = 0,
}
