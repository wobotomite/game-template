return @native function(mdl: Model, animation: Animation)
	for i, v in mdl:QueryDescendants "Animator" do
		return v:LoadAnimation(animation)
	end
	error(`NO ANIMATOR FOUND IN {mdl:GetFullName()}`)
end
