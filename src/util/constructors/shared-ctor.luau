const ReplicatedStorage = game:GetService "ReplicatedStorage"

const RunService = game:GetService "RunService"

const generate_id = require(ReplicatedStorage.Util.strings["generate-id"])
const to_array = require(ReplicatedStorage.Util.tables["to-array"])

return @native function<V>(calculate: (vals: { V }, dt: number) -> ()): () -> (V) -> ()
	local vals: { [string]: V } = {}
	local do_update = true
	RunService.PostSimulation:Connect(function(delta_time: number)
		if not do_update then
			return
		end
		do_update = false
		task.spawn(calculate, to_array(vals), delta_time)
	end)
	return function()
		const id = generate_id(12)
		return function(value: V?)
			vals[id] = value
			do_update = true
		end
	end
end
