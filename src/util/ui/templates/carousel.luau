const ReplicatedStorage = game:GetService "ReplicatedStorage"

-- These four requires pointed at ReplicatedStorage.Client.ui.traits /
-- Shared.util for a long time -- paths that exist in no project built from
-- this template, so requiring this module threw at the first line of any game
-- that reached for it. The templates and hooks live under Util.ui.
const clickable = require(ReplicatedStorage.Util.ui.templates.clickable)
const pane = require(ReplicatedStorage.Util.ui.templates.pane)
const use_motion = require(ReplicatedStorage.Util.ui.hooks["use-motion"])
const vide = require(ReplicatedStorage.Packages.vide)
const ui_types = require(ReplicatedStorage.Util.ui["ui-types"])

function carousel_item(props: {
	Index: ui_types.UsedAs<number>,
	Padding: ui_types.UsedAs<number>,
	Size: ui_types.UsedAs<UDim2>,
	SelectedIndex: vide.Source<number>,
	MaxDisplay: number?,
	OnClick: () -> (),
	OnClickSound: (() -> ())?,
} & { [any]: any })
	-- The key is `damping`. ripple 0.6 reads no `dampingRatio`, and an unknown
	-- option key is ignored without a word: under the old spelling this ran
	-- critically damped (1) for as long as it read 1.5.
	const options = { frequency = 6, damping = 1.5 }
	const index_pos, index_pos_motion = use_motion(vide.read(props.Index) - props.SelectedIndex())
	const selected_scale, selected_scale_motion =
		use_motion(if props.SelectedIndex() == vide.read(props.Index) then 1 else 0.9)

	local initial_run = true
	vide.effect(function()
		const index = vide.read(props.Index)
		local offset = index - props.SelectedIndex()
		if props.MaxDisplay and math.abs(offset) > props.MaxDisplay and not initial_run then
			initial_run = false
			return
		end
		selected_scale_motion:spring(if props.SelectedIndex() == index then 1 else 0.9, options)
		index_pos_motion:spring(offset, options)
	end)

	return pane {
		ZIndex = if props.Selected then 999 else props.Index,
		AnchorPoint = Vector2.one / 2,
		Size = props.Size,
		Position = function()
			const absolute_width = vide.read(props.Size).X.Offset
			const position = index_pos() * (absolute_width + vide.read(props.Padding))
			return UDim2.new(0.5, position, 0.5, 0)
		end,

		clickable {
			OnClick = function()
				props.OnClick()
				-- The click cue is INJECTED rather than required. This module
				-- used to reach into a `Shared.util.sound` that no project has,
				-- which is the whole reason it never loaded; a template has no
				-- business knowing a game's sound record or its playback
				-- helper.
				const cue = props.OnClickSound
				if cue then
					cue()
				end
			end,
		},
		vide.create "UIScale" {
			Scale = selected_scale,
		},

		unpack(props),
	}
end

return function<T>(
	props: {
		AnchorPoint: Vector2?,
		Position: ui_types.UsedAs<UDim2>?,
		Size: ui_types.UsedAs<UDim2>?,
		ItemSize: ui_types.UsedAs<UDim2>,
		Padding: ui_types.UsedAs<number>,
		SelectedIndex: number?,
		DisplayCount: number?,
		OnSelectedChanged: ((index: number) -> ())?,
		-- Played on every item click. Wire your game's own cue in here.
		OnClickSound: (() -> ())?,
		Provider: (() -> { T }) | { T },
		Consumer: (value: T, index: () -> number) -> Instance,
	}
)
	const items: () -> { T } = if type(props.Provider) == "function"
		then props.Provider :: () -> { T }
		else function()
			return props.Provider :: { T }
		end

	const selected = vide.source(props.SelectedIndex or 0)
	-- ARGUMENT ORDER: the VALUE being clamped is `selected()`, and the bounds are
	-- 0 and the item count. It used to read `math.clamp(#items(), 0, selected())`,
	-- which clamps the COUNT into the range [0, selected] -- so it wrote the item
	-- count into `selected` whenever the list was shorter than the current index,
	-- and clamped the count DOWN to the index otherwise. Either way the selection
	-- was being assigned a list length. With an empty provider it pinned the
	-- selection at 0 (which looked correct and is why this survived), and with a
	-- populated one it jumped the carousel to a position nobody asked for every
	-- time the list changed size.
	vide.effect(function(): ()
		selected(math.clamp(selected(), 0, #items()))
	end)
	vide.effect(function()
		if props.OnSelectedChanged then
			props.OnSelectedChanged(selected())
		end
	end)

	return pane {
		Name = "Carousel",
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		-- vide.for_values does not exist in vide 0.4 -- the iterator is
		-- `vide.values`, and it takes a SOURCE, so a provider handed in as a
		-- plain array has to be wrapped. Both halves of this were wrong, and
		-- both only ever showed up at the moment a carousel was first rendered.
		vide.values(items, function(v: T, k: () -> number): Instance?
			return carousel_item {
				MaxDisplay = props.DisplayCount,
				OnClickSound = props.OnClickSound,
				Padding = props.Padding,
				Index = k,
				Size = props.ItemSize,
				SelectedIndex = selected,
				OnClick = function()
					selected(k())
				end,
				vide.create "UIFlexItem" {
					FlexMode = Enum.UIFlexMode.Fill,
				},
				props.Consumer(v, k),
			}
		end),
	}
end
