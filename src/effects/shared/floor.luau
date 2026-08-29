const ReplicatedStorage = game:GetService "ReplicatedStorage"

const character_exclusion = require(ReplicatedStorage.Shared.world["character-exclusion"])

-- Finds the walkable floor under a point, for anything that draws on the
-- ground. Shared rather than per-effect because the RaycastParams are: building
-- one per effect means one per effect to get wrong, and character-exclusion
-- keeps exactly one of them in step with who is alive.

const fx_ray_params = RaycastParams.new()
character_exclusion.track(fx_ray_params)
-- "Floor" means the WALKABLE floor. Skipping CanCollide-false geometry is what
-- keeps the probe off effect parts, character bodies and decor you can walk
-- through -- a decal placed on the first thing a ray hit lands on somebody's
-- head rather than on the ground.
fx_ray_params.RespectCanCollide = true

function below(position: Vector3): Vector3
	const hit = workspace:Raycast(position + Vector3.yAxis * 2, Vector3.new(0, -60, 0), fx_ray_params)
	return if hit then hit.Position + Vector3.yAxis * 0.15 else position - Vector3.yAxis * 2
end

-- NOTE ON WHAT USED TO BE HERE. This module also carried a `decal()` builder --
-- a flat, anchored, inert Neon slab -- because ground telegraphs were its first
-- caller. That was a general-purpose part builder sitting in the effects
-- folder, which is not where anybody would look for one, and it duplicated
-- util/instances/make-display-part with a few more properties. It is now that
-- module, which takes named props and can express all of it.
--
-- This module keeps the one job its name claims: where is the floor.

return table.freeze {
	below = below,
	params = fx_ray_params,
}
