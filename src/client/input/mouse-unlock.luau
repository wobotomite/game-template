const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const UserInputService = game:GetService "UserInputService"

const vide = require(ReplicatedStorage.Packages.vide)

-- First-person locks the mouse; UIs need it back. The classic trick: an
-- invisible full-screen TextButton with Modal = true (and Active = false so
-- it sinks no input) unlocks the cursor while enabled. Any number of UIs can
-- hold the unlock; it releases when the last one closes.

const local_player = Players.LocalPlayer

const screen = vide.create "ScreenGui" {
	Name = "MouseUnlock",
	ResetOnSpawn = false,
	Enabled = false,
	DisplayOrder = -100,

	vide.create "TextButton" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		Modal = true,
		Active = false,
		Selectable = false,
	},

	Parent = local_player:WaitForChild "PlayerGui",
}

-- `boolean`, not `true`: the removal below assigns nil, and `{ [string]: true }`
-- makes `true?` an error on the way in even though nil-to-remove is the whole
-- idiom.
const holders: { [string]: boolean } = {}

-- The cursor ICON follows the unlock. Under LockFirstPerson the mouse is pinned
-- to the middle of the screen, where the icon sits on top of the crosshair and
-- cannot click a thing -- so it is hidden while nothing holds the unlock, and
-- comes straight back the moment something does. That covers every holder at
-- once, which is the point: a UI that unlocks the mouse and then draws no
-- cursor to click with is worse than no unlock at all.
--
-- Only while the camera is locked, because the lobby is third-person and there
-- the cursor is the ONLY way to press anything. Driven off the CameraMode
-- signal as well as set(), since first-person-camera locks the camera from its
-- own script and may boot after this module is first required.
local function apply_icon()
	const locked = local_player.CameraMode == Enum.CameraMode.LockFirstPerson
	UserInputService.MouseIconEnabled = not locked or screen.Enabled
end

local function set(key: string, open: boolean)
	if open then
		holders[key] = true
	else
		holders[key] = nil
	end
	screen.Enabled = next(holders) ~= nil
	apply_icon()
end

local_player:GetPropertyChangedSignal("CameraMode"):Connect(apply_icon)
apply_icon()

return table.freeze {
	set = set,
}
