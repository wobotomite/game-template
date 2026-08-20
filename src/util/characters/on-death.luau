local ReplicatedStorage = game:GetService "ReplicatedStorage"

local observe_character = require(ReplicatedStorage.Util.observers["observe-character"])
local observe_players = require(ReplicatedStorage.Util.observers["observe-players"])

local DEAD_TAG = "__dead"

local connections: { (instance: Instance) -> () } = {}

local function fire_for(instance: Instance)
	for _, callback in connections do
		task.defer(callback, instance)
	end
end

local function is_dead(instance: Instance): boolean
	return instance:HasTag(DEAD_TAG)
end

local function mark(instance: Instance)
	if is_dead(instance) then
		return
	end
	instance:AddTag(DEAD_TAG)
	fire_for(instance)
end

local function register(_self: unknown, callback: (instance: Instance) -> ()): () -> ()
	table.insert(connections, callback)
	return function()
		local idx = table.find(connections, callback)
		if idx then
			table.remove(connections, idx)
		end
	end
end

local on_death = setmetatable({
	mark = mark,
	is_dead = is_dead,
}, { __call = register })

observe_players(function(player: Player)
	return observe_character(player, function(character: Model)
		local humanoid = character:FindFirstChildOfClass "Humanoid" or character:WaitForChild("Humanoid", 5)
		if not humanoid or not humanoid:IsA "Humanoid" then
			return
		end

		if humanoid:GetState() == Enum.HumanoidStateType.Dead then
			mark(character)
		end

		local con = humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Dead then
				mark(character)
			end
		end)

		return function()
			con:Disconnect()
		end
	end)
end)

return on_death
