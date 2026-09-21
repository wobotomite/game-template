-- A PANEL IN THE WORLD: the same kit widgets, mounted onto a part instead of
-- onto the screen.
--
-- For anything the player walks up to rather than opens -- a vending machine, a
-- terminal on a wall, a scoreboard in a lobby. Given a CollectionService tag
-- and a builder, every tagged part gets its own copy, including parts streamed
-- in later.
--
-- ONE BUILD PER PART, not one shared GUI moved around: two of these are usually
-- on screen at once showing different state, and a SurfaceGui has exactly one
-- Adornee.
--
-- MOUNTED IN PlayerGui, NOT UNDER THE PART. A SurfaceGui parented into the
-- workspace replicates to everyone and is rebuilt by streaming; one in PlayerGui
-- with an Adornee is local, survives the part streaming out, and is the shape
-- Roblox documents.
const CollectionService = game:GetService "CollectionService"
const ReplicatedStorage = game:GetService "ReplicatedStorage"
const Players = game:GetService "Players"
const vide = require(ReplicatedStorage.Packages.vide)
const render_step = require(ReplicatedStorage.Util.events["render-step"])
const SURFACE = require(ReplicatedStorage.Shared.settings).ui.SURFACE

function surface(tag: string, build: () -> Frame): Folder
	const player = Players.LocalPlayer
	const player_gui = if player then player:FindFirstChildOfClass "PlayerGui" else nil
	-- Asserted rather than waited for: this is called from a panel that is
	-- already mounted, so a missing PlayerGui means it was called too early --
	-- which is a wiring mistake to fix, not a race to ride out.
	assert(player_gui, "PlayerGui must exist before mounting a surface panel")
	const folder = Instance.new "Folder"
	folder.Name = "SurfacePanels"
	vide.cleanup(folder)
	const mounted: { [Instance]: () -> () } = {}
	-- ONE range poll for every panel of this tag, at a quarter second rather
	-- than a frame: a distance test does not need a frame, and a panel that
	-- switches off a quarter second late is not something anyone sees.
	const step = render_step(SURFACE.POLL)
	local function remove(part: Instance)
		const dispose = mounted[part]
		if dispose then
			dispose()
			mounted[part] = nil
		end
	end
	local function attach(part: Instance)
		-- Guarded on both counts: a tag can be applied to anything, and the
		-- added signal fires again for a part that is already mounted when the
		-- tag is re-applied.
		if not part:IsA "BasePart" or mounted[part] then
			return
		end
		mounted[part] = vide.mount(function()
			const nearby = vide.source(false)
			vide.cleanup(step:connect(function()
				const character = Players.LocalPlayer.Character
				const root = if character then character:FindFirstChild "HumanoidRootPart" else nil
				nearby(
					root ~= nil
						and root:IsA "BasePart"
						and (root.Position - part.Position).Magnitude <= SURFACE.DISTANCE
				)
			end))
			return vide.create "SurfaceGui" {
				Name = "Surface",
				Adornee = part,
				Face = Enum.NormalId.Front,
				-- Fixed canvas, so the same UI is the same size on a big part
				-- and a small one; the part decides how much wall it covers.
				SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
				CanvasSize = SURFACE.SIZE,
				-- NOT AlwaysOnTop: a panel that drew through the wall in front
				-- of it would be a screen floating in the world.
				AlwaysOnTop = false,
				-- Unlit and over-bright, so the panel reads at night and in a
				-- dark room -- which is exactly where a glowing screen is most
				-- useful.
				LightInfluence = SURFACE.LIGHT,
				Brightness = SURFACE.BRIGHTNESS,
				MaxDistance = SURFACE.DISTANCE,
				-- Disabled out of range as well as capped by MaxDistance: the
				-- cap stops it DRAWING, this stops it laying out and stepping.
				Enabled = nearby,
				Active = true,
				ResetOnSpawn = false,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				build(),
			}
		end, player_gui)
	end
	-- The parts already here, then the ones that arrive. Both, because
	-- streaming means neither set is reliably the whole set.
	for _, part in CollectionService:GetTagged(tag) do
		attach(part)
	end
	vide.cleanup(CollectionService:GetInstanceAddedSignal(tag):Connect(attach))
	vide.cleanup(CollectionService:GetInstanceRemovedSignal(tag):Connect(remove))
	vide.cleanup(function()
		for part in mounted do
			remove(part)
		end
		step:destroy()
	end)
	return folder
end

return surface
