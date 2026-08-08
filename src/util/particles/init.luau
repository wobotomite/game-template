
@native
function get_max_emit_lifetime(p: Instance): number
	local max = 0
	for i, v in p:QueryDescendants "ParticleEmitter" do
		max = math.max(max, v.Lifetime.Max)
	end

	return max
end
@native
function emit_descendants(p: Instance): number
	const lifetime = get_max_emit_lifetime(p)
	for i, v in p:QueryDescendants "ParticleEmitter" do
		const val = (v:GetAttribute "EmitCount" or 1)
		if typeof(val) ~= "number" then
			continue
		end

		v:Emit(val)
	end
	return lifetime
end

@native
function toggle_emit(p: Instance, enable: boolean)
	for i, v in p:QueryDescendants "ParticleEmitter" do
		v.Enabled = enable
	end
end

return table.freeze {
	emit_descendants = emit_descendants,
	get_max_emit_lifetime = get_max_emit_lifetime,
	toggle_emit = toggle_emit,
}
