const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_character = require(ReplicatedStorage.Util.observers["observe-character"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

-- ONE list of every player character, for every RaycastParams in the game that
-- has to treat characters as "not terrain".
--
-- Why this is one module rather than a line in each caller. In the game this
-- came from, three systems wanted exactly this and each grew its own copy:
--
--   * AI steering probes -- a whisker skimming a player deflects the slide
--     differently every tick, which replicates as jitter;
--   * a line-of-sight ray -- a teammate crossing your aim is not a wall, and
--     with only the caster excluded their body silently broke the lock;
--   * a ground probe for aimed effects -- telegraphs are aimed AT players, so
--     the probe under one started inside somebody's head and parked the decal
--     on top of them.
--
-- The three copies were identical down to the comment, and each ran its OWN
-- observe_players/observe_character tree -- three lifecycle subscriptions and
-- three tables rebuilding the same content on every spawn and every death.
--
-- The list is maintained on CHARACTER LIFECYCLE rather than rebuilt per ray, on
-- purpose. Per-entity probes cast many times a tick, and ASSIGNING
-- FilterDescendantsInstances makes the engine rebuild the whole exclusion set
-- whether or not anything in it changed. The set only actually changes when
-- somebody spawns or dies, so that is when it is rebuilt.

const characters: { Instance } = {}
const tracked: { RaycastParams } = {}

local observing = false

function refresh()
	table.clear(characters)
	for _, player in Players:GetPlayers() do
		const character = player.Character
		if character then
			table.insert(characters, character)
		end
	end
	for _, params in tracked do
		params.FilterDescendantsInstances = characters
	end
end

-- Keep `params` excluding every player character for as long as the place
-- runs. Sets FilterType for the caller -- an Exclude list on an Include filter
-- is the one way to get this exactly backwards, and it would read as ghosts
-- colliding with nothing but people.
--
-- Returns nothing, deliberately. `const p = track(RaycastParams.new())` reads
-- better, but a spec that stubs this module out then has to hand the params
-- BACK, so every such stub has to know what this returns. Taking the params and
-- staying quiet costs one line at each call site and keeps the stub a no-op.
function track(params: RaycastParams)
	params.FilterType = Enum.RaycastFilterType.Exclude
	table.insert(tracked, params)

	-- Nothing observes until something is actually tracked: this module is
	-- replicated to both places and the lobby raycasts none of this.
	if not observing then
		observing = true
		observe_players(function(player)
			return observe_character(player, function()
				refresh()
				return refresh -- and again when that character goes away
			end)
		end)
	end

	-- observe_* run synchronously for whoever is already here, so the loop
	-- above has usually filled the list by now -- but not for a player who has
	-- joined without spawning, and not for the second caller onwards.
	params.FilterDescendantsInstances = characters
end

return table.freeze {
	track = track,
}
