const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const charm = require(ReplicatedStorage.Packages.charm)
const event_step_enum = require(ReplicatedStorage.Util.events["event-step-enum"])
const physics_step = require(ReplicatedStorage.Util.events["physics-step"])
const get_instance_id = require(ReplicatedStorage.Util.instances["get-instance-id"])
const synced_time = require(ReplicatedStorage.Util.numbers["synced-time"])
const sync_registry = require(ReplicatedStorage.Shared.services["sync-registry"])

const deep_copy = require(ReplicatedStorage.Util.tables["deep-copy"])

export type StatusEffectData = { stacks: number, added_at: number }
export type StatusEffectContainer = {
	effects: { [string]: StatusEffectData },
	last_update: number,
}
export type StatusEffectAtom = { [string]: StatusEffectContainer }
const repl_status_effects = charm.atom({} :: StatusEffectAtom)
const ID = ".STATUS_EFFECTS"
sync_registry.register(ID, repl_status_effects)

export type StatusEffectInfo = {
	name: string,
	color: Color3,
	duration: number,
	max_stacks: number,
	effect_index: string,
	icon: string,
}

const STATUS_EFFECTS: { [string]: StatusEffectInfo } = {
	confused = {
		name = "Confused!",
		color = Color3.new(1, 0, 1),
		duration = 8,
		max_stacks = 1,
		effect_index = "status-effects/confused",
		icon = "decal/status_effects/confused",
	},
}

const EMPTY_CONTAINER_TTL = 10 -- seconds an empty container may linger before removal

const containers: StatusEffectAtom = {}
-- Publish (deep copy + replicate) only on real changes, not every SLOW step.
local dirty = false
function create_container(c: Model)
	const id = get_instance_id(c)
	if containers[id] then
		return containers[id]
	end
	const container: StatusEffectContainer = {
		last_update = synced_time(),
		effects = {},
	}
	containers[id] = container
	return container
end

function add(c: Model, effect: keyof<typeof(STATUS_EFFECTS)>)
	assert(RunService:IsServer(), "CAN ONLY BE CALLED ON THE SERVER")
	const info = assert(STATUS_EFFECTS[effect], `UNKNOWN STATUS EFFECT {effect}`)
	const container = create_container(c)
	const data = container.effects[effect]
	if data then
		data.stacks = math.min(data.stacks + 1, info.max_stacks)
		data.added_at = synced_time()
	else
		container.effects[effect] = {
			stacks = 1,
			added_at = synced_time(),
		}
	end
	dirty = true
end

-- Strip ONE effect (every stack of it), leaving the rest alone. `clear` drops
-- the whole container, which is right for a respawn and wrong for anything
-- that cures a specific condition.
--
-- Returns whether the effect was actually present, so a caller that only
-- wants to act when something was really cured can tell the difference.
function remove(c: Model, effect: keyof<typeof(STATUS_EFFECTS)>): boolean
	assert(RunService:IsServer(), "CAN ONLY BE CALLED ON THE SERVER")
	const id = get_instance_id(c)
	const container = containers[id]
	if not container or not container.effects[effect] then
		return false
	end
	container.effects[effect] = nil
	container.last_update = synced_time()
	dirty = true
	return true
end

function clear(c: Model)
	const id = get_instance_id(c)
	if containers[id] then
		containers[id] = nil
		dirty = true
	end
end

function clear_all()
	if next(containers) then
		dirty = true
	end
	table.clear(containers)
end

-- This module is a SINGLETON -- one container table, one step subscription --
-- and `init` is how a server boot wires it up. A second call would add a SECOND
-- SLOW listener over the same shared state: every tick would then expire
-- effects twice and push the replication payload twice, and the only visible
-- symptom is durations running short by an inconsistent amount. Two boot paths
-- reaching one service is not exotic (a service registry plus an explicit call,
-- a re-run in Studio), and the guard belongs here rather than in each caller
-- because there is nothing a caller could check.
local started = false
function init()
	assert(RunService:IsServer(), "CAN ONLY BE CALLED ON THE SERVER")
	-- After the assert, deliberately: a CLIENT calling `init` is a bug worth
	-- an error whether or not the server has already started.
	if started then
		return
	end
	started = true

	physics_step(event_step_enum.SLOW):connect(function(a0: number)
		const now = synced_time()
		for id, container in containers do
			if next(container.effects) == nil and now - container.last_update > EMPTY_CONTAINER_TTL then
				containers[id] = nil
				dirty = true
				continue
			end
			for fx_index, effect in container.effects do
				const effect_data = STATUS_EFFECTS[fx_index]
				if not effect_data or now - effect.added_at > effect_data.duration then
					container.effects[fx_index] = nil
					container.last_update = now
					dirty = true
				end
			end
			if next(container.effects) ~= nil then
				container.last_update = now
			end
		end

		if dirty then
			dirty = false
			repl_status_effects(deep_copy(containers))
		end
	end)
end

-- SERVER-ONLY, and not merely by convention like `add`/`remove` above: this
-- MINTS an id. get_instance_id writes the attribute when the instance has none
-- yet, and on a client that write is local, does not replicate, and will never
-- be corrected -- the server only re-sends the real id if IT changes, and it
-- won't. So a client call here fabricates an id that matches nothing in the
-- replicated table AND clobbers the real one locally, permanently, for that
-- instance. Silent, and close to undebuggable from the symptom.
--
-- There is no assert because the two getters are read-only and the util is
-- shared template code; the rule is the comment. A client that needs this
-- reads the attribute PASSIVELY (never get_instance_id) and indexes the atom
-- itself.
function get_status_effects(c: Model): StatusEffectContainer
	return repl_status_effects()[get_instance_id(c)] or { last_update = 0, effects = {} }
end

function get_status_effect_count(c: Model, effect: keyof<typeof(STATUS_EFFECTS)>)
	const fx = get_status_effects(c).effects[effect]
	if not fx then
		return 0
	end
	return fx.stacks
end

function get_info(effect: keyof<typeof(STATUS_EFFECTS)>): StatusEffectInfo
	return assert(STATUS_EFFECTS[effect], `UNKNOWN STATUS EFFECT {effect}`)
end

if RunService:IsServer() then
	init()
end

return table.freeze {
	add = add,
	remove = remove,
	clear = clear,
	clear_all = clear_all,
	get_status_effects = get_status_effects,
	get_status_effect_count = get_status_effect_count,
	get_info = get_info,
	reactive_getter = charm.computed(function()
		return repl_status_effects()
	end),
}
