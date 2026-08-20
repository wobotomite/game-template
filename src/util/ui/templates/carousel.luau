const ReplicatedStorage = game:GetService "ReplicatedStorage"

const clickable = require(ReplicatedStorage.Client.ui.traits.clickable)
const pane = require(ReplicatedStorage.Client.ui.traits.pane)
const sound = require(ReplicatedStorage.Shared.util.sound)
const use_motion = require(ReplicatedStorage.Client.ui.hooks["use-motion"])
const vide = require(ReplicatedStorage.Packages.vide)
const ui_types = require(ReplicatedStorage.Util.ui["ui-types"])

function carousel_item(props: {
	Index: ui_types.UsedAs<number>,
	Padding: ui_types.UsedAs<number>,
	Size: ui_types.UsedAs<UDim2>,
	SelectedIndex: vide.Source<number>,
	MaxDisplay: number?,
	OnClick: () -> (),
} & { [any]: any })
	const options = { frequency = 6, dampingRatio = 1.5 }
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
				sound.client("sound/whoosh", { volume = 0.05 })
			end,
		},
		vide.create "UIScale" {
			Scale = selected_scale,
		},

		unpack(props),
	}
end

return function<T>(props: {
	AnchorPoint: Vector2?,
	Position: ui_types.UsedAs<UDim2>?,
	Size: ui_types.UsedAs<UDim2>?,
	ItemSize: ui_types.UsedAs<UDim2>,
	Padding: ui_types.UsedAs<number>,
	SelectedIndex: number?,
	DisplayCount: number?,
	OnSelectedChanged: ((index: number) -> ())?,
	Provider: (() -> { T }) | { T },
	Consumer: (value: T, index: () -> number) -> Instance,
})
	const selected = vide.source(props.SelectedIndex or 0)
	vide.effect(function(): ()
		selected(math.clamp(#(vide.read(props.Provider) :: any), 0, selected()))
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
		vide.for_values(props.Provider, function(v: T, k: () -> number): Instance?
			return carousel_item {
				MaxDisplay = props.DisplayCount,
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
