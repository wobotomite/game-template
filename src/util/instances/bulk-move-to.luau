const ReplicatedStorage = game:GetService "ReplicatedStorage"

const event_step_enum = require(ReplicatedStorage.Util.events["event-step-enum"])
const physics_step = require(ReplicatedStorage.Util.events["physics-step"])

const parts = {}
const cfs = {}

const bulk_move_to = workspace.BulkMoveTo
physics_step(event_step_enum.MEDIUM):connect(function(a0: number)
	if #parts == 0 then
		return
	end
	bulk_move_to(workspace, parts, cfs)
	table.clear(parts)
	table.clear(cfs)
end)

return function(p: BasePart, cf: CFrame)
	table.insert(parts, p)
	table.insert(cfs, cf)
end
