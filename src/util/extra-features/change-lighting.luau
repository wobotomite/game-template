const Lighting = game:GetService "Lighting"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const TweenService = game:GetService "TweenService"

const tags = require(ReplicatedStorage.Shared.records.tags)

const IGNORE_TAG = tags.LIGHTING_ENGINE_IGNORE

const WHITELISTED_CLASSES = {
	"Atmosphere",
	"BloomEffect",
	"DepthOfFieldEffect",
	"SunRaysEffect",
	"ColorCorrectionEffect",
	"BlurEffect",
	"Sky",
}

const LIGHTING_PROPERTIES = {
	ColorShift_Top = "Color3",
	ColorShift_Bottom = "Color3",
	Ambient = "Color3",
	OutdoorAmbient = "Color3",
	Brightness = "number",
	EnvironmentDiffuseScale = "number",
	EnvironmentSpecularScale = "number",
	ClockTime = "number",
	ExposureCompensation = "number",
	ShadowSoftness = "number",
}

const PROPERTIES = {
	Atmosphere = {
		Density = "number",
		Offset = "number",
		Color = "Color3",
		Decay = "Color3",
		Glare = "number",
		Haze = "number",
	},
	BloomEffect = {
		Enabled = "boolean",
		Intensity = "number",
		Size = "number",
		Threshold = "number",
	},
	DepthOfFieldEffect = {
		Enabled = "boolean",
		FarIntensity = "number",
		FocusDistance = "number",
		InFocusRadius = "number",
		NearIntensity = "number",
	},
	SunRaysEffect = {
		Enabled = "boolean",
		Intensity = "number",
		Spread = "number",
	},
	ColorCorrectionEffect = {
		Enabled = "boolean",
		Brightness = "number",
		Contrast = "number",
		Saturation = "number",
		TintColor = "Color3",
	},
	BlurEffect = {
		Enabled = "boolean",
		Size = "number",
	},
	Sky = {
		MoonAngularSize = "number",
		StarCount = "number",
		SunAngularSize = "number",
		CelestialBodiesShown = "boolean",
		SkyboxOrientation = "Vector3",

		-- evil:
		SunTextureId = "string",
		MoonTextureId = "string",

		SkyboxBk = "string",
		SkyboxLf = "string",
		SkyboxFt = "string",
		SkyboxDn = "string",
		SkyboxUp = "string",
		SkyboxRt = "string",
	},
}

const tween_info = TweenInfo.new(1)

function create_blank_instance(class_name: string, parent: Instance): Instance?
	const prop_list = PROPERTIES[class_name]
	if not prop_list then
		return nil
	end
	const instance = Instance.new(class_name) :: any

	for i, v in prop_list do
		if v == "number" then
			instance[i] = 0
		elseif v == "Color3" then
			instance[i] = Color3.new(1, 1, 1)
		elseif v == "boolean" then
			instance[i] = false
		end
	end

	instance.Parent = parent
	return instance
end
-- WRITTEN AND NEVER READ. `fade_out` sets a flag here and nothing in this
-- module (or any other) consults it -- a half-finished idea left standing.
--
-- It is kept rather than removed, with STRONG keys, because the weak version
-- was a trap for whoever eventually wires up the read: in Roblox an Instance's
-- Lua-side wrapper is collectable whenever nothing on the Lua side holds it
-- strongly, whatever the DataModel thinks, so a weak-keyed entry for a live,
-- parented instance is dropped on the first GC cycle. Measured elsewhere in
-- this tree: 0 of 40 entries survived. The same mistake in util/ragdolls froze
-- corpses upright, and the symptom pointed nowhere near the table.
--
-- The set is bounded (one entry per lighting instance the engine has), so
-- strong keys cost nothing here.
const did_fade_out: { [Instance]: boolean } = {}
function fade_out(instance: Instance?)
	if not instance then
		return
	end
	did_fade_out[instance] = true
	const prop_list = PROPERTIES[instance.ClassName]
	if not prop_list then
		return
	end

	local new_list: { [string]: any } = {}
	for i, v in prop_list do
		if v == "number" then
			new_list[i] = 0
		elseif v == "Color3" then
			new_list[i] = Color3.new(1, 1, 1)
		end
	end

	TweenService:Create(instance, tween_info, new_list):Play()
	task.delay(tween_info.Time, function()
		instance:Destroy()
	end)
end
function morph<T>(origin: T & Instance, target: T & Instance)
	const prop_list = PROPERTIES[origin.ClassName]
	if not prop_list then
		return
	end

	local new_list = {}
	for i, v in prop_list do
		if v == "boolean" or v == "string" then
			(origin :: any)[i] = (target :: any)[i]
			continue
		end
		new_list[i] = (target :: any)[i]
	end

	TweenService:Create(origin, tween_info, new_list):Play()
end

local currently_reconciled: Instance?

function update_lighting(attributes: { [string]: any })
	local list = {}
	for i: string, v in pairs(LIGHTING_PROPERTIES :: { [string]: string }) do
		if attributes[i] then
			list[i] = attributes[i]
		end
	end
	TweenService:Create(Lighting, tween_info, list):Play()
end

function reconcile_children(new: Instance)
	if currently_reconciled and new == currently_reconciled then
		return
	end

	currently_reconciled = new
	update_lighting(new:GetAttributes())
	for _, class_name in WHITELISTED_CLASSES do
		const target_num = new:QueryDescendants(`>{class_name}:not(.{IGNORE_TAG})`)
		const current_num = Lighting:QueryDescendants(`>{class_name}:not(.{IGNORE_TAG})`)

		while #target_num > #current_num do
			const blank = create_blank_instance(class_name, Lighting)
			if blank then
				table.insert(current_num, blank)
			else
				break
			end
			task.wait()
		end
		while #target_num < #current_num do
			const shifted = table.remove(current_num, 1)
			fade_out(shifted)
			task.wait()
		end

		for i = 1, #current_num do
			local c1 = target_num[i]
			local c2 = current_num[i]
			morph(c2, c1)
		end
	end
end

return reconcile_children
