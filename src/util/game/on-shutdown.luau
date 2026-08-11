const Players = game:GetService "Players"
const RunService = game:GetService "RunService"
local callbacks = {}

task.defer(function()
	Players.PlayerRemoving:Connect(function(a0: Player)
		if a0 == Players.LocalPlayer then
			for i, v in callbacks do
				task.spawn(v)
			end
		end
	end)
end)

return function(...: () -> ())
	for i, v in { ... } do
		table.insert(callbacks, v)
	end
end
