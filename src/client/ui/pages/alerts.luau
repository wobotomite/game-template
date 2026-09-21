-- THE TOAST STACK: the last thing the game says to the player before it gives
-- up on saying it any other way.
--
-- A column at the bottom of the screen fed by the atom in
-- `src/shared/services/alert.luau`. This page reads that atom and nothing else
-- from the service: `alert.client` is the whole API for putting a line up, from
-- either realm, and a page that reached further would make the alert service a
-- client dependency.
--
-- DELIBERATELY ANONYMOUS. A toast says what happened, never who it happened to.
-- Attaching a player's name or headshot here would couple the last-resort
-- message layer to whatever the game happens to know about identity, and that
-- knowledge arrives late -- which is exactly when a toast is most likely to be
-- the thing telling you it did not.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const vide = require(ReplicatedStorage.Packages.vide)
const alert = require(ReplicatedStorage.Shared.services.alert)
const kit = require(script.Parent.Parent.kit)
const hud_inset = require(script.Parent.Parent["hud-inset"])
const px = require(ReplicatedStorage.Util.ui.hooks.px)
const use_atom = require(ReplicatedStorage.Util.ui.hooks["use-atom"])
const ALERTS = require(ReplicatedStorage.Shared.settings).ui.ALERTS

-- One toast: scales in, sits, fades out, then asks to be removed.
--
-- THE TWO TIMERS ARE CANCELLED ON CLEANUP. A toast is destroyed early whenever
-- the cap pushes it out, and a `task.delay` outlives the instance it was
-- written for: the fade would write to a source nothing is reading, and
-- `remove` would run against a list the toast is no longer in and delete a
-- LATER toast that had reused nothing but the closure. Neither errors, which is
-- why it is worth cancelling rather than guarding.
local function alert_label(info: alert.alert_type, order: number, remove: () -> ()): TextLabel
	const visible = vide.source(0)
	const scale = vide.spring(visible, ALERTS.ANIMATION_TIME, 0.7)

	visible(1)
	const fade_thread = task.delay(ALERTS.LIFESPAN - ALERTS.ANIMATION_TIME, function()
		visible(0)
	end)
	const remove_thread = task.delay(ALERTS.LIFESPAN, remove)
	vide.cleanup(function()
		for _, thread in { fade_thread, remove_thread } do
			if coroutine.status(thread) == "suspended" then
				task.cancel(thread)
			end
		end
	end)

	return kit.text {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = info.message,
		-- RichText, because a service that colours a keyword in a shouted line
		-- has nowhere else to put the markup.
		RichText = true,
		TextSize = px(ALERTS.TEXT_SIZE),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = order,
		-- The spring overshoots past 1 on the way in; the fade must not go
		-- negative when it does.
		Transparency = function(): number
			return math.clamp(1 - scale(), 0, 1)
		end,

		vide.create "UIScale" {
			Scale = scale,
		},
	}
end

return function(): Frame
	const alerts = vide.source({} :: { [number]: alert.alert_type })
	local next_id = 0
	const viewport = vide.source(Vector2.zero)
	const current_alert = use_atom(alert.alert_atom)

	-- UNTRACKED WRITE. This effect depends on the atom and on nothing else --
	-- but it reads `alerts` to append to it and writes it straight back, and a
	-- tracked read of a source the same effect writes is a loop that re-runs
	-- itself forever. `untrack` is what says "read this for its value, not as a
	-- dependency".
	vide.effect(function()
		const atm = current_alert()
		if atm == nil then
			return
		end

		next_id += 1
		const id = next_id

		vide.untrack(function()
			const new = table.clone(alerts())
			new[id] = atm
			-- THE CAP DROPS THE OLDEST, not the newest. Ids only ever go up, so
			-- anything more than MAX_VISIBLE behind the one just added has been
			-- on screen longest. Without this a burst -- a party all earning
			-- something at once -- stacks off the top of the screen and the
			-- newest toast, the one that matters, is the one pushed out of view.
			for existing in new do
				if existing <= id - ALERTS.MAX_VISIBLE then
					new[existing] = nil
				end
			end
			alerts(new)
		end)
	end)

	const frame = vide.create "Frame" {
		Name = "Toasts",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,

		vide.create "Frame" {
			-- CLAMPED TO THE VIEWPORT, not just set to WIDTH: on a phone the
			-- column is narrower than the design width, and a fixed one would
			-- run off both edges rather than wrapping.
			Size = function(): UDim2
				const room = math.max(0, viewport().X - px(ALERTS.MARGIN * 2)())
				return UDim2.fromOffset(math.min(px(ALERTS.WIDTH)(), room), 0)
			end,
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,

			-- Lifted clear of whatever the game has anchored to the bottom edge
			-- -- a hotbar, a prompt -- or the margin, whichever is further up.
			-- A toast that lands behind the hotbar is a toast nobody reads.
			vide.create "UIPadding" {
				PaddingBottom = function(): UDim
					return UDim.new(0, px(math.max(ALERTS.MARGIN, hud_inset.bottom()))())
				end,
			},

			vide.create "UIListLayout" {
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = px.udim(0, kit.METRICS.GAP),
			},

			-- `indexes` and not `values`: the key IS the toast's identity here,
			-- so a toast keeps its instance -- and its running fade -- while the
			-- ones around it come and go.
			vide.indexes(alerts, function(value, id)
				return alert_label(value(), id, function()
					const res = table.clone(alerts())
					res[id] = nil
					alerts(res)
				end)
			end),
		},
	}
	-- Read once and then on change: the first value is needed before any
	-- property changes, and there is no reactive source for AbsoluteSize.
	viewport(frame.AbsoluteSize)
	vide.cleanup(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		viewport(frame.AbsoluteSize)
	end))
	return frame
end
