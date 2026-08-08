const ReplicatedStorage = game:GetService "ReplicatedStorage"

const synced_time = require(ReplicatedStorage.Util.numbers["synced-time"])
print "Hello world, from client!"

while task.wait() do
	workspace:SetAttribute("current_time", synced_time())
end
