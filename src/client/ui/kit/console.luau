-- A STATION THE PLAYER WALKS UP TO AND USES: the open/close half of a world
-- panel, without any of its contents.
--
-- Given a CollectionService tag, it puts a ProximityPrompt on every tagged part
-- and hands back an `open` source for a panel to follow. The panel itself is an
-- ordinary `kit.window` somewhere else; this only decides WHEN it is up.
--
-- WHY OPENING AND CLOSING IS ITS OWN MODULE. Every station gets the same four
-- rules wrong in the same four ways: the prompt stays live while the panel is
-- open so the player re-triggers it, the panel stays up after they walk away,
-- it survives the Roblox menu opening over it, and the prompt on a part that
-- streamed out is never cleaned up. All four are here, once.
--
-- THE CALLER OWNS THE WORDS AND THE DISTANCES. `action` and `object` are what
-- the prompt says and belong in `strings`; the two distances belong in
-- `settings`. Nothing here invents either.
const CollectionService = game:GetService "CollectionService"
const GuiService = game:GetService "GuiService"
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const mouse_unlock = require(ReplicatedStorage.Client.input["mouse-unlock"])
const render_step = require(ReplicatedStorage.Util.events["render-step"])

export type ConsoleProps = {
	tag: string,
	-- The prompt's two lines: what pressing it does, and what it is.
	action: string,
	object: string,
	-- Studs: how close to show the prompt, and how far before an open panel
	-- closes itself. The second should be the LARGER of the two, so walking a
	-- step back does not shut the panel the player is reading.
	prompt_distance: number,
	close_distance: number,
	-- A `mouse-unlock` holder name. Present means the panel wants a cursor
	-- while it is open; absent means it is read, not clicked.
	unlock: string?,
}

export type Console = {
	open: () -> boolean,
	set_open: (boolean) -> (),
	open_anywhere: () -> (),
	close: () -> (),
	destroy: () -> (),
}

-- ONE range poll shared by every station in the game, at the same quarter
-- second as `kit/surface`. A per-station RenderStepped would be a connection
-- per tagged part.
const range_step = render_step(require(ReplicatedStorage.Shared.settings).ui.SURFACE.POLL)

function console(props: ConsoleProps): Console
	const open = vide.source(false)
	-- Opened by something other than a prompt -- a command, a cutscene, a
	-- tutorial step -- so the range check must not close it. Cleared by the
	-- next ordinary open or close.
	local anywhere = false
	const prompts: { ProximityPrompt } = {}
	const points: { [BasePart]: ProximityPrompt } = {}

	local function set_open(value: boolean)
		anywhere = false
		open(value)
		if props.unlock then
			mouse_unlock.set(props.unlock, value)
		end
		-- Backwards, because a prompt whose part has gone is dropped from the
		-- list as we pass it. The prompts are DISABLED while the panel is open:
		-- leaving them live lets the player re-trigger the station they are
		-- already standing in.
		for index = #prompts, 1, -1 do
			const prompt = prompts[index]
			if prompt.Parent == nil then
				table.remove(prompts, index)
			else
				prompt.Enabled = not value
			end
		end
	end

	local function attach(instance: Instance)
		if not instance:IsA "BasePart" then
			return
		end
		-- The added signal fires again when a tag is re-applied to a part that
		-- already has its prompt.
		if points[instance] then
			return
		end
		const prompt = Instance.new "ProximityPrompt"
		prompt.ActionText = props.action
		prompt.ObjectText = props.object
		-- No hold: opening a panel is not destructive, and a hold on the way in
		-- is friction on every single use.
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = props.prompt_distance
		-- A station is usually a console set into a wall or a counter, and the
		-- sight line to its ORIGIN is routinely blocked by the very thing the
		-- prompt is attached to.
		prompt.RequiresLineOfSight = false
		prompt.Enabled = not open()
		prompt.Triggered:Connect(function()
			set_open(true)
		end)
		prompt.Parent = instance
		points[instance] = prompt
		table.insert(prompts, prompt)
	end

	-- The tagged parts already here, then the ones that arrive. Both, because
	-- streaming means neither set is reliably the whole set.
	for _, instance in CollectionService:GetTagged(props.tag) do
		attach(instance)
	end
	const added = CollectionService:GetInstanceAddedSignal(props.tag):Connect(attach)
	const removed = CollectionService:GetInstanceRemovedSignal(props.tag):Connect(function(instance)
		if instance:IsA "BasePart" then
			const prompt = points[instance]
			if prompt then
				prompt:Destroy()
				points[instance] = nil
			end
		end
		-- The last station streaming out closes the panel: there is nothing
		-- left for it to be a panel FOR.
		if next(points) == nil and not anywhere then
			set_open(false)
		end
	end)

	-- Roblox's own menu opening over the panel counts as walking away: the
	-- player's attention has gone and their next click is aimed at that menu.
	const menu_opened = GuiService.MenuOpened:Connect(function()
		set_open(false)
	end)

	const disconnect_range = range_step:connect(function()
		if not open() then
			return
		end
		const character = Players.LocalPlayer and Players.LocalPlayer.Character
		const root = if character then character:FindFirstChild "HumanoidRootPart" else nil
		-- No character means dead, respawning or still loading. Every one of
		-- those should close a panel the player cannot be standing at.
		if not root or not root:IsA "BasePart" then
			set_open(false)
			return
		end
		if anywhere then
			return
		end
		-- ANY station in range keeps it open, not the one it was opened from:
		-- a bank of terminals side by side is one panel as far as the player is
		-- concerned, and stepping from one to the next should not blink it.
		for part in points do
			if part.Parent ~= nil and (part.Position - root.Position).Magnitude <= props.close_distance then
				return
			end
		end
		set_open(false)
	end)

	return table.freeze {
		open = open,
		set_open = set_open,
		-- Opens the panel with no station involved, and pins it open against
		-- the range check.
		open_anywhere = function()
			set_open(true)
			anywhere = true
		end,
		close = function()
			set_open(false)
		end,
		destroy = function()
			added:Disconnect()
			removed:Disconnect()
			menu_opened:Disconnect()
			disconnect_range()
			-- Before destroying the prompts, so the mouse-unlock holder this
			-- console took is released rather than stranded.
			set_open(false)
			for _, prompt in points do
				prompt:Destroy()
			end
			table.clear(points)
			table.clear(prompts)
		end,
	}
end

return console
