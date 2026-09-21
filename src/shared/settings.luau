-- Every tunable in the game, as data. No functions, no requires, no Instances.
--
-- WHY ONE FILE. A number that lives beside the code that reads it gets tuned by
-- whoever happens to be in that file, against nothing. Here a designer reads one
-- section top to bottom and sees every value that shapes a feature, a balance
-- pass is one diff, and two systems that must agree on a number (a hold time and
-- the bar that draws it) read the SAME constant instead of two that drift.
--
-- THE THREE FILES. `settings` holds numbers and shapes, `assets` holds ids that
-- point at something uploaded (`src/shared/assets.luau`), `strings` holds every
-- word a player reads (`src/shared/strings.luau`). A record that needs all three
-- joins them by key; the products record under `src/shared/records` is the
-- worked example.
--
-- NO TYPE ANNOTATIONS, ON PURPOSE. The type of `settings.commerce.LEDGER_MAX` is
-- inferred from the literal, so a wrong type at a read site is an analyzer error
-- for free. What the analyzer does NOT catch is a misspelled KEY read through an
-- alias (`const S = settings.audio`, then `S.VOLUMEE`): that is `nil` at run
-- time and silent in `scripts/analyze.sh`. After renaming a key, grep the old
-- name and expect zero hits.
--
-- HOW TO READ IT. Alias the section once at require time and index the alias:
--
--   const AUDIO = require(ReplicatedStorage.Shared.settings).audio
--
-- Every comment here says why the value is what it is. A bare number with no
-- reason is a number nobody will dare change.
--
-- FROZEN RECURSIVELY at the bottom, so a consumer cannot tune the game for
-- everyone by writing into a table it was handed.
function deep(t)
	for _, value in t do
		if type(value) == "table" then
			deep(value)
		end
	end
	table.freeze(t)
end

const SETTINGS = {
	-- NETWORK. Remote rate limits and payload ceilings that more than one handler
	-- shares. A limit used by exactly one handler stays beside that handler, where
	-- the reason for it is.
	--
	-- Read by `src/server/net`.
	net = {},

	-- ALERTS. The toast stack: how many are visible at once, how long one lives,
	-- and the keyword colouring `src/shared/services/alert.luau` applies to a
	-- shouted line.
	--
	-- Read by `src/shared/services/alert.luau` and the client alert page.
	alerts = {},

	-- DEBUG. Studio-only commands and the menu that fires them. Nothing in this
	-- section is read in a published server: the remotes that would carry it do not
	-- exist there (`src/shared/network.luau`, the `debug` group).
	--
	-- Read by the debug command script and the debug menu.
	debug = {},

	-- CHARACTER. Rig and ragdoll numbers shared by the server and client halves of
	-- character setup, so a death looks the same from both sides of the wire.
	--
	-- Read by `src/server/players/setup-ragdolls.luau` and its client twin.
	character = {},

	-- COMMERCE. Developer products and game passes as SHAPE: what a product grants,
	-- how many times an ownership check retries. The ids are in `assets`, the names
	-- and descriptions in `strings`; the products record joins them.
	--
	-- Read by the receipt and pass services.
	commerce = {},

	-- BADGES. Retry budget for `BadgeService`, which fails transiently and must not
	-- be hammered. The badge ids themselves are in `assets.badges`.
	--
	-- Read by the badge service.
	badges = {},

	-- LEADERBOARDS. Which saved counters become global boards, how often a board is
	-- read and written, and the OrderedDataStore budgets the worker stays inside.
	--
	-- Read by the leaderboard service.
	leaderboards = {},

	-- DAILY REWARDS. The streak schedule, the length of a "day", the grace window,
	-- and the reminder queue that tells a player a reward is ready.
	--
	-- Read by the daily reward rules and the reminder scheduler.
	daily = {},

	-- VOICE. Names the per-player audio input the server attaches when the project
	-- turns the default voice pipeline off.
	--
	-- Read by the voice service.
	voice = {},

	-- AUDIO. Bus volumes, the cue engine's voice budget and distance culling, and
	-- the named sound profiles cues are played through.
	--
	-- Read by `src/client/audio`.
	audio = {},

	-- BOOT. How long the client waits for data and a character before it stops
	-- waiting, and what the preloader is handed.
	--
	-- Read by `src/client/boot`.
	boot = {},

	-- TRANSITION. The loading cover shown from ReplicatedFirst: its colours, fade
	-- times, and the longest it may stay up before it is removed regardless.
	--
	-- Read through the `TransitionSettings` alias in `default.project.json`, which
	-- maps this same file into ReplicatedFirst so the cover can read it before
	-- ReplicatedStorage has replicated. That is a SECOND ModuleScript instance: the
	-- values are equal, the tables are not the same objects.
	transition = {},

	-- EFFECTS. Defaults for the shared effect primitives under
	-- `src/effects/shared` -- particle bursts, rings, display ghosts.
	--
	-- Read by `src/effects`.
	effects = {},

	-- UI. The widget kit's theme: colours, metrics, text sizes, motion. Every
	-- visual value a widget uses comes from here, so reskinning a game is this
	-- section and `assets.fonts`, not a sweep through the widgets.
	--
	-- Read by `src/client/ui`.
	ui = {
		-- COLOURS. Seven names, and the whole kit reads one of them: no widget
		-- under `src/client/ui/kit` writes a literal colour. A reskin is this
		-- table plus `assets.fonts`, which is the only reason the kit is worth
		-- copying into a second game.
		--
		-- The defaults are a dark console palette: near-black panels, one bright
		-- outline hue that doubles as the "pressed" fill, and text a long way off
		-- pure white so an outline still reads against it.
		COLORS = {
			-- Body text. Not `Color3.new(1, 1, 1)`: pure white against a near
			-- black panel is the one pairing that makes a 1px text outline
			-- invisible, and the outline is what keeps HUD text legible over
			-- the world.
			TEXT = Color3.fromRGB(200, 225, 250),
			-- Secondary text -- captions, unselected labels, key caps. Dimmer
			-- than TEXT by enough to rank at a glance, not so much that it
			-- reads as disabled.
			TEXT_DIM = Color3.fromRGB(155, 181, 205),

			-- Panel fill. Also the text colour of an INVERTED button, where
			-- background and foreground swap, so it has to stay dark enough to
			-- read on top of OUTLINE.
			PANEL_BG = Color3.fromRGB(2, 6, 12),
			-- Button fill at rest, a shade up from the panel it sits on so a
			-- button is findable before it is hovered.
			BUTTON_BG = Color3.fromRGB(5, 16, 32),

			-- Every border, rule and divider, and the fill of a hovered or
			-- held button. One hue doing both jobs is what makes the kit look
			-- like one system.
			OUTLINE = Color3.fromRGB(60, 160, 255),
			-- The selection highlight: the hotbar diamond behind the chosen
			-- slot. Kept separate from OUTLINE so a game can make "chosen"
			-- louder than "bordered" without touching every border.
			ACCENT = Color3.fromRGB(90, 190, 255),
			-- Destructive actions only -- the button that wipes something.
			-- Warm, because every other colour here is cold and the contrast is
			-- the warning.
			DANGER = Color3.fromRGB(255, 80, 70),
		},

		-- METRICS. Sizes in DESIGN pixels: every one is passed through
		-- `util/ui/hooks/px`, which scales it for the viewport, so these are
		-- read at the 1280x832 base resolution and never as final pixels.
		METRICS = {
			-- The icon source grid. `kit/icon` and `kit/lock-icon` snap to an
			-- INTEGER multiple of this, so a 32px sprite drawn at 80px shows as
			-- 64px centred rather than as a blurred 2.5x. Change it only with
			-- the art.
			ICON_NATIVE_SIZE = 32,
			-- Padding from a window's border to its contents.
			INSET = 12,
			-- The single gap between stacked things -- list rows, button
			-- columns, hotbar slots. One number, so nothing in the kit can
			-- disagree with anything else about spacing.
			GAP = 6,
			-- Default label size, and the caption size of every button.
			TEXT = 18,

			-- Button height. Fixed rather than hugging the text, because a
			-- footer row of buttons with different captions must line up.
			ACTION_HEIGHT = 44,
			-- Left and right padding inside a button that hugs its text. Also
			-- the inset a hold-button's fill starts from, so the fill covers
			-- the padding rather than stopping short of it.
			BUTTON_PAD = 10,

			-- The title plate: text size and the height of the plate itself.
			-- The plate straddles the window's top border -- half of
			-- TITLE_HEIGHT is above it -- so the window reserves exactly
			-- TITLE_HEIGHT / 2 of headroom, and these two move together.
			TITLE_TEXT = 22,
			TITLE_HEIGHT = 32,
			-- Window border thickness, in the same design pixels; the border is
			-- drawn inside the frame, so the sheet is inset by it on each side.
			WINDOW_STROKE = 2,
			-- How fast a window wipes open and shut, as an exponential
			-- approach rate (see `util/numbers/approach`): the gap left after a
			-- second is exp(-rate), so 16 is "instant but not a pop".
			WIPE_RATE = 16,

			-- HOTBAR SLOTS. A slot is a fixed box; everything inside it is
			-- positioned off these, and the whole bar is laid out by a list
			-- layout at METRICS.GAP.
			SLOT_WIDTH = 96,
			SLOT_HEIGHT = 124,
			-- The key-cap corner: its box and its text.
			SLOT_KEY_TEXT = 16,
			SLOT_KEY_HEIGHT = 20,
			-- The right-hand badge (a count, a charge, a cooldown). Wide
			-- enough for three digits at SLOT_BADGE_TEXT.
			SLOT_BADGE_WIDTH = 40,
			SLOT_BADGE_TEXT = 16,
			-- The slot's own name label under the icon.
			SLOT_NAME_TEXT = 20,
			-- Padding inside the slot box, so neighbouring slots do not touch
			-- when the bar is full.
			SLOT_INSET = 6,
			-- How far the selected (or hovered) slot's contents rise. Small on
			-- purpose: the lift is a confirmation, not an animation to watch.
			SLOT_LIFT = 4,
			-- Approach rate for the lift and the diamond's turn. High enough
			-- that switching slots feels like a switch and not a slide.
			SLOT_RESPONSE = 18,
			-- The rotated square behind a selected slot. ANGLE is the resting
			-- 45 degrees that makes a square a diamond; TURN is the extra
			-- rotation applied while selected, so selection reads even in
			-- greyscale.
			SLOT_DIAMOND_SIZE = 64,
			SLOT_DIAMOND_ANGLE = 45,
			SLOT_DIAMOND_TURN = -10,
			-- The diamond is a wash behind the icon, never a solid plate: at 0
			-- it hides the icon it is meant to be highlighting.
			SLOT_DIAMOND_TRANSPARENCY = 0.2,
		},

		-- STYLE. The kit's surface treatment -- strokes, transparencies, the
		-- blink -- as opposed to the SIZES in METRICS. Split from METRICS
		-- because a reskin usually wants one and not the other.
		STYLE = {
			-- When an eased value is close enough to its target to be SNAPPED
			-- to it and the per-frame step disconnected. Exponential approach
			-- never arrives (see `util/numbers/approach`), so without a
			-- settle threshold every eased value in the kit holds a
			-- RenderStepped connection forever.
			SETTLED = 0.002,

			-- Border thickness in design pixels, and the two transparencies a
			-- border is drawn at: SOFT at rest, DIM when the control is
			-- disabled. A hovered control passes 0 (fully opaque) explicitly.
			STROKE = 1,
			STROKE_SOFT = 0.35,
			STROKE_DIM = 0.75,
			-- Rules and dividers sit a step fainter than a resting border, so a
			-- divider inside a panel does not compete with the panel's own edge.
			RULE_SOFT = 0.55,
			-- The rule between a window's body and its footer buttons, in design
			-- pixels. Its own key because the window RESERVES this height when
			-- it measures the footer; a divider that draws thicker than the
			-- space reserved for it clips the top button.
			WINDOW_RULE = 1,

			-- Text outline: colour, thickness, and how far it is faded. Darker
			-- than PANEL_BG so the outline reads as a shadow rather than as a
			-- second colour.
			TEXT_OUTLINE = Color3.fromRGB(1, 3, 6),
			TEXT_OUTLINE_PX = 1,
			TEXT_OUTLINE_SOFT = 0.65,
			-- HUD text is drawn over the WORLD rather than over a panel, so it
			-- needs a heavier outline than panel text does. Anything the kit
			-- draws outside a window passes this instead.
			HUD_TEXT_OUTLINE_PX = 2,

			-- Panels are slightly see-through, so a window never fully hides
			-- what the player was looking at. Only slightly: text has to stay
			-- readable over whatever is behind it.
			BG_TRANSPARENCY = 0.15,

			-- Cursor blink half-period, in seconds. 0.53 is the DEC VT100's,
			-- which is where every terminal cursor since got it from.
			BLINK_PERIOD = 0.53,

			-- The hotbar's icon box and the label strip under it. In STYLE
			-- rather than METRICS because they size ART, not layout: swapping
			-- to a denser icon set moves these two and nothing else.
			ICON_SIZE = 80,
			SLOT_LABEL_HEIGHT = 26,
		},

		-- TEXT. Line box arithmetic.
		TEXT = {
			-- Extra height added to a text size to get its line box, so stacked
			-- single-line labels do not touch. A label sized by its FONT rather
			-- than by its box gets clipped descenders at some scales; this is
			-- the leading that prevents it.
			LINE_LEAD = 4,
		},

		-- BUTTON HOTKEYS. The key-cap badge a button draws when it has a
		-- keyboard or gamepad shortcut, and the two keys the kit treats as
		-- MEANINGS rather than as bindings.
		BUTTON_HOTKEY = {
			-- PRIMARY and CANCEL are the kit's two roles. A button declaring
			-- one of these keyboard keys is understood by the gamepad layer as
			-- "this is the confirm button" / "this is the back button" and is
			-- bound to the pad's own confirm/cancel instead. Any other key is
			-- carried through literally.
			PRIMARY = Enum.KeyCode.E,
			CANCEL = Enum.KeyCode.C,
			-- Priority of the InputContext a hotkey badge creates. Above
			-- gameplay bindings, so a panel's E beats the world's E while the
			-- panel is on screen; below the gamepad navigation context, which
			-- has to be able to take the same buttons back.
			PRIORITY = 1000,
			-- The key cap: its square, the gap it leaves between itself and the
			-- button's caption, and its own text size.
			SIZE = 24,
			GAP = 8,
			TEXT_SIZE = 18,
			-- The cap is a faint plate rather than a filled box, so a row of
			-- caps does not out-shout the captions beside them.
			BACKGROUND_ALPHA = 0.15,
		},

		-- HOLD BUTTONS. A button that must be held for `hold` seconds before it
		-- fires. Used for anything destructive, where a misclick is expensive.
		HOLD_BUTTON = {
			-- How fast the fill drains when the player lets go, as a MULTIPLE
			-- of the fill rate: 3 means a released hold empties in a third of
			-- the time it took to fill. Fast enough that letting go reads as a
			-- cancel, slow enough to see that it cancelled.
			DRAIN_RATE = 3,
			-- The fill is a wash over the button, not a replacement for it: the
			-- caption stays readable the whole way across.
			FILL_TRANSPARENCY = 0.35,
			-- Floor on `hold`, in seconds. A zero or negative hold divides by
			-- zero in the fill arithmetic and fires on the frame it is pressed,
			-- which is a plain button with extra steps.
			MIN_HOLD = 0.05,
		},

		-- DIALOGS. A dialog is a window with a fixed width and centred lines.
		DIALOG = {
			-- Narrow on purpose: a dialog is one question, and a wide one
			-- invites paragraphs.
			WIDTH = 380,
		},

		-- MENU BACKDROP. The blur and dim behind an open menu, driven by
		-- `src/client/ui/menu-state`.
		MENU_BACKDROP = {
			-- Blur radius at full menu. Enough that the world stops competing
			-- for attention, not so much that the player loses their place.
			BLUR = 12,
			-- Default brightness offset. NEGATIVE: the world darkens, so light
			-- panel text keeps its contrast. A menu may ask for a darker value
			-- than this, never a lighter one -- `menu-state` takes the MINIMUM
			-- across open menus, so nesting a panel inside another cannot
			-- brighten the backdrop back up.
			BRIGHTNESS = -0.12,
			-- Approach rate for both, so the backdrop arrives with the window
			-- rather than after it. Slower than METRICS.WIPE_RATE, because a
			-- full-screen blur snapping in is a flash.
			FADE_RATE = 14,
		},

		-- SCALE. The floor `util/ui/hooks/px` clamps its scale factor to, set
		-- once at boot by `src/client/ui/app`.
		SCALE = {
			-- 0.75 rather than the hook's own 0.4 default, because this kit's
			-- densest screen is a window full of body text: below about
			-- three quarters, 18px body text on a phone stops being readable.
			-- A game whose densest screen is icons can lower it.
			MINIMUM = 0.75,
		},

		-- SURFACE PANELS. `kit/surface` mounts a UI onto every part carrying a
		-- tag, as a SurfaceGui -- a screen in the world rather than on the HUD.
		SURFACE = {
			-- Canvas size in surface pixels. Fixed rather than derived from the
			-- part, so the same UI is the same size on a big part and a small
			-- one; the part's own size decides how much wall it covers.
			SIZE = Vector2.new(1024, 640),
			-- Studs. Doubles as the SurfaceGui's MaxDistance and as the range
			-- check that enables it, so the panel is never drawn just outside
			-- the distance at which it would be legible.
			DISTANCE = 60,
			-- Unlit (0) and over-bright, so a world panel reads at night and
			-- inside a dark room. A lit panel is invisible exactly where a
			-- glowing screen is most useful.
			LIGHT = 0,
			BRIGHTNESS = 1.5,
			-- Seconds between range checks. A distance test does not need a
			-- frame: at 0.25 s a player walking away sees the panel switch off
			-- a quarter second late, and nobody notices.
			POLL = 0.25,
		},

		-- ALERTS. The toast stack drawn by `src/client/ui/pages/alerts` over the
		-- message atom in `src/shared/services/alert.luau`.
		ALERTS = {
			-- DisplayOrder. Deliberately enormous: a toast is the last thing
			-- the game says before something goes wrong, and it has to survive
			-- a panel that picked an optimistic layer of its own.
			LAYER = 900000,
			TEXT_SIZE = 22,
			-- Toast column width, and the margin it keeps from the screen edge.
			-- The column is CLAMPED to the viewport minus two margins, so a
			-- phone shows a narrower column rather than a clipped one.
			WIDTH = 700,
			MARGIN = 20,
			-- Hard cap on visible toasts. Without it a burst -- a party of four
			-- all earning something at once -- stacks off the top of the screen
			-- and the newest, which is the one that matters, is the one pushed
			-- out of view.
			MAX_VISIBLE = 4,
			-- Seconds a toast lives, and how long its scale-in and fade-out
			-- take. LIFESPAN is measured from the toast appearing, so the fade
			-- starts at LIFESPAN - ANIMATION_TIME and the two end together.
			LIFESPAN = 3,
			ANIMATION_TIME = 0.2,
		},
	},

	-- CONTROLS. Key, gamepad and touch bindings, and the thresholds gesture
	-- recognition uses (how far is a swipe, how long is a hold).
	--
	-- Read by `src/client/input` and the input labels in the widget kit.
	controls = {
		-- GAMEPAD. The two buttons every pad agrees on, plus the numbers the
		-- menu navigator in `src/client/ui` runs on. Gameplay bindings belong
		-- to the game, not to the kit; only the menu layer is here.
		GAMEPAD = {
			-- A confirms and B goes back, on every pad Roblox reports, because
			-- that is the layout the console the player learned on used. The
			-- kit maps a button's keyboard hotkey onto these rather than asking
			-- each button for a pad binding of its own.
			CONFIRM = Enum.KeyCode.ButtonA,
			CANCEL = Enum.KeyCode.ButtonB,
			-- Shoulder buttons step a list or a carousel sideways, leaving the
			-- stick free to move the focus within a page.
			CAROUSEL_PREVIOUS = Enum.KeyCode.ButtonL1,
			CAROUSEL_NEXT = Enum.KeyCode.ButtonR1,
			-- The left stick moves the selection. Read as a whole Vector2
			-- action rather than as four directions, so a diagonal picks one
			-- neighbour instead of firing two steps.
			MOVE = Enum.KeyCode.Thumbstick1,

			-- Stick magnitude a menu step needs. MUCH larger than a gameplay
			-- dead zone (which is about 0.18): moving a cursor is discrete, so
			-- a stick resting a little off centre must not walk the selection,
			-- and the player has to mean it.
			MENU_DEADZONE = 0.6,
			-- Held-stick auto-repeat: the pause before the second step, then
			-- the interval between the rest. The long first delay is what lets
			-- a single flick move exactly one item.
			REPEAT_DELAY = 0.6,
			REPEAT_INTERVAL = 0.3,

			-- How much harder it is to move ACROSS the stick's direction than
			-- along it, when picking the next thing to focus. At 3, a candidate
			-- three times further sideways than a rival loses even if it is
			-- nearer in a straight line -- which is how "press right" lands on
			-- the thing to the right rather than on the nearest thing that
			-- happens to be up and to the right.
			NAV_AXIS_BIAS = 3,
			-- The navigation InputContext's priority, and it sinks. Above every
			-- gameplay context and above a panel's own hotkeys
			-- (`ui.BUTTON_HOTKEY.PRIORITY`), because while a menu is being
			-- driven by a pad, A and B belong to the menu.
			NAV_PRIORITY = 3000,
		},

		-- TOUCH. Sizes for the on-screen buttons in `src/client/input`, and the
		-- thresholds the gesture recogniser there classifies a touch by.
		--
		-- REAL VIEWPORT PIXELS, not design pixels -- these are the one group of
		-- sizes in the file that is NOT scaled through `util/ui/hooks/px` the
		-- way `ui.METRICS` is. A thumb is the same size on every phone, so a
		-- touch target that shrank with the viewport would be hardest to hit on
		-- exactly the smallest screens, and a drift threshold that shrank with
		-- it would call a deliberate drag a tap.
		TOUCH = {
			-- A touch button's square, and the gap between buttons. 54 design
			-- px is about 9 mm on a phone: the smallest square still reliably
			-- hit by a thumb that is also holding the device.
			BUTTON = 54,
			GAP = 8,
			TEXT = 14,
			-- DisplayOrder for the touch layer. Above panels (which sit near
			-- 1000) so a button is never buried, below `ui.ALERTS.LAYER`.
			LAYER = 1250,
			-- Seconds between re-measurements of the Roblox touch controls the
			-- buttons anchor themselves off. Those live in CoreGui and give no
			-- change signal, so the only way to follow them is to look; 0.05 s
			-- is fast enough that a rotation is not seen as a jump.
			POLL = 0.05,

			-- Thumbstick magnitude below which movement reads as zero. Lower
			-- than a gamepad's, because a virtual stick has no spring to return
			-- it and no physical centre to rest at.
			DEADZONE = 0.08,

			-- What separates a TAP from a drag or a hold: a touch that lifts
			-- within TAP_SECONDS, never drifted further than TAP_DRIFT pixels
			-- from where it landed, and did not turn the camera by more than
			-- TAP_CAMERA_DEGREES. The camera test is the one that matters:
			-- on a phone the whole screen is also the look control, so a short
			-- flick to look around is otherwise indistinguishable from a tap on
			-- the world.
			TAP_SECONDS = 0.3,
			TAP_DRIFT = 12,
			TAP_CAMERA_DEGREES = 2,

			-- Fraction of the viewport width at which the right side begins.
			-- Each touch is stamped with the side it STARTED on, so a gesture
			-- beginning under the movement thumbstick is never mistaken for one
			-- aimed at the world.
			RIGHT_SIDE_START = 0.5,

			-- Where each touch button sits, by the id the game registers it
			-- under, as a grid cell COUNTED BACK from the jump button: X steps
			-- left, Y steps up, in whole BUTTON + GAP squares. Measured from
			-- the jump button rather than from the screen corner because that
			-- is the one control Roblox moves for us across phone sizes,
			-- notches and orientations, so the game's buttons follow it.
			--
			-- Empty here: touch buttons are the game's actions, not the kit's.
			-- A button whose id is missing from this table falls back to cell
			-- (0, 0) and warns once, which puts it on top of jump where it
			-- cannot be missed.
			SLOTS = {},
		},
	},
}

deep(SETTINGS)

return SETTINGS
