local ReplicatedStorage = game:GetService "ReplicatedStorage"

local vide = require(ReplicatedStorage.Packages.vide)
local zoom_to_extents = require(ReplicatedStorage.Util.ui["zoom-to-extents"])

-- 3D model preview (hide-n-seek's weapon-inventory pattern): a ViewportFrame
-- with its own WorldModel + camera, aimed from `Orbit` (a direction offset
-- from the model pivot) and dollied back until the model fits the frame.

export type ViewportProps = {
	Model: Model,
	Size: (UDim2 | () -> UDim2)?,
	Position: (UDim2 | () -> UDim2)?,
	AnchorPoint: Vector2?,
	Visible: (boolean | () -> boolean)?,
	ZIndex: number?,
	LayoutOrder: number?,
	Orbit: Vector3?, -- camera offset direction from the pivot (default front-right)
	-- Dolly multiplier applied after the fit: < 1 pushes in. The fit sizes the
	-- model to the frame's VERTICAL fov, so a wide, short frame leaves the
	-- model looking tiny — pull the camera in to fill it.
	Zoom: number?,
	Ambient: Color3?,
	LightColor: Color3?,
}

return function(props: ViewportProps)
	local camera = Instance.new "Camera"
	local orbit = props.Orbit or Vector3.new(1, 0.3, -4)
	local zoom = props.Zoom or 1

	return vide.create "ViewportFrame" {
		Name = "Preview",
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Visible = props.Visible,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		LightDirection = -Vector3.one,
		LightColor = props.LightColor or Color3.new(1, 1, 1),
		Ambient = props.Ambient or Color3.new(1, 1, 1),
		CurrentCamera = camera,

		vide.create "WorldModel" {
			props.Model,
			camera,
			vide.action(function()
				local pivot = props.Model:GetPivot().Position
				camera.CFrame = CFrame.lookAt(pivot + orbit, pivot)
				zoom_to_extents(camera, props.Model)
				if zoom ~= 1 then
					local focus = camera.Focus.Position
					camera.CFrame = CFrame.lookAt(focus + (camera.CFrame.Position - focus) * zoom, focus)
				end
			end),
		},
	}
end
