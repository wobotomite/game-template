-- THE HOTBAR: a row of slots along the bottom of the screen, one per thing the
-- player can pick.
--
-- Tools, abilities, spells, emotes -- the widget does not care. A caller hands
-- it an array of slots and it draws them; which slot is selected and what
-- picking one does are the game's business, not the kit's.
--
-- NOT A MENU. The hotbar is HUD: it sits over the world, it is read at a
-- glance, and it is why every label in here is drawn with the heavier
-- `HUD_TEXT_OUTLINE_PX` outline rather than the panel one.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const ui_sounds = require(ReplicatedStorage.Client.audio["ui-sounds"])

const input_label = require(script.Parent["input-label"])
const input_state = require(ReplicatedStorage.Client.input["input-state"])
const base = require(script.Parent["__base"])
const text = require(script.Parent.text)
const icon = require(script.Parent.icon)
const px = require(ReplicatedStorage.Util.ui.hooks.px)

const COLORS = base.COLORS
const STYLE = base.STYLE
const METRICS = base.METRICS
const peek = base.peek

type Usable<T> = base.Usable<T>

export type Slot = {
	-- The key cap's text, for a slot with no InputAction to draw from.
	key: string,
	-- Preferred over `key` when present: the engine then draws whatever the
	-- action is really bound to, including a pad glyph. See `kit/input-label`.
	action: InputAction?,
	icon: string?,
	name: Usable<string>,
	-- The small right-hand number: a count, a charge, a cooldown. nil hides it.
	badge: Usable<string?>?,
	badge_color: Usable<Color3>?,
	selected: Usable<boolean>,
	enabled: Usable<boolean>?,
	activated: () -> (),
}

export type HotbarProps = {
	slots: Usable<{ Slot }>,

	Position: Usable<UDim2>?,
	AnchorPoint: Vector2?,
	Visible: Usable<boolean>?,
	ZIndex: number?,
}

-- `slot` is a function rather than a value because the bar is built with
-- `vide.indexes`: the slot AT an index changes without the row being rebuilt,
-- so everything inside reads through the function.
function slot_view(slot: () -> Slot, index: number): Frame
	local function enabled(): boolean
		return base.is_enabled(slot().enabled)
	end
	-- A disabled slot cannot be the selected one. Otherwise a slot that goes
	-- unavailable while chosen keeps its highlight while refusing to be used.
	local function selected(): boolean
		return enabled() and peek(slot().selected) == true
	end
	local function badge(): string?
		return peek(slot().badge)
	end

	const hovering = vide.source(false)
	-- The slot's contents rise a few pixels when it is chosen or hovered. Small
	-- and fast on purpose: it is a confirmation that the pick landed, not an
	-- animation to watch.
	const lift = base.eased(function(): number
		return if selected() or hovering() then METRICS.SLOT_LIFT else 0
	end, METRICS.SLOT_RESPONSE)
	-- And the diamond behind it turns. Rotation as well as colour, so the
	-- selected slot is still obvious in greyscale or to a colourblind player.
	const rotation = base.eased(function(): number
		return METRICS.SLOT_DIAMOND_ANGLE + if selected() then METRICS.SLOT_DIAMOND_TURN else 0
	end, METRICS.SLOT_RESPONSE)
	return vide.create "Frame" {
		Name = `Slot{index}`,
		-- A disabled slot is not drawn at all, so the bar closes up rather than
		-- leaving a hole where something the player cannot use used to be.
		Visible = enabled,
		Size = px.offset(METRICS.SLOT_WIDTH, METRICS.SLOT_HEIGHT),
		LayoutOrder = index,
		BorderSizePixel = 0,
		BackgroundTransparency = 1,

		vide.create "UIPadding" {
			PaddingLeft = px.udim(0, METRICS.SLOT_INSET),
			PaddingRight = px.udim(0, METRICS.SLOT_INSET),
			PaddingTop = px.udim(0, METRICS.SLOT_INSET),
			PaddingBottom = px.udim(0, METRICS.SLOT_INSET),
		},

		vide.create "Frame" {
			Name = "Diamond",
			Size = px.offset(METRICS.SLOT_DIAMOND_SIZE, METRICS.SLOT_DIAMOND_SIZE),
			AnchorPoint = Vector2.new(0.5, 0.5),
			-- Centred on the ICON, not on the slot: the label strip under the
			-- icon is part of the slot's height, so the visual centre is half a
			-- label plus a gap above the geometric one.
			Position = function(): UDim2
				return UDim2.new(0.5, 0, 0.5, -px((STYLE.SLOT_LABEL_HEIGHT + METRICS.GAP) / 2 + lift())())
			end,
			Rotation = rotation,
			BorderSizePixel = 0,
			BackgroundColor3 = function(): Color3
				return if selected() then COLORS.ACCENT else COLORS.PANEL_BG
			end,
			BackgroundTransparency = METRICS.SLOT_DIAMOND_TRANSPARENCY,
			-- Behind everything else in the slot: it is a wash under the icon.
			ZIndex = 0,
		},

		-- The engine's own key cap when the slot has an action, so the hint
		-- follows a rebind and shows pad glyphs. `show` rather than a Visible
		-- flag, because the label is built FROM the action.
		vide.show(function(): boolean
			return slot().action ~= nil
		end, function()
			-- Captured once as the fallback: the reactive read below can return
			-- nil for a frame while the slots array is being swapped, and
			-- `input-label` has to have an action at all times.
			const current = slot().action :: InputAction
			const label = input_label(function(): InputAction
				return slot().action or current
			end, COLORS.TEXT_DIM)
			vide.apply(label) {
				Position = function(): UDim2
					return UDim2.fromOffset(0, -px(lift())())
				end,
				-- No key cap on a phone: there is no key to press.
				Visible = function(): boolean
					return input_state.preferred() ~= Enum.PreferredInput.Touch
				end,
			}
			return label
		end),

		-- The plain-text cap, for a slot with no action to draw from.
		text {
			Visible = function(): boolean
				return slot().action == nil
			end,
			StrokeThickness = px(STYLE.HUD_TEXT_OUTLINE_PX),
			Size = px.offset(METRICS.SLOT_KEY_HEIGHT, METRICS.SLOT_KEY_HEIGHT),
			Position = function(): UDim2
				return UDim2.fromOffset(0, -px(lift())())
			end,
			ZIndex = 2,
			Text = function(): string
				return slot().key
			end,
			TextSize = px(METRICS.SLOT_KEY_TEXT),
			TextXAlignment = Enum.TextXAlignment.Left,
			dim = true,
		},

		vide.show(function(): boolean
			return slot().icon ~= nil
		end, function()
			return icon(slot().icon :: string, {
				Size = px.offset(STYLE.ICON_SIZE, STYLE.ICON_SIZE),
				Position = function(): UDim2
					return UDim2.new(0.5, 0, 0.5, -px((STYLE.SLOT_LABEL_HEIGHT + METRICS.GAP) / 2 + lift())())
				end,
				AnchorPoint = Vector2.new(0.5, 0.5),
			})
		end),

		text {
			StrokeThickness = px(STYLE.HUD_TEXT_OUTLINE_PX),
			Text = function(): string
				return peek(slot().name) or ""
			end,
			Size = px.udim2(1, 0, 0, STYLE.SLOT_LABEL_HEIGHT),
			-- The mirror of the diamond's offset: the label sits below the icon
			-- box by half of each, and moves the opposite way as the slot lifts.
			Position = function(): UDim2
				return UDim2.new(
					0.5,
					0,
					0.5,
					px((STYLE.ICON_SIZE - STYLE.SLOT_LABEL_HEIGHT + METRICS.GAP) / 2 - lift())()
				)
			end,
			AnchorPoint = Vector2.new(0.5, 0),
			ZIndex = 2,
			TextSize = px(METRICS.SLOT_NAME_TEXT),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			-- Only the selected slot gets full-strength text, so the bar reads
			-- as one chosen thing among several rather than as a row of equals.
			TextColor3 = function(): Color3
				if not enabled() then
					return COLORS.TEXT_DIM
				end
				return if selected() then COLORS.TEXT else COLORS.TEXT_DIM
			end,
		},

		text {
			StrokeThickness = px(STYLE.HUD_TEXT_OUTLINE_PX),
			Size = px.offset(METRICS.SLOT_BADGE_WIDTH, METRICS.SLOT_KEY_HEIGHT),
			Position = function(): UDim2
				return UDim2.new(1, 0, 0, -px(lift())())
			end,
			AnchorPoint = Vector2.new(1, 0),
			ZIndex = 2,
			Text = function(): string
				return badge() or ""
			end,
			TextSize = px(METRICS.SLOT_BADGE_TEXT),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = function(): Color3
				return peek(slot().badge_color) or COLORS.TEXT
			end,
			Visible = function(): boolean
				return badge() ~= nil
			end,
		},

		-- ONE transparent button over the whole slot, above everything. The
		-- alternative -- making the icon or the label clickable -- leaves dead
		-- gaps between them that the player reads as a missed click.
		vide.create "TextButton" {
			Name = "Pick",
			MouseEnter = function()
				if not hovering() and enabled() then
					ui_sounds.hover()
				end
				hovering(true)
			end,
			MouseLeave = function()
				hovering(false)
			end,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 3,
			Interactable = function(): boolean
				return enabled()
			end,
			Activated = function()
				if enabled() then
					slot().activated()
				end
			end,
		},
	}
end

function hotbar(props: HotbarProps): Frame
	const slots: () -> { Slot } = if type(props.slots) == "function"
		then props.slots :: () -> { Slot }
		else function(): { Slot }
			return props.slots :: { Slot }
		end

	return vide.create "Frame" {
		Name = "Hotbar",
		-- Hugs its slots, so the bar is centred on the screen whatever number
		-- of slots the game has.
		Size = UDim2.fromScale(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = props.Position or px.udim2(0.5, 0, 1, -METRICS.INSET),
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Visible = props.Visible,
		ZIndex = props.ZIndex,

		vide.create "UIListLayout" {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			-- Bottom aligned, so a lifted slot rises out of the row rather than
			-- pushing the row down.
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = px.udim(0, METRICS.GAP),
		},

		-- `indexes`, not `values`: the slot at position 3 is position 3's slot
		-- whatever object is in it, so swapping a tool updates the existing
		-- view instead of destroying and rebuilding it -- which would restart
		-- the lift animation every time the array changed.
		vide.indexes(slots, function(slot, index)
			return slot_view(slot, index)
		end),
	}
end

return hotbar
