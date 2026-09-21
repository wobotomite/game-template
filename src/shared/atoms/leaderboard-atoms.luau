const ReplicatedStorage = game:GetService "ReplicatedStorage"

const charm = require(ReplicatedStorage.Packages.charm)
const sync_registry = require(ReplicatedStorage.Shared.services["sync-registry"])

-- The published global leaderboards: what the server last read out of the
-- OrderedDataStores, replicated to every client.
--
-- WHY AN ATOM AND NOT A REMOTE FUNCTION. A board is the same for everybody and
-- changes every couple of minutes. Replicating it as state means a client that
-- joins mid-refresh, or opens the board UI before the first read has finished,
-- reads whatever is there now instead of asking and waiting -- and a UI built on
-- it re-renders when the next refresh lands without knowing that refreshes
-- exist.
--
-- WHY THE STATUS IS PART OF THE DATA. "No rows" has four different causes and a
-- display should say a different thing for each: the first read has not come
-- back yet, the board is genuinely empty, the DataStore could not be reached at
-- all, or the last read failed and these rows are the previous ones. Collapsing
-- them into an empty list is how a UI ends up saying "be the first!" to a
-- player during an outage.

export type Entry = {
	user_id: number,
	-- Resolved from the id by `src/server/leaderboards/name-cache.luau` and sent
	-- with the row, rather than looked up per row on the client: the names are
	-- the same for all of them, and a client-side lookup is one web call per
	-- visible row per client.
	username: string,
	display_name: string,
	value: number,
}

export type Board = {
	entries: { Entry },
	-- `os.time()` of the read these rows came from, so a display can say how old
	-- they are (and 0 means "never successfully read").
	updated_at: number,
	status: "loading" | "ready" | "unavailable" | "stale",
}

-- Keyed by the board key -- the same key as `settings.leaderboards.ORDER` --
-- because charm-sync replicates dictionaries keyed by STRINGS; an array of
-- boards would re-send the whole list whenever one of them changed.
const boards = charm.atom({} :: { [string]: Board })

-- The leading dot keeps the sync keys of shared state together and apart from
-- the per-player keys, which are suffixed with a user id.
sync_registry.register(".GLOBAL_LEADERBOARDS", boards)

return table.freeze {
	boards = boards,
}
