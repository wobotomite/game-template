function weld_attachments(a0: Attachment, a1: Attachment)
	const rigid = Instance.new "RigidConstraint"
	rigid.Name = `{a0.Name} -> {a1.Name}`
	rigid.Attachment0 = a0
	rigid.Attachment1 = a1

	rigid.Parent = a0
	return rigid
end

function weld_attachments_motor(a0: Attachment, a1: Attachment)
	const motor = Instance.new "Motor6D"
	motor.Part0 = a0.Parent :: never
	motor.Part1 = a1.Parent :: never
	motor.Name = `{a0.Name} -> {a1.Name}`
	motor.C0 = a0.CFrame
	motor.C1 = a1.CFrame
	motor.Parent = a0
	return motor
end

function build_welds(i1: Instance, i2: Instance, query: string?)
	const welds: { Motor6D | Weld | RigidConstraint } = {}
	for i, v in i1:QueryDescendants(`Attachment{query or ""}`) do
		const targetAttachment = i2:FindFirstChild(v.Name, true)
		if not targetAttachment then
			warn(`COULD NOT FIND ATTACHMENT {v}`)
			continue
		end
		if not targetAttachment:IsA "Attachment" then
			warn(`INVALID ATTACHMENT {targetAttachment:GetFullName()}`)
			continue
		end
		table.insert(welds, weld_attachments_motor(targetAttachment, v :: any))
	end
	return function()
		for i, v in welds do
			v:Destroy()
		end
	end
end

return table.freeze {
	build_welds = build_welds,
	weld_attachments = weld_attachments,
	weld_attachments_motor = weld_attachments_motor,
}
