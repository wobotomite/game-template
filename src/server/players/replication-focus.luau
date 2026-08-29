const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

-- Who each player's world is streamed around.
--
--   focus.watch(spectator, target)   -- stream the target's surroundings
--   focus.watch(spectator, nil)      -- back to their own body
--   focus.refocus(target)            -- the target respawned; re-point watchers
--
-- WHY THIS EXISTS AS A MODULE rather than a property write at each call site.
-- `Player.ReplicationFocus` is server-only and it has two traps, and both of
-- them produce a player standing in a world that is not there.
--
-- **`nil` DOES NOT MEAN "STREAM NOTHING".** It hands the choice back to Roblox,
-- which falls back to the player's own character — which is what you want, and
-- is exactly why clearing the field by hand *seems* fine. The problem is the
-- path you forget: one route out of spectating that does not clear it leaves
-- the focus parked on a teammate, and the player revives into a room that
-- streams in late around their own feet. Routing every path through one
-- function is what makes "did we clear it?" answerable.
--
-- **A FOCUS THAT MISSES ITS PART NEVER RETRIES.** Set it while the target is
-- between characters — the window between "alive" flipping true and
-- `LoadCharacter` returning is real and easy to land in — and there is no root
-- part to point at yet. Nothing re-attempts on its own, so the watcher rides a
-- camera through a world that never streams in. `refocus` is the fix, called
-- when a target's character arrives.
--
-- ONE MORE, WORTH KNOWING BEFORE IT COSTS AN AFTERNOON: a focus left pointing
-- at a part you are about to destroy is a state worth forbidding outright. Tear
-- down watchers BEFORE tearing down what they watch.

const watching: { [Player]: Player } = {}

local function root_of(player: Player): BasePart?
	const character = player.Character
	return character and character:FindFirstChild "HumanoidRootPart" :: BasePart?
end

-- Point `player`'s streaming at `target`, or back at themselves with nil.
function watch(player: Player, target: Player?)
	if target and target ~= player then
		watching[player] = target
		player.ReplicationFocus = root_of(target)
	else
		watching[player] = nil
		player.ReplicationFocus = nil
	end
end

function watching_who(player: Player): Player?
	return watching[player]
end

-- Re-point everyone watching `target` at its CURRENT root part. Call this when
-- a target's character spawns: a focus set during the gap between characters
-- landed on nil and will not fix itself.
function refocus(target: Player)
	const root = root_of(target)
	for watcher, watched in watching do
		if watched == target and watcher.Parent then
			watcher.ReplicationFocus = root
		end
	end
end

-- Stop everyone watching `target`. Call it before destroying that character, so
-- no focus is left pointing at a part that is going away.
function drop_watchers_of(target: Player)
	for watcher, watched in watching do
		if watched == target then
			watch(watcher, nil)
		end
	end
end

function clear_all()
	for watcher in watching do
		watch(watcher, nil)
	end
end

observe_players(function(player: Player): () -> ()
	return function()
		watching[player] = nil
		-- Anyone watching the player who just left has to be released too, or
		-- their focus stays on a character that is being torn down.
		drop_watchers_of(player)
	end
end)

return table.freeze {
	watch = watch,
	watching_who = watching_who,
	refocus = refocus,
	drop_watchers_of = drop_watchers_of,
	clear_all = clear_all,
}
