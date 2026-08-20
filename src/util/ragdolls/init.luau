const RunService = game:GetService "RunService"

const util = require(script.util)

if RunService:IsServer() then
	workspace:RegisterCollisionGroup "RagdollColliders"
	workspace:CollisionGroupSetCollidable("RagdollColliders", "RagdollColliders", false)
end

type RagdollObject = {
	rig: Model,
	colliders: { BasePart },
	root_weld: Weld,
	character_joints: { Motor6D },
	ragdoll_joints: { util.SocketMapValue },
	is_ragdolled: boolean,
}

const storage = setmetatable({}, { __mode = "k" }) :: { [Model]: RagdollObject }

function init_ragdoll(rig: Model)
	if storage[rig] then
		warn "already init"
		return
	end
	const joint_map = util.get_joint_map(rig)

	storage[rig] = {
		rig = rig,
		colliders = {},
		root_weld = util.ragdoll_weld_root(rig),
		character_joints = joint_map,
		ragdoll_joints = util.build_sockets_from_joint_map(joint_map),
		is_ragdolled = false,
	}
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
	util.clear_colliders(stored.colliders)
	if val then
		stored.colliders = util.create_colliders(stored.ragdoll_joints)
	end
	stored.root_weld.Enabled = val
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
	is_ragdolled = is_ragdolled,
	set_ragdoll = set_ragdoll,
	init_ragdoll = init_ragdoll,
	is_init = is_init,
}
