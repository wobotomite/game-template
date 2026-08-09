const ReplicatedStorage = game:GetService "ReplicatedStorage"

print "Hello world, from client!"

function benchmark(cb: () -> (), sample_size: number)
	local t = os.clock()
	for i = 1, sample_size do
		cb()
	end
	print(`SAMPLE SIZE: {sample_size}, RESULT: {os.clock() - t}`)
end

benchmark(function() end)
