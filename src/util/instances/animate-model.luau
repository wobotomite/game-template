const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"
const render_step = require(ReplicatedStorage.Util.events["render-step"])
const on_shutdown = require(ReplicatedStorage.Util.game["on-shutdown"])
const map_table = require(ReplicatedStorage.Util.iterators["map-table"])
const bezier = require(ReplicatedStorage.Util.numbers.bezier)

const to_solve = {}

const rnd = Random.new()

const SOLVE_TIME = 1.5

@native
function solve_me(i: BasePart, old_pos: CFrame, target_pos: CFrame, delay_time: number)
	const max_offset = (old_pos.Position - target_pos.Position).Magnitude
	to_solve[i] = {
		t = -delay_time,
		speed = 1 + rnd:NextNumber(),
		old_pos = old_pos,
		target_pos = target_pos,
		control_pos = old_pos:Lerp(target_pos, 0.5)
			* CFrame.lookAlong(rnd:NextUnitVector() * max_offset, rnd:NextUnitVector()),
	}
end

on_shutdown(render_step():connect(function(a0: number)
	local parts, cfs = {}, {}
	for i, v in to_solve do
		v.t += (a0 * v.speed)

		const clamped_time = math.clamp(v.t, 0, SOLVE_TIME) / SOLVE_TIME

		i.LocalTransparencyModifier = (1 - clamped_time)

		const p_res = bezier.quad(clamped_time, v.old_pos.Position, v.control_pos.Position, v.target_pos.Position)

		table.insert(parts, i)
		table.insert(
			cfs,
			CFrame.new(p_res)
				* CFrame.new():Lerp(v.control_pos, 1 - clamped_time).Rotation
				* v.old_pos:Lerp(v.target_pos, clamped_time).Rotation
		)

		if v.t >= SOLVE_TIME then
			to_solve[i] = nil
		end
	end
	workspace:BulkMoveTo(parts, cfs)
end))

@native
function animate_model(static_model: Model, start_cframe: CFrame, end_cframe: CFrame)
	assert(RunService:IsClient(), "CAN ONLY BE RUN ON THE CLIENT!")
	const clone = static_model:Clone()

	const original_pivot = clone:GetPivot()

	local total_count = 0

	const descendant_positions = (
		map_table(clone:QueryDescendants "BasePart", function(a0: BasePart, a1: number): (CFrame, BasePart)
			a0.LocalTransparencyModifier = 1
			total_count += 1
			return original_pivot:ToObjectSpace(a0.CFrame), a0
		end)
	)

	clone:PivotTo(end_cframe)

	local delay_time = 0

	for i, v in descendant_positions do
		delay_time += (SOLVE_TIME / total_count)
		solve_me(i, start_cframe * v, end_cframe * v, delay_time)
	end

	return clone, SOLVE_TIME + delay_time
end

return animate_model
