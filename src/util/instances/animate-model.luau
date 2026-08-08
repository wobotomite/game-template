return @native function(static_model: Model)
	return function(cf: CFrame)
		const clone = static_model:Clone()
		clone:PivotTo(cf)
		warn "UNIMPLEMENTED"
		return clone
	end
end
