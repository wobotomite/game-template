return function(rate: number)
	local clock = os.clock()
	return function(): boolean
		if os.clock() - clock > rate then
			clock = os.clock()
			return true
		end
		return false
	end
end
