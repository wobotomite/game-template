const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
local function use_event_listener<T>(event: RBXScriptSignal<T>, callback: (T) -> ()): ()
	vide.cleanup(event:Connect(callback))
end

return use_event_listener
