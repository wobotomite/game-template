--!nocheck
-- server/players/replication-focus: the bookkeeping, which is the whole module.
-- Run with:
--   lune run tests/replication-focus.spec.luau
--
-- WHY THIS ONE. Both failure modes end with a player standing in a world that
-- was never streamed to them, and neither raises anything -- the symptom is
-- "the room loaded in late around my feet", reported by a player, once,
-- unreproducibly.
--
-- The module exists because `Player.ReplicationFocus = nil` does NOT mean
-- "stream nothing": it hands the choice back to Roblox, which falls back to
-- the player's own character. That is what you want, which is exactly why
-- clearing the field by hand looks fine and why the path somebody forgets is
-- the one that leaves a focus parked on a teammate.
--
-- So every case below is about a path OUT of watching.

local h = require "./harness"
local env = require "./roblox-env"
local roblox = require "@lune/roblox"

h.title "replication focus:"

local focus = env.load("ServerScriptService.Server.players.replication-focus", { realm = "server" })

-- A player stand-in. The module reads `Character`, writes `ReplicatedFocus`,
-- and checks `Parent` for "has left".
local function fake_player(name: string, with_character: boolean?)
	local player = { Name = name, Parent = true, ReplicationFocus = nil, Character = nil }
	if with_character ~= false then
		local character = roblox.Instance.new "Model"
		local root = roblox.Instance.new "Part"
		root.Name = "HumanoidRootPart"
		root.Parent = character
		player.Character = character
	end
	return player
end

do
	local watcher, target = fake_player "watcher", fake_player "target"
	focus.watch(watcher, target)
	h.check("watching points the focus at the target's root", watcher.ReplicationFocus ~= nil)
	h.equals("and records who", focus.watching_who(watcher), target)

	focus.watch(watcher, nil)
	-- nil, not "some other part": handing the choice back to Roblox is what
	-- returns the player to their own body.
	h.equals("clearing hands the focus back to Roblox", watcher.ReplicationFocus, nil)
	h.equals("and forgets who", focus.watching_who(watcher), nil)
end

do
	-- Watching yourself is the same as watching nobody. Without this it is a
	-- focus pinned to your own root part, which looks identical until the
	-- character is replaced and the focus points at a destroyed instance.
	local player = fake_player "self"
	focus.watch(player, player)
	h.equals("watching yourself clears instead", player.ReplicationFocus, nil)
	h.equals("and records nothing", focus.watching_who(player), nil)
end

do
	-- THE RACE. A spectate claim can land between "target is alive" and
	-- `LoadCharacter` returning, so there is no root part to point at yet --
	-- and a focus that missed NEVER retries on its own. The watcher rides a
	-- camera through a world that never streams in.
	local watcher = fake_player "watcher"
	local target = fake_player("target", false) -- mid-respawn: no character
	focus.watch(watcher, target)
	h.equals("a target with no character yields no focus", watcher.ReplicationFocus, nil)
	h.equals("but the watch is still recorded", focus.watching_who(watcher), target)

	-- ...and this is what fixes it, called when the character arrives.
	local character = roblox.Instance.new "Model"
	local root = roblox.Instance.new "Part"
	root.Name = "HumanoidRootPart"
	root.Parent = character
	target.Character = character

	focus.refocus(target)
	h.check("refocus re-points watchers once the character exists", watcher.ReplicationFocus ~= nil)
end

do
	-- A focus left pointing at a part that is about to be destroyed is the one
	-- state worth forbidding outright, so watchers come off BEFORE the thing
	-- they watch does.
	local a, b, target = fake_player "a", fake_player "b", fake_player "target"
	focus.watch(a, target)
	focus.watch(b, target)

	focus.drop_watchers_of(target)
	h.equals("dropping releases every watcher of that target", a.ReplicationFocus, nil)
	h.equals("both of them", b.ReplicationFocus, nil)
	h.equals("and forgets them", focus.watching_who(a), nil)
end

do
	-- Re-targeting must not leave the old record behind, or `drop_watchers_of`
	-- on the FIRST target would release a watcher who has since moved on.
	local watcher, first, second = fake_player "w", fake_player "first", fake_player "second"
	focus.watch(watcher, first)
	focus.watch(watcher, second)
	h.equals("re-targeting replaces the record", focus.watching_who(watcher), second)

	focus.drop_watchers_of(first)
	h.equals("dropping the old target does not touch the watcher", focus.watching_who(watcher), second)
end

do
	local a, b = fake_player "a", fake_player "b"
	focus.watch(a, b)
	focus.clear_all()
	h.equals("clear_all releases everyone", focus.watching_who(a), nil)
	h.equals("and clears the field", a.ReplicationFocus, nil)
end

h.done()
