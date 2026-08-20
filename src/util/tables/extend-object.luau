return @native function<O, E>(target: {} & O, extend_with: {} & E): setmetatable<E, { __index: O }>
	return setmetatable(extend_with, { __index = target })
end
