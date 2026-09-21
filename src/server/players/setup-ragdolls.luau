const ReplicatedStorage = game:GetService "ReplicatedStorage"

const network_ownership = require(ReplicatedStorage.Util.instances["network-ownership"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])
const observe_rig = require(ReplicatedStorage.Util.observers["observe-rig"])
const ragdolls = require(ReplicatedStorage.Util.ragdolls)
const settings = require(ReplicatedStorage.Shared.settings)

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
-- the ownership comment below. In settings rather than here because the client
-- half tunes the fall against it and the two have to agree.
const DEATH_SPIN = settings.character.DEATH_SPIN

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

	observe_players(function(player: Player): () -> ()
		-- A RIG resolver rather than `observe_character`. A character can be
		-- parented before its Humanoid exists, and the old shape's answer to that
		-- was `WaitForChild("Humanoid", 30)` INSIDE the observer callback: it
		-- yields the observer's own thread, and for up to thirty seconds it holds
		-- a character the player may already have left. The resolver publishes
		-- again as each part appears, so the wait becomes a second call with a
		-- fuller rig instead of a blocked thread.
		const rig = observe_rig(player)

		-- The character this player is currently bound for, and the two
		-- connections that binding made.
		local ready: Model? = nil
		local added: RBXScriptConnection? = nil
		local died: RBXScriptConnection? = nil

		const function forget()
			if added then
				added:Disconnect()
				added = nil
			end
			if died then
				died:Disconnect()
				died = nil
			end
			ready = nil
		end

		const function bind(parts: observe_rig.Rig)
			-- THE RE-ENTRANCY GUARD, and the reason the resolver needs one. A rig
			-- republishes whenever any of its four parts changes -- the appearance
			-- load swapping the Head is enough -- and without this, the SAME
			-- character got a second DescendantAdded connection and a second
			-- Died:Once on every republish. Two Died handlers means the death
			-- impulse is applied twice and ownership is handed over twice, which
			-- reads as a corpse that flies.
			if parts.character == ready then
				return
			end
			-- A different character (or none): whatever the last one bound is now
			-- stale, and an undisconnected DescendantAdded on a dead rig keeps
			-- that whole character reachable.
			forget()

			const character = parts.character
			const humanoid = parts.humanoid
			if character == nil or humanoid == nil then
				return
			end
			ready = character

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
			for _, descendant in character:GetDescendants() do
				claim(descendant)
			end
			added = character.DescendantAdded:Connect(claim)

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
			died = humanoid.Died:Once(function()
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
		end

		const unsubscribe = rig.changed(bind)
		-- And once for whatever is already there: `changed` only fires on the
		-- NEXT publish, and a player who already has a character when this
		-- starts would otherwise never be bound at all.
		bind(rig.get())

		return function()
			unsubscribe()
			rig.destroy()
			forget()
		end
	end)
end

return table.freeze {
	start = start,
}
