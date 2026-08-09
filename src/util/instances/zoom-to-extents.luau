@native
function getCameraOffset(fov: number, extentsSize: Vector3)
	local halfSize = extentsSize.Magnitude / 2
	local fovDivisor = math.tan(math.rad(fov / 2))
	return halfSize / fovDivisor
end

@native
function zoomToExtents(camera: Camera, instance: Model | BasePart)
	local cf, size
	if instance:IsA "Model" then
		cf, size = instance:GetBoundingBox()
	else
		cf, size = instance.CFrame, instance.Size
	end

	if not cf or not size then
		error "INVALID ZOOM!"
	end

	local cameraOffset = getCameraOffset(camera.FieldOfView, size)
	local cameraRotation = camera.CFrame - camera.CFrame.Position

	local instancePosition = cf.Position
	camera.CFrame = cameraRotation + instancePosition + (-cameraRotation.LookVector * cameraOffset)
	camera.Focus = cameraRotation + instancePosition
end

return zoomToExtents
