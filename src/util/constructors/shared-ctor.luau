const ReplicatedStorage = game:GetService "ReplicatedStorage"

const RunService = game:GetService "RunService"

const generate_id = require(ReplicatedStorage.Util.strings["generate-id"])
const to_array = require(ReplicatedStorage.Util.tables["to-array"])

return @native function<V>(calculate: (vals: { V }) -> ()): () -> (V) -> ()
	local vals: { [string]: V } = {}
	local do_update = true
	RunService.PostSimulation:Connect(function()
		if not do_update then
			return
		end
		do_update = false
		task.spawn(calculate, to_array(vals))
	end)
	return function()
		const id = generate_id(12)
		return function(value: V?)
			vals[id] = value
			do_update = true
		end
	end
end
