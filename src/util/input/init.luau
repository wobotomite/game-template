const Players = game:GetService "Players"
const RunService = game:GetService "RunService"

export type ActionDef = {
	type: Enum.InputActionType?,
	keys: { Enum.KeyCode }?,
	modifier: Enum.KeyCode?,
	up: Enum.KeyCode?,
	down: Enum.KeyCode?,
	left: Enum.KeyCode?,
	right: Enum.KeyCode?,
	forward: Enum.KeyCode?,
	backward: Enum.KeyCode?,
	buttons: { GuiButton }?,
	enabled: boolean?,
}

export type ContextConfig = {
	sink: boolean?,
	priority: number?,
	enabled: boolean?,
}

local input_contexts_folder: Folder? = nil

function get_input_contexts_folder(): Folder
	-- `.Parent`, because a cached folder can be DESTROYED under us (a character
	-- reset script that clears the Player's children, a debug wipe). Contexts
	-- parented to a destroyed folder are silently inert: no error, no input.
	const cached = input_contexts_folder
	if cached and cached.Parent then
		return cached
	end

	const player = Players.LocalPlayer
	const existing = player:FindFirstChild "InputContexts"
	if existing and existing:IsA "Folder" then
		input_contexts_folder = existing
		return existing
	end

	const folder = Instance.new "Folder"
	folder.Name = "InputContexts"
	folder.Parent = player
	input_contexts_folder = folder
	return folder
end

function infer_type(def: ActionDef): Enum.InputActionType
	if def.type then
		return def.type
	end
	if def.forward or def.backward then
		return Enum.InputActionType.Direction3D
	end
	if def.left or def.right then
		return Enum.InputActionType.Direction2D
	end
	if def.up or def.down then
		return Enum.InputActionType.Direction1D
	end
	return Enum.InputActionType.Bool
end

function normalize_def(def: ActionDef | { Enum.KeyCode }): ActionDef
	if typeof((def :: any)[1]) == "EnumItem" then
		return { type = Enum.InputActionType.Bool, keys = def :: any }
	end
	const d = def :: ActionDef
	return {
		type = infer_type(d),
		keys = d.keys,
		modifier = d.modifier,
		up = d.up,
		down = d.down,
		left = d.left,
		right = d.right,
		forward = d.forward,
		backward = d.backward,
		buttons = d.buttons,
		enabled = d.enabled,
	}
end

const action_mt = {}
action_mt.__index = action_mt

export type Action = typeof(setmetatable({} :: { instance: InputAction }, action_mt))

function action_mt.bind_key(self: Action, key_code: Enum.KeyCode, modifier: Enum.KeyCode?): InputBinding
	const binding = Instance.new "InputBinding"
	binding.KeyCode = key_code
	if modifier then
		binding.PrimaryModifier = modifier
	end
	binding.Parent = self.instance
	return binding
end

function action_mt.bind_direction(self: Action, def: ActionDef): InputBinding
	const binding = Instance.new "InputBinding"
	if def.up then
		binding.Up = def.up
	end
	if def.down then
		binding.Down = def.down
	end
	if def.left then
		binding.Left = def.left
	end
	if def.right then
		binding.Right = def.right
	end
	if def.forward then
		binding.Forward = def.forward
	end
	if def.backward then
		binding.Backward = def.backward
	end
	binding.Parent = self.instance
	return binding
end

-- Destroying the InputAction takes its bindings and its signal connections
-- with it. A panel that makes actions when it mounts needs this on unmount, or
-- every reopen adds another live copy of the same key.
function action_mt.destroy(self: Action)
	self.instance:Destroy()
end

function action_mt.append(self: Action, gui_button: GuiButton): InputBinding
	const binding = Instance.new "InputBinding"
	binding.UIButton = gui_button
	binding.Parent = self.instance
	return binding
end

function new_action(input_context: InputContext, name: string, def: ActionDef | { Enum.KeyCode }): Action
	const normalized = normalize_def(def)

	const instance = Instance.new "InputAction"
	instance.Name = name
	instance.Type = normalized.type :: Enum.InputActionType
	if normalized.enabled ~= nil then
		instance.Enabled = normalized.enabled
	end

	const self = setmetatable({ instance = instance }, action_mt)

	if normalized.keys then
		for _, key_code in normalized.keys do
			self:bind_key(key_code, normalized.modifier)
		end
	end

	if
		normalized.up
		or normalized.down
		or normalized.left
		or normalized.right
		or normalized.forward
		or normalized.backward
	then
		self:bind_direction(normalized)
	end

	if normalized.buttons then
		for _, gui_button in normalized.buttons do
			self:append(gui_button)
		end
	end

	instance.Parent = input_context

	return self
end

const context_mt = {}
context_mt.__index = context_mt

export type Context = typeof(setmetatable({} :: { instance: InputContext }, context_mt))

function context_mt.action(self: Context, name: string, def: ActionDef | { Enum.KeyCode }): Action
	return new_action(self.instance, name, def)
end

-- Takes every action under it along. See `action_mt.destroy`.
function context_mt.destroy(self: Context)
	self.instance:Destroy()
end

function context(name: string, config: ContextConfig?): Context
	assert(RunService:IsClient(), "RUNS ONLY ON THE CLIENT!")

	const instance = Instance.new "InputContext"
	instance.Name = name

	if config then
		if config.sink ~= nil then
			instance.Sink = config.sink
		end
		if config.priority ~= nil then
			instance.Priority = config.priority
		end
		if config.enabled ~= nil then
			instance.Enabled = config.enabled
		end
	end

	instance.Parent = get_input_contexts_folder()

	return setmetatable({ instance = instance }, context_mt)
end

return table.freeze {
	context = context,
}
