const ReplicatedStorage = game:GetService "ReplicatedStorage"

const network_ownership = require(ReplicatedStorage.Util.instances["network-ownership"])
const observe_character = require(ReplicatedStorage.Util.observers["observe-character"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const ragdolls = require(ReplicatedStorage.Util.ragdolls)

-- The ragdoll itself is CLIENT-side (ReplicatedStorage.Client.character.setup-ragdolls
-- flips Motor6Ds off and BallSocketConstraints on when a humanoid dies). This
-- script is only the three things the client cannot do for itself -- and
-- without them death was never a ragdoll, just a body that froze upright.
--
-- Requiring the module here is the first of them: the collision groups are
-- registered in its IsServer branch, which no server script required, so it
-- never ran. Assigning an unregistered group throws, so the very first
-- set_ragdoll errored halfway through with the sockets still disabled. The
-- registration replicates, which is what lets a client assign those groups to
-- a part on its own.

-- The spin that starts the topple, applied on the server for a reason -- see
-- the ownership comment below.
const DEATH_SPIN = Vector3.new(90, 0, 0)

-- OPT-IN:
--
--   require(ServerScriptService.Server.players["setup-ragdolls"]).start()
--
-- Pair it with the client half (ReplicatedStorage.Client.character.setup-ragdolls);
-- neither works alone. See that file for why.
local started = false
function start()
	if started then
		return
	end
	started = true

	observe_players(function(player: Player)
		return observe_character(player, function(character: Model): (() -> ())?
			const humanoid = character:WaitForChild("Humanoid", 30) :: Humanoid?
			if not humanoid then
				return nil
			end

			-- 2. Death with BreakJointsOnDeath left on *destroys* every Motor6D in
			--    the rig -- and the client parents its sockets to those joints, its
			--    root weld to the PrimaryPart -- so the engine wiped the whole
			--    ragdoll and replicated the loose limbs before any client saw the
			--    Dead state. This has to be off server-side: a client-only write
			--    would not stop the server breaking them.
			humanoid.BreakJointsOnDeath = false
			-- A ragdoll's neck is a disabled Motor6D, and a Humanoid that requires
			-- its neck treats that as a broken rig. Only bites on a ragdoll the
			-- player is meant to get back up from (Physics state), but it costs
			-- nothing to be right about it here.
			humanoid.RequiresNeck = false

			-- Living characters get their own collision group so the ragdoll group
			-- can be made non-collidable with it. Every part, because the group is
			-- per-part -- and on DescendantAdded too, because the appearance load
			-- replaces the Head a few hundred ms after the character arrives (the
			-- same swap flashlight.server works around), and a part that lands
			-- after this pass would otherwise stay in Default and keep colliding
			-- with corpses.
			const function claim(instance: Instance)
				if instance:IsA "BasePart" then
					instance.CollisionGroup = ragdolls.CHARACTER_GROUP
				end
			end
			for i, descendant in character:GetDescendants() do
				claim(descendant)
			end
			const added = character.DescendantAdded:Connect(claim)

			-- 3. THE one that made death read as a freeze. A living player's
			--    character is network-owned by that player's client, so its
			--    client-side ragdoll simulates and replicates like any other thing
			--    that client owns. The engine REVOKES that ownership the instant
			--    the humanoid dies -- measured in a running server, GetNetworkOwner
			--    goes Player -> nil on the same frame as the Dead state -- and a
			--    client does not simulate what it does not own. Verified directly:
			--    a rig with ownership forced to the server, ragdolled locally by a
			--    client, sat at exactly 0 velocity for two full seconds with all 15
			--    sockets enabled. Hand the corpse back and the same local ragdoll
			--    collapses and replicates to everyone.
			const died = humanoid.Died:Once(function()
				const root = humanoid.RootPart
				if not root or not player.Parent then
					return
				end
				-- Before the handoff, while the server still owns the body: the
				-- new owner is sent the assembly's velocity along with its pose, so
				-- the spin carries over. Applied on the client instead it would
				-- land in the gap before the grant arrives, on parts that client
				-- cannot write to yet, and be silently dropped.
				root:ApplyAngularImpulse(DEATH_SPIN)
				-- Ownership of the root part carries the whole assembly.
				network_ownership.set(root, player)
			end)

			return function()
				added:Disconnect()
				died:Disconnect()
			end
		end)
	end)
end

return table.freeze {
	start = start,
}
