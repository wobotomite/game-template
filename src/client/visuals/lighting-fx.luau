const CollectionService = game:GetService "CollectionService"
const Lighting = game:GetService "Lighting"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const tags = require(ReplicatedStorage.Shared.records.tags)

-- The ONE way a script puts a post-processing effect into Lighting.
--
-- Lighting's children are reconciled against the current room mood by
-- util/extra-features/change-lighting: it counts what is in there, morphs what
-- it can reuse, and FADES OUT AND DESTROYS the rest. A ColorCorrectionEffect a
-- script parented in by hand is, from the reconciler's side, an extra child of
-- a class the next mood does not want -- so the VHS grade, the goo tint or the
-- damage blip would be tweened to neutral and destroyed the first time the
-- party walked through a door, and the script that made it would go on holding
-- a destroyed instance and writing properties nobody renders.
--
-- LIGHTING_ENGINE_IGNORE takes an instance out of BOTH sides of that
-- comparison. Every effect in this game is script-owned and every one of them
-- carries it, which is why this exists as a function rather than as a line in
-- eight files: the tag is not optional, and a parent-then-tag ordering leaves a
-- window (the reconciler yields between children, so it can genuinely run
-- between the two statements) where the effect is visible to a reconcile that
-- is already in flight. Tag first, parent second, never by hand.
function own<T>(effect: T & Instance): T & Instance
	CollectionService:AddTag(effect, tags.LIGHTING_ENGINE_IGNORE)
	effect.Parent = Lighting
	return effect
end

return table.freeze {
	own = own,
}
