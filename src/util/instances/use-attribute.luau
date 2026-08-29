return @native function<T>(k: string, default: T?)
	return table.freeze {
		set = function(i: Instance, v: T)
			i:SetAttribute(k, v)
		end,
		get = function(i: Instance)
			return i:GetAttribute(k) or default
		end,
		name = k,
		on_changed = function(i: Instance)
			return i:GetAttributeChangedSignal(k)
		end,
	}
end
