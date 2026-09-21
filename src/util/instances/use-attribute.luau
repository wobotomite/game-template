return @native function<T>(k: string, default: T?)
	return table.freeze {
		set = function(i: Instance, v: T)
			i:SetAttribute(k, v)
		end,
		get = function(i: Instance)
			-- Not `or default`: an attribute explicitly set to `false` is a value,
			-- and `or` replaced it with the default.
			const v = i:GetAttribute(k)
			return if v == nil then default else v
		end,
		name = k,
		on_changed = function(i: Instance)
			return i:GetAttributeChangedSignal(k)
		end,
	}
end
