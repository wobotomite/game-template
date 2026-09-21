const ReplicatedStorage = game:GetService "ReplicatedStorage"

const make_display_part = require(ReplicatedStorage.Util.instances["make-display-part"])

-- AN INERT COPY OF SOMETHING THAT IS STILL IN THE WORLD, for the effects that
-- need to move a thing without moving the thing: an item flying towards the
-- inventory it was just picked up into, a copy left behind where something was
-- standing, a preview sliding into place. The real object keeps being real --
-- collided with, queried, networked -- and the ghost is what gets thrown
-- around.
--
-- THE HARD PART IS NOT THE CLONE, IT IS WHAT COMES WITH IT. A `:Clone()` of
-- anything built by a real system brings its scripts, its welds, its
-- constraints, its Humanoid, its sounds, its tags and its particles -- and all
-- of them start running the moment it is parented to the workspace. A ghost
-- that carries a tag gets picked up by whatever watches that tag; one that
-- carries a Humanoid starts walking; one that carries a Sound plays it. So
-- everything below the clone is stripped, disabled or destroyed, and what is
-- left is geometry.
--
-- THE GHOST IS YOURS TO DESTROY. It is parented to the workspace and nothing
-- here is watching it. An effect that makes one destroys it in its teardown.

export type Ghost = {
	-- Already parented to the workspace, anchored, inert.
	model: Model,
	-- Every BasePart in it, flattened, so an effect can tween transparency
	-- across the whole ghost without walking the descendants again.
	parts: { BasePart },
	-- The source's scale, captured at copy time. A ghost that is going to be
	-- scaled needs to know what 1x was; reading it back off the model later
	-- gives whatever the tween last set.
	scale: number,
}

-- `piece` is the part the caller has a handle on.
--
-- `wrapper_of` is the OPTIONAL question "is this part actually one piece of a
-- larger assembly, and if so what is the whole thing?" -- a tool model, a
-- character, a prop built from a dozen parts. A game that has a concept of
-- assemblies passes its own lookup here; one that does not passes nothing and
-- gets a ghost of exactly the part it named.
--
-- IT IS A PARAMETER RATHER THAN A REQUIRE on purpose. Copying a thing is
-- generic; knowing what counts as a whole thing is the game's business, and
-- reaching into a game's prefab registry from a shared effects helper is how a
-- generic module quietly becomes un-reusable.
function new(piece: BasePart, wrapper_of: ((BasePart) -> Instance?)?): Ghost
	const source: Instance = (if wrapper_of then wrapper_of(piece) else nil) or piece

	-- ARCHIVABLE IS A REAL NO. It is off on things the engine or a system has
	-- marked as not-to-be-copied, and `:Clone()` on one returns nil rather than
	-- raising -- so the nil branch below is the normal path for those, not an
	-- error case.
	const cloned = if source.Archivable then source:Clone() else nil

	local model: Model
	if cloned and cloned:IsA "Model" then
		model = cloned
	else
		-- Either the clone failed, or the source was a lone part. Either way the
		-- result is still a Model, so every caller gets one shape back and no
		-- effect has to branch on what it was handed.
		model = Instance.new "Model"
		const part = if cloned and cloned:IsA "BasePart"
			then cloned
			-- LAST RESORT: a hand-built stand-in that copies what can be read off
			-- the part directly. A blocky approximation of a mesh, and much
			-- better than an effect that silently does not happen.
			else make_display_part {
				Size = piece.Size,
				CFrame = piece.CFrame,
				Color = piece.Color,
				Material = piece.Material,
				Transparency = piece.Transparency,
			}
		part.Parent = model
	end

	model.Name = "VisualGhost"
	-- NO PRIMARY PART, and a pivot set by hand. A cloned model's PrimaryPart
	-- points at a part inside the clone, and `PivotTo` on a model with one moves
	-- relative to THAT part rather than to where the thing visibly is. Clearing
	-- it and setting the pivot to the source's own CFrame means the ghost pivots
	-- around the piece the caller pointed at, which is the point it is animating
	-- from.
	model.PrimaryPart = nil
	model.WorldPivot = piece.CFrame

	const parts: { BasePart } = {}
	-- READ ONCE, BEFORE THE LOOP DESTROYS THINGS. Walking a live descendant list
	-- while removing entries from it skips siblings of whatever was just
	-- destroyed -- which here means a script or a Humanoid surviving into the
	-- world at random.
	const descendants = model:GetDescendants()

	for _, tag in model:GetTags() do
		model:RemoveTag(tag)
	end

	for _, child in descendants do
		-- Tags first, and on everything. A tag is a subscription: whatever
		-- CollectionService listener owns that tag will pick the ghost up as a
		-- real one the frame it is parented in.
		for _, tag in child:GetTags() do
			child:RemoveTag(tag)
		end

		if child:IsA "BasePart" then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
			child.CanQuery = false
			child.CastShadow = false
			-- The engine sets this on the local player's own character parts to
			-- hide them in first person. A ghost cloned from one inherits the
			-- value and is invisible to the only person it was made for.
			child.LocalTransparencyModifier = 0
			table.insert(parts, child)
		elseif
			child:IsA "LuaSourceContainer"
			or child:IsA "JointInstance"
			or child:IsA "Constraint"
			or child:IsA "AnimationController"
			or child:IsA "Humanoid"
			or child:IsA "Sound"
		then
			-- Destroyed rather than disabled: every one of these does something
			-- the moment it is in the workspace. Joints and constraints in
			-- particular fight the anchoring above and drag the ghost apart.
			child:Destroy()
		elseif child:IsA "ParticleEmitter" or child:IsA "Trail" or child:IsA "Beam" then
			-- DISABLED, NOT DESTROYED. These are part of how the thing looks, and
			-- an effect that wants a ghost with its trail still on can switch one
			-- back on. Off by default because a copy that keeps emitting reads as
			-- a second real object.
			child.Enabled = false
		end
	end

	model.Parent = workspace
	return { model = model, parts = parts, scale = model:GetScale() }
end

return table.freeze { new = new }
