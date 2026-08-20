const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const charm = require(ReplicatedStorage.Packages.charm)
const charm_sync = require(ReplicatedStorage.Packages["charm-sync"])
const use_throttle = require(ReplicatedStorage.Util.constructors["use-throttle"])
const event_step_enum = require(ReplicatedStorage.Util.events["event-step-enum"])
const physics_step = require(ReplicatedStorage.Util.events["physics-step"])
const get_instance_id = require(ReplicatedStorage.Util.instances["get-instance-id"])
const synced_time = require(ReplicatedStorage.Util.numbers["synced-time"])
const observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

const deep_copy = require(ReplicatedStorage.Util.tables["deep-copy"])

export type StatusEffectData = { stacks: number, added_at: number }
export type StatusEffectContainer = {
	effects: { [string]: StatusEffectData },
	last_update: number,
}
export type StatusEffectAtom = { [string]: StatusEffectContainer }
const repl_status_effects = charm.atom({} :: StatusEffectAtom)
const ID = ".STATUS_EFFECTS"
if RunService:IsClient() then
	charm_sync.client.addSignals {
		[ID] = repl_status_effects,
	}
else
	observe_players(function(a0: Player): () -> ()
		charm_sync.server.addSignalsToClient(a0, {
			[ID] = repl_status_effects,
		})
	end)
end

const STATUS_EFFECTS = {
	confused = {
		name = "Confused!",
		color = Color3.new(1, 0, 1),
		duration = 8,
		effect_index = "status-effects/confused",
		icon = "decal/status_effects/confused",
	},
}

const containers: StatusEffectAtom = {}
function create_container(c: Model)
	const id = get_instance_id(c)
	if containers[id] then
		return containers[id]
	end
	const container: StatusEffectContainer = {
		last_update = 0,
		effects = {},
	}
	containers[id] = container
	return container
end

function add(c: Model, effect: keyof<typeof(STATUS_EFFECTS)>)
	assert(RunService:IsServer(), "CAN ONLY BE CALLED ON THE SERVER")
	const container = create_container(c)
	const data = container.effects[effect]
	if data then
		data.stacks = math.min(data.stacks + 1, effect.max_stacks)
		data.added_at = synced_time()
	else
		container.effects[effect] = {
			stacks = 1,
			added_at = synced_time(),
		}
	end
end

function clear(c: Model)
	containers[get_instance_id(c)] = nil
end

function clear_all()
	table.clear(containers)
end

function init()
	assert(RunService:IsServer(), "CAN ONLY BE CALLED ON THE SERVER")

	physics_step(event_step_enum.SLOW):connect(function(a0: number)
		for id, container in containers do
			if next(container.effects) == nil and container.last_update > 10 then
				containers[id] = nil
				continue
			end
			for fx_index, effect in container.effects do
				const effect_data = STATUS_EFFECTS[fx_index]
				if not effect_data or synced_time() - effect.added_at > effect_data.duration then
					container.effects[fx_index] = nil
				end
			end
			container.last_update = synced_time()
		end

		repl_status_effects(deep_copy(containers))
	end)
end

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

if RunService:IsServer() then
	init()
end

return table.freeze {
	add = add,
	clear = clear,
	clear_all = clear_all,
	get_status_effects = get_status_effects,
	get_status_effect_count = get_status_effect_count,
	reactive_getter = charm.computed(function()
		return repl_status_effects()
	end),
}
