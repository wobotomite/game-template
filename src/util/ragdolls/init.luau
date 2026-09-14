const PhysicsService = game:GetService "PhysicsService"
const RunService = game:GetService "RunService"

const util = require(script.util)

-- Everything ragdolled -- the invisible collider parts AND the rig's own limbs
-- while they are limp. Declared next to create_collider_part, which stamps it.
const RAGDOLL_GROUP = util.ragdoll_group
-- Every part of a character that is still being played. The server puts
-- characters in here (setup-ragdolls.server) purely so that the row below can
-- exist: "not collidable with the world" is not expressible, because the world
-- is Default and so is everything else.
const CHARACTER_GROUP = "Characters"

-- Collision groups still live on PhysicsService; the workspace:* equivalents
-- are not available yet.
--
-- Server-only, but the matrix REPLICATES -- which is the whole reason a client
-- may assign these groups to a part on its own.
if RunService:IsServer() then
	-- Registering a group that already exists throws, and these are ordinary
	-- names somebody may well have added by hand in Studio.
	for i, group in { RAGDOLL_GROUP, CHARACTER_GROUP } do
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
	end
	-- Corpses do not pile on each other...
	PhysicsService:CollisionGroupSetCollidable(RAGDOLL_GROUP, RAGDOLL_GROUP, false)
	-- ...and the living walk straight through them. A corpse is scenery: it
	-- lies where players are trying to run, it cannot be pushed out of the way
	-- by anything except more players, and a body wedged in a doorway during a
	-- chase is the whole reason this row is here.
	PhysicsService:CollisionGroupSetCollidable(RAGDOLL_GROUP, CHARACTER_GROUP, false)
end

type RagdollObject = {
	rig: Model,
	colliders: { BasePart },
	-- OPTIONAL, because `util.ragdoll_weld_root` can legitimately fail to make
	-- one -- no PrimaryPart yet, or no root joint it recognises (see the note
	-- in util on AnimationConstraint rigs). This used to be a non-optional
	-- `Weld` that the util module guaranteed by THROWING, so a rig that could
	-- not be welded took the whole `init_ragdoll` down with it instead of being
	-- set up without a root weld and repaired on the next `sync_ragdoll`.
	root_weld: Weld?,
	character_joints: { Motor6D },
	ragdoll_joints: { util.SocketMapValue },
	-- What each of the rig's own parts was in before it went limp, so releasing
	-- a ragdoll puts them back rather than assuming everything came from the
	-- character group (this module also ragdolls things that are not players).
	part_groups: { [BasePart]: string },
	is_ragdolled: boolean,
}

-- STRONG keys, cleaned up on Destroying. This was a weak-KEY table, on the
-- assumption that a live, parented rig keeps its own entry alive -- and in
-- Roblox that assumption is false. An Instance's Lua-side wrapper is
-- collectable whenever nothing on the Lua side holds it strongly, whatever the
-- DataModel thinks, so a weak entry keyed by a perfectly healthy character is
-- dropped on the first GC cycle. Measured in Studio: 40 parts created and left
-- parented, referenced ONLY from a weak table -- 0 of the 40 entries survived,
-- and the state was unrecoverable even by looking the same instance up again.
--
-- What that cost: init_ragdoll runs once at spawn and this table is the only
-- place the rig's sockets, welds and saved collision groups live. A few seconds
-- later the entry was gone, so the death that followed found is_ragdolled()
-- answering false and set_ragdoll() bailing with "ragdoll not init" -- i.e. the
-- body froze upright, which is the exact symptom the two setup-ragdolls scripts
-- already chased three other causes of. It only bit once a GC cycle had passed,
-- so dying seconds after spawning worked and dying a room later did not.
--
-- Destroying is the right release: a character model is destroyed on respawn
-- and on leave, which is precisely when its ragdoll state stops being useful.
const storage: { [Model]: RagdollObject } = {}

function init_ragdoll(rig: Model)
	if storage[rig] then
		warn "already init"
		return
	end

	storage[rig] = {
		rig = rig,
		colliders = {},
		root_weld = util.ragdoll_weld_root(rig),
		character_joints = {},
		ragdoll_joints = {},
		part_groups = {},
		is_ragdolled = false,
	}
	rig.Destroying:Once(function()
		storage[rig] = nil
	end)
	sync_ragdoll(rig)
end

-- Bring a built ragdoll back in line with the rig as it exists RIGHT NOW:
-- drop entries whose joint was destroyed under us, and socket up any joint
-- that has appeared since.
--
-- A character's rig is not fixed at spawn. The appearance load replaces the
-- Head a few hundred ms in (a mesh/dynamic head), destroying the old Head and
-- the Neck Motor6D that lived inside it -- and with them the socket and
-- attachments this module had just built. Without this, the neck of every
-- corpse in the game stayed rigid, because the entry we held pointed at a
-- joint that no longer existed and the joint that replaced it was never
-- socketed. Any other limb swap (a body package, a severed part) lands the
-- same way, so this is written against rig change in general rather than
-- against the head specifically.
function sync_ragdoll(rig: Model)
	const stored = storage[rig]
	if not stored then
		return
	end

	const live: { util.SocketMapValue } = {}
	const covered: { [Motor6D]: true } = {}
	for i, v in stored.ragdoll_joints do
		-- Parent is the liveness test: :Destroy() detaches, and a joint taken
		-- out with its host part takes its socket and attachments with it.
		if v.parent.Parent and v.socket.Parent and v.a0.Parent and v.a1.Parent then
			table.insert(live, v)
			covered[v.parent] = true
		else
			-- A half-dead entry (say the attachment survived on a part that
			-- outlived the joint) would otherwise leave litter on the rig.
			v.socket:Destroy()
			v.a0:Destroy()
			v.a1:Destroy()
		end
	end

	const joints = util.get_joint_map(rig)
	const missing: { Motor6D } = {}
	for i, joint in joints do
		if not covered[joint] then
			table.insert(missing, joint)
		end
	end
	for i, v in util.build_sockets_from_joint_map(missing) do
		-- Sockets are built disabled; a joint that arrives mid-ragdoll has to
		-- catch up to the state the rest of the rig is already in.
		v.socket.Enabled = stored.is_ragdolled
		v.parent.Enabled = not stored.is_ragdolled
		table.insert(live, v)
	end

	stored.character_joints = joints
	stored.ragdoll_joints = live

	-- The root weld hangs off the PrimaryPart and bridges the root joint's two
	-- parts, so a swap of either takes it with them.
	--
	-- `not weld` as well as `not weld.Parent`: init is allowed to have produced
	-- none at all now, so this is the repair path for both "it was destroyed"
	-- and "there never was one", and it re-runs on every sync until the rig can
	-- actually carry one.
	const weld = stored.root_weld
	if not weld or not weld.Parent then
		const rebuilt = util.ragdoll_weld_root(rig)
		if rebuilt then
			rebuilt.Enabled = stored.is_ragdolled
		end
		stored.root_weld = rebuilt
	end
end

function set_ragdoll(rig: Model, val: boolean)
	if not storage[rig] then
		warn(`ragdoll not init for {rig:GetFullName()}`)
		return
	end
	const stored = storage[rig]
	if stored.is_ragdolled == val then
		return
	end
	stored.is_ragdolled = val
	-- Re-read the rig before acting on it: the joints stored at spawn are not
	-- necessarily the joints the character has now.
	sync_ragdoll(rig)
	util.clear_colliders(stored.colliders)
	if val then
		-- Read the groups BEFORE the colliders exist, so the colliders (which
		-- are born in RAGDOLL_GROUP and destroyed on release) never end up in
		-- the restore table.
		for i, part in rig:QueryDescendants "BasePart" :: { BasePart } do
			stored.part_groups[part] = part.CollisionGroup
			part.CollisionGroup = RAGDOLL_GROUP
		end
		stored.colliders = util.create_colliders(stored.ragdoll_joints)
	else
		for part, group in stored.part_groups do
			-- A limb destroyed while limp (a swapped head, a despawn racing a
			-- revive) is not ours to write to any more.
			if part.Parent then
				part.CollisionGroup = group
			end
		end
		table.clear(stored.part_groups)
	end
	-- `.Parent` as well as nil: `sync_ragdoll` above only rebuilds a destroyed
	-- weld when the rig can carry one, so it is still possible to arrive here
	-- holding a weld that was detached in between. Writing to a destroyed
	-- instance is not an error in Roblox -- it is simply lost -- so the guard
	-- is about not believing the write landed, rather than about avoiding a
	-- throw.
	const root_weld = stored.root_weld
	if root_weld and root_weld.Parent then
		root_weld.Enabled = val
	end
	for i, v in stored.ragdoll_joints do
		if not v.a0.Parent or not v.a1.Parent then
			continue
		end
		v.socket.Enabled = val
		v.parent.Enabled = not val
	end
end

function is_init(rig: Model)
	return storage[rig] ~= nil
end

function is_ragdolled(rig: Model)
	if not storage[rig] then
		return false
	end
	return storage[rig].is_ragdolled
end

return table.freeze {
	RAGDOLL_GROUP = RAGDOLL_GROUP,
	CHARACTER_GROUP = CHARACTER_GROUP,
	is_ragdolled = is_ragdolled,
	set_ragdoll = set_ragdoll,
	init_ragdoll = init_ragdoll,
	sync_ragdoll = sync_ragdoll,
	is_init = is_init,
}
