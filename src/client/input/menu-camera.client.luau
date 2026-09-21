-- STOPPING THE WORLD MOVING WHILE A MENU IS OPEN.
--
-- Roblox's PlayerModule keeps driving the character and the camera regardless
-- of what the game has on screen, so without this the player walks off a ledge
-- while reading a shop, and dragging a slider spins the camera with it.
--
-- REACHES INTO THE PLAYERMODULE, which is the only way: `GetControls()` is
-- public, but there is no supported API for "ignore camera input", so the
-- camera half pulls `CameraInput` out of the module and calls its own
-- `setInputEnabled`. That is the one place in the client that depends on
-- Roblox's internals, and it is here, in one script, rather than spread over
-- every panel that needs it.
--
-- A SCRIPT, not a module: it is wiring with no exports, it runs once, and
-- nothing should be able to require it and get a second copy of these effects.
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const RunService = game:GetService "RunService"

const vide = require(ReplicatedStorage.Packages.vide)
const menu_state = require(ReplicatedStorage.Client.ui["menu-state"])

-- Yielding is free here in a way it is not inside a module: nothing is waiting
-- on this script to finish.
while not Players.LocalPlayer do
	task.wait()
end
const scripts = Players.LocalPlayer:WaitForChild "PlayerScripts"
const player_module = scripts:WaitForChild "PlayerModule"
const controls = require(player_module :: ModuleScript):GetControls()
const camera_module = player_module:WaitForChild "CameraModule"
const camera_input = require(camera_module:WaitForChild "CameraInput" :: ModuleScript)

vide.root(function()
	vide.effect(function()
		if menu_state.state() == "none" then
			return
		end
		controls:Disable()
		camera_input.setInputEnabled(false)
		-- AND AGAIN EVERY FRAME, just before the camera runs. The PlayerModule
		-- re-enables its own input from inside its update, so disabling it once
		-- lasts exactly until the next frame.
		RunService:BindToRenderStep("MenuCameraInput", Enum.RenderPriority.Camera.Value - 1, function()
			camera_input.setInputEnabled(false)
		end)
		vide.cleanup(function()
			RunService:UnbindFromRenderStep "MenuCameraInput"
			controls:Enable()
			-- NOT unconditionally true: a scriptable camera is one the game is
			-- driving itself (a cutscene, a fixed view), and handing input back
			-- to the PlayerModule there would fight it. Re-read now rather than
			-- remembered from when the menu opened, because the game may have
			-- taken the camera while it was up.
			const camera = workspace.CurrentCamera
			camera_input.setInputEnabled(camera ~= nil and camera.CameraType ~= Enum.CameraType.Scriptable)
		end)
	end)
end)
