const ReplicatedStorage = game:GetService "ReplicatedStorage"
const TweenService = game:GetService "TweenService"

const shared_ctor = require(ReplicatedStorage.Util.constructors["shared-ctor"])
const reduce_number_array = require(ReplicatedStorage.Util.tables["reduce-number-array"])

local BASE_FOV = 70
return shared_ctor(function(vals: { number }, dt: number)
	const total_fov = BASE_FOV + reduce_number_array(vals)

	TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.5), { FieldOfView = total_fov }):Play()
end)
