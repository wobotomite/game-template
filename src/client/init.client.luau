const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const animate_model = require(ReplicatedStorage.Util.instances["animate-model"])
print "Hello world, from client!"

task.wait(5)

const mdl, delay_time =
	animate_model(workspace.house, Players.LocalPlayer.Character:GetPivot(), CFrame.new() + Vector3.new(0, 23, 0))
mdl.Parent = workspace

task.delay(delay_time, function()
	mdl:ScaleTo(0.5)
end)
