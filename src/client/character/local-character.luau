const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const observe_rig = require(ReplicatedStorage.Util.observers["observe-rig"])

-- The local character's parts, or nil while they are dead, still loading, or
-- the module was required before LocalPlayer existed. Three run scripts in the
-- game this came from had their own copy of this four-liner under two
-- different names (`character_root`, `local_root`).
--
-- BUILT ON `observe-rig` RATHER THAN A `FindFirstChild` PER CALL. The
-- hand-rolled version is two lines and wrong twice over:
--
--   a tree search per call        and the callers are per-frame code, so that
--                                 is one search every frame, per caller
--   it trusts the first model     CharacterAdded can fire with an EMPTY model:
--                                 resolved at that instant there is no root
--                                 and no head. `observe-rig` resolves again on
--                                 every child added, so the answer corrects
--                                 itself instead of being cached wrong.
--
-- LocalPlayer is read on each call until it exists rather than captured at
-- require time: a module pulled in early enough would otherwise cache nil
-- forever. Callers are per-frame code that simply skips a frame when there is
-- no character, so this returns nil rather than erroring.
--
-- The resolver is never destroyed. It is one subscription for the local player,
-- who is present for the whole session -- there is no moment at which tearing
-- it down would be correct.
const EMPTY: observe_rig.Rig = table.freeze {}

local resolver: observe_rig.Resolver? = nil

const function rig(): observe_rig.Rig
	local found = resolver
	if found == nil then
		const player = Players.LocalPlayer
		if player == nil then
			return EMPTY
		end
		found = observe_rig(player)
		resolver = found
	end
	return (found :: observe_rig.Resolver).get()
end

return table.freeze {
	root = function(): BasePart?
		return rig().root
	end,

	head = function(): BasePart?
		return rig().head
	end,
}
