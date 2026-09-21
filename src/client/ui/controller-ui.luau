-- DRIVING THE UI WITH A GAMEPAD.
--
-- Roblox ships gamepad GUI navigation, and it is not usable for a game's own
-- menus: it selects across every ScreenGui at once, it picks a starting item by
-- rules nobody can predict, and it has no idea which of four open panels the
-- player is actually looking at. So this module turns it off while a game panel
-- is up and does the job itself.
--
-- WHAT IT OWNS. A registry of selectable widgets (`register`, called by the
-- kit's buttons for you), a registry of open windows (`window`), and one
-- InputContext holding confirm, cancel, the two carousel shoulder buttons and
-- the navigation stick. The NEWEST open window is the root: navigation is
-- confined to it, which is what makes a confirmation opened over a shop behave
-- like a modal without anyone writing modal logic.
--
-- Directional navigation is geometric, not a hand-authored neighbour graph:
-- press right and the nearest widget to the right is selected, where "nearest"
-- leans heavily along the pressed axis (`GAMEPAD.NAV_AXIS_BIAS`). A layout can
-- be rearranged without anyone rewiring the focus order.
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const Players = game:GetService "Players"
const GuiService = game:GetService "GuiService"
const UserInputService = game:GetService "UserInputService"
const RunService = game:GetService "RunService"

const vide = require(ReplicatedStorage.Packages.vide)
const input = require(ReplicatedStorage.Util.input)
const state = require(ReplicatedStorage.Client.input["input-state"])
const settings = require(ReplicatedStorage.Shared.settings)
const PAD = settings.controls.GAMEPAD
const KEY = settings.ui.BUTTON_HOTKEY

type Target = {
	object: GuiObject,
	enabled: () -> boolean,
	press: () -> (),
	release: (() -> ())?,
	-- The keyboard key this widget claims, used to find the CANCEL widget when
	-- B is pressed -- the player expects B to close the panel wherever the
	-- focus happens to be sitting.
	key: Enum.KeyCode?,
	-- A widget that does not activate but STEPS: a carousel, a slider. Takes
	-- the stick along its own axis, and takes the shoulder buttons.
	cycle: ((number) -> ())?,
	vertical: boolean?,
}

const targets: { [GuiObject]: Target } = {}
-- Insertion order, not a stack: a window reopening moves to the top rather than
-- being pushed onto one, so no bookkeeping is needed for a panel that closes
-- out of order.
const windows: { [GuiObject]: number } = {}
-- Bumped to force the root search below to run again. The search reads
-- non-reactive state (the two registries, instance visibility), so this is the
-- one dependency that makes it re-run at all.
const revision = vide.source(0)
const selected = vide.source(GuiService.SelectedObject)
const current = vide.source(nil :: GuiObject?)
local order = 0
local held: Target? = nil
local direction = Vector2.zero
local next_step = 0
-- A button ALREADY DOWN when a panel opens must not fire. Otherwise the press
-- that opened the panel activates whatever the panel put under the cursor; the
-- pad has to be released once before it counts.
local confirm_armed = false
local cancel_armed = false

-- Visible ALL THE WAY UP, and in this player's own PlayerGui. A widget inside a
-- hidden frame still reports `Visible = true` for itself, and a tree that has
-- been unparented reports it too -- both would otherwise be selectable.
function visible(object: GuiObject): boolean
	local ancestor: Instance? = object
	while ancestor do
		if ancestor:IsA "GuiObject" and not ancestor.Visible then
			return false
		end
		if ancestor:IsA "LayerCollector" and not ancestor.Enabled then
			return false
		end
		if ancestor:IsA "PlayerGui" then
			return ancestor.Parent == Players.LocalPlayer
		end
		ancestor = ancestor.Parent
	end
	return false
end

-- `ControllerSkip` is the opt-out: an attribute rather than a parameter so a
-- game can mark one instance in a shared widget without forking the widget.
function valid(target: Target, root: GuiObject): boolean
	return target.object:GetAttribute "ControllerSkip" ~= true
		and target.object:IsDescendantOf(root)
		and target.enabled()
		and visible(target.object)
end

function release()
	const target = held
	held = nil
	if target and target.release then
		target.release()
	end
end

-- The opening selection, and the answer to "which widget does this key mean".
-- Ranked: a stepper first, then the panel's primary action, then anything else;
-- ties broken top-to-bottom, left-to-right, which is reading order on every
-- layout the kit produces.
function choose(root: GuiObject, key: Enum.KeyCode?): Target?
	local best: Target? = nil
	local rank = math.huge
	for _, target in targets do
		if not valid(target, root) or (key and target.key ~= key) then
			continue
		end
		const priority = if target.cycle then 0 else if target.key == KEY.PRIMARY then 1 else 2
		const position = target.object.AbsolutePosition
		const previous = if best then best.object.AbsolutePosition else Vector2.new(math.huge, math.huge)
		if
			priority < rank
			or (
				priority == rank and (position.Y < previous.Y or (position.Y == previous.Y and position.X < previous.X))
			)
		then
			best = target
			rank = priority
		end
	end
	return best
end

function select_target(target: Target?)
	if target then
		-- Scroll every ScrollingFrame above it just far enough to bring it into
		-- view. Without this the selection walks happily off the bottom of a
		-- list and the player is left driving something they cannot see.
		local ancestor = target.object.Parent
		while ancestor do
			if ancestor:IsA "ScrollingFrame" then
				const top = target.object.AbsolutePosition.Y - ancestor.AbsolutePosition.Y
				const bottom = top + target.object.AbsoluteSize.Y - ancestor.AbsoluteSize.Y
				const delta = if top < 0 then top else if bottom > 0 then bottom else 0
				ancestor.CanvasPosition += Vector2.new(0, delta)
			end
			ancestor = ancestor.Parent
		end
	end
	GuiService.SelectedObject = if target then target.object else nil
end

-- Is this pad button physically down right now. There is no "is it down" on the
-- action, and the arming rule above needs an answer at the instant a panel
-- opens rather than at the next press.
function down(key: Enum.KeyCode): boolean
	for _, gamepad in UserInputService:GetConnectedGamepads() do
		if UserInputService:IsGamepadButtonDown(gamepad, key) then
			return true
		end
	end
	return false
end

-- The current selection if it is still a valid target of this root, otherwise a
-- fresh one. Keeps the player's place across a redraw; recovers when the widget
-- they were on is destroyed or disabled under them.
function focus(root: GuiObject): Target?
	const target = if GuiService.SelectedObject then targets[GuiService.SelectedObject] else nil
	if target and valid(target, root) then
		return target
	end
	const first = choose(root)
	select_target(first)
	return first
end

function navigate(root: GuiObject, delta: Vector2)
	const from = focus(root)
	if not from then
		return
	end
	-- A stepper eats the stick along its own axis: left and right on a carousel
	-- change the item rather than jumping out of it. The other axis still moves
	-- the focus, which is how the player gets back out.
	if from.cycle and ((from.vertical and delta.Y ~= 0) or (not from.vertical and delta.X ~= 0)) then
		from.cycle(if from.vertical then delta.Y else delta.X)
		return
	end
	const origin = from.object.AbsolutePosition + from.object.AbsoluteSize / 2
	local best: Target? = nil
	local score = math.huge
	for _, target in targets do
		if target == from or not valid(target, root) then
			continue
		end
		const offset = target.object.AbsolutePosition + target.object.AbsoluteSize / 2 - origin
		const along = offset:Dot(delta)
		-- Strictly ahead. A widget level with or behind the current one is not
		-- a candidate for "right" at any distance.
		if along <= 0 then
			continue
		end
		const across = math.abs(offset:Dot(Vector2.new(-delta.Y, delta.X)))
		const distance = along + across * PAD.NAV_AXIS_BIAS
		if distance < score then
			best = target
			score = distance
		end
	end
	if best then
		select_target(best)
	end
end

-- Sinks, so the pad's A and B do not also reach the gameplay bindings
-- underneath while a menu is up.
const context = input.context("ControllerMenu", { enabled = false, sink = true, priority = PAD.NAV_PRIORITY })
const confirm = context:action("Confirm", { PAD.CONFIRM })
const cancel = context:action("Cancel", { PAD.CANCEL })
-- Enabled only while a stepper is focused, so the shoulder buttons stay free
-- for the game everywhere else in a panel.
const previous = context:action("PreviousItem", { keys = { PAD.CAROUSEL_PREVIOUS }, enabled = false })
const next_item = context:action("NextItem", { keys = { PAD.CAROUSEL_NEXT }, enabled = false })
-- One Direction2D action rather than four buttons: a diagonal flick then picks
-- a single neighbour instead of firing a step on each axis. The D-pad is bound
-- into the same action so both report through one path.
const navigation = context:action("Navigate", {
	type = Enum.InputActionType.Direction2D,
	keys = { PAD.MOVE },
	up = Enum.KeyCode.DPadUp,
	down = Enum.KeyCode.DPadDown,
	left = Enum.KeyCode.DPadLeft,
	right = Enum.KeyCode.DPadRight,
})

function activate(key: Enum.KeyCode)
	if not context.instance.Enabled then
		return
	end
	const root = current()
	if not root then
		return
	end
	-- B looks for the panel's CANCEL widget wherever it is; A acts on whatever
	-- is focused. And A on a stepper falls through to the panel's primary
	-- action, because a carousel has no "press" of its own and the player
	-- pressing A on one means "take this".
	local target = if key == KEY.CANCEL then choose(root, key) else focus(root)
	if target and target.cycle then
		target = choose(root, KEY.PRIMARY)
	end
	if not target then
		return
	end
	release()
	held = target
	target.press()
end

function cycle_item(delta: number)
	const root = current()
	if not root or not context.instance.Enabled then
		return
	end
	const target = focus(root)
	if target and target.cycle then
		target.cycle(delta)
	end
end

function update_focus(root: GuiObject)
	const target = focus(root)
	const cycling = target ~= nil and target.cycle ~= nil
	previous.instance.Enabled = cycling
	next_item.instance.Enabled = cycling
end

-- AUTO-REPEAT, hand-rolled, because the action reports a stick position rather
-- than key repeats. A new direction steps immediately and then waits
-- REPEAT_DELAY; holding steps every REPEAT_INTERVAL. Snapped to one axis first,
-- so a stick held diagonally walks a column rather than a staircase.
function update_navigation(value: any)
	const root = current()
	if not root or not context.instance.Enabled then
		return
	end
	const vector = if typeof(value) == "Vector2" then value else Vector2.zero
	const next_direction = if vector.Magnitude < PAD.MENU_DEADZONE
		then Vector2.zero
		else if math.abs(vector.X) > math.abs(vector.Y)
			-- Y is inverted: the stick reports up as positive, screen space has
			-- up as negative.
			then Vector2.new(math.sign(vector.X), 0)
			else Vector2.new(0, -math.sign(vector.Y))
	const now = os.clock()
	if next_direction ~= direction then
		direction = next_direction
		next_step = now + PAD.REPEAT_DELAY
		if direction ~= Vector2.zero then
			navigate(root, direction)
		end
	elseif direction ~= Vector2.zero and now >= next_step then
		next_step = now + PAD.REPEAT_INTERVAL
		navigate(root, direction)
	end
end

navigation.instance.StateChanged:Connect(update_navigation)
previous.instance.Pressed:Connect(function()
	cycle_item(-1)
end)
next_item.instance.Pressed:Connect(function()
	cycle_item(1)
end)

confirm.instance.Pressed:Connect(function()
	if confirm_armed then
		confirm_armed = false
		activate(KEY.PRIMARY)
	end
end)
cancel.instance.Pressed:Connect(function()
	if cancel_armed then
		cancel_armed = false
		activate(KEY.CANCEL)
	end
end)
confirm.instance.Released:Connect(function()
	confirm_armed = true
	release()
end)
cancel.instance.Released:Connect(function()
	cancel_armed = true
	release()
end)
GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
	selected(GuiService.SelectedObject)
	-- Moving the selection ends any hold: a held button whose focus moved away
	-- would otherwise never be told to let go.
	release()
end)

vide.root(function()
	vide.effect(function()
		revision()
		-- Nothing on screen unless the player is actually holding a pad. A
		-- keyboard player who plugged one in last week should not have their
		-- menus quietly driven by it.
		if state.preferred() ~= Enum.PreferredInput.Gamepad or not state.available() then
			context.instance.Enabled = false
			current(nil)
			release()
			return
		end
		local root: GuiObject? = nil
		local newest = -math.huge
		for candidate, stamp in windows do
			if stamp > newest and visible(candidate) then
				root = candidate
				newest = stamp
			end
		end
		confirm_armed = not down(PAD.CONFIRM)
		cancel_armed = not down(PAD.CANCEL)
		current(root)
		context.instance.Enabled = root ~= nil
		if not root then
			return
		end
		-- Roblox's own navigation is turned off for as long as a panel is up,
		-- and put back exactly as it was found -- a game that had deliberately
		-- disabled it keeps that.
		const prior_navigation = GuiService.GuiNavigationEnabled
		const prior_auto = GuiService.AutoSelectGuiEnabled
		GuiService.GuiNavigationEnabled = false
		GuiService.AutoSelectGuiEnabled = false
		vide.cleanup(function()
			release()
			direction = Vector2.zero
			GuiService.GuiNavigationEnabled = prior_navigation
			GuiService.AutoSelectGuiEnabled = prior_auto
			-- Only clear a selection that belonged to the panel going away.
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
				GuiService.SelectedObject = nil
			end
		end)
		-- Per frame, because none of the three things it watches has a signal:
		-- a widget can be destroyed, disabled or hidden under the selection,
		-- and the stick has a position rather than an event.
		vide.cleanup(RunService.RenderStepped:Connect(function()
			update_focus(root)
			if held and not valid(held, root) then
				release()
			end
			update_navigation(navigation.instance:GetState())
		end))
	end)
end)

return table.freeze {
	-- The InputActions themselves, for a hotkey badge that wants to draw the
	-- pad's own glyph for confirm or cancel rather than a keyboard key.
	confirm = confirm.instance,
	cancel = cancel.instance,
	previous = previous.instance,
	next_item = next_item.instance,

	-- Make a widget reachable by the pad. Called from inside a vide scope: the
	-- registration is removed with the scope, so a panel that unmounts takes
	-- its widgets out of the registry without a matching call.
	register = function(
		object: GuiObject,
		enabled: () -> boolean,
		press: () -> (),
		ended: (() -> ())?,
		key: Enum.KeyCode?,
		cycle: ((number) -> ())?,
		vertical: boolean?,
		gamepad_key: Enum.KeyCode?
	)
		const target: Target = {
			object = object,
			enabled = enabled,
			press = press,
			release = ended,
			-- A widget that asked for the pad's confirm or cancel directly is
			-- recorded under the matching kit role, so `activate` finds it the
			-- same way it finds one that asked by keyboard key.
			key = if gamepad_key == PAD.CANCEL
				then KEY.CANCEL
				else if gamepad_key == PAD.CONFIRM then KEY.PRIMARY else key,
			cycle = cycle,
			vertical = vertical,
		}
		targets[object] = target
		object.Selectable = true
		-- An EMPTY highlight. Roblox draws a blue box around the selected
		-- object by default; the kit shows the selection in the widget's own
		-- styling instead, and there is no way to ask for no highlight at all.
		object.SelectionImageObject = vide.create "Frame" { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }
		vide.cleanup(function()
			if held == target then
				release()
			end
			targets[object] = nil
		end)
	end,

	-- Declare a panel as a navigation root while `open` is true. Also called
	-- from inside a vide scope.
	window = function(object: GuiObject, open: () -> boolean)
		local function refresh()
			revision(revision() + 1)
		end
		vide.effect(function()
			if open() then
				order += 1
				windows[object] = order
			else
				windows[object] = nil
			end
			-- Untracked: `refresh` writes `revision`, which the root search
			-- above reads. Tracking it here would make this effect depend on
			-- its own write.
			vide.untrack(refresh)
		end)
		-- Visibility and ancestry are what `visible` reads, and neither is a
		-- vide source, so the search has to be told when they change.
		vide.cleanup(object.AncestryChanged:Connect(refresh))
		vide.cleanup(object:GetPropertyChangedSignal("Visible"):Connect(refresh))
		vide.cleanup(function()
			windows[object] = nil
			refresh()
		end)
	end,

	selected = selected,
	-- Is the pad currently driving a panel. For the HUD hints, which should
	-- show pad glyphs only while the pad is in charge.
	active = function(): boolean
		return current() ~= nil
	end,
}
