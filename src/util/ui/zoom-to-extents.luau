-- Ported from hide-n-seek (Shared/util/zoom-to-extents): dolly a viewport
-- camera back along its look vector until the model's bounding box fits the
-- field of view.

@native
local function get_camera_offset(fov: number, extents_size: Vector3): number
	local half_size = extents_size.Magnitude / 2
	local fov_divisor = math.tan(math.rad(fov / 2))
	return half_size / fov_divisor
end

@native
local function zoom_to_extents(camera: Camera, instance: Model | BasePart)
	local cf, size
	if instance:IsA "Model" then
		cf, size = instance:GetBoundingBox()
	else
		cf, size = instance.CFrame, instance.Size
	end

	if not cf or not size then
		error "INVALID ZOOM!"
	end

	local camera_offset = get_camera_offset(camera.FieldOfView, size)
	local camera_rotation = camera.CFrame - camera.CFrame.Position

	local instance_position = cf.Position
	camera.CFrame = camera_rotation + instance_position + (-camera_rotation.LookVector * camera_offset)
	camera.Focus = camera_rotation + instance_position
end

return zoom_to_extents
