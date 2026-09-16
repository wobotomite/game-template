--!nocheck
-- util/texture-baker: tinted, highlighted SurfaceAppearance variants.
-- Run with:
--   lune run tests/texture-baker.spec.luau
--
-- The three modules are a verbatim copy of the standalone texture-baker
-- package, which carries the exhaustive suite for the blend modes and the
-- compositor. This spec proves what only THIS tree can get wrong -- the
-- module loads through the Util mount and its `@self/` requires resolve
-- here -- and then runs one generate end to end against
-- `tests/texture-baker-fake.luau`, a buffer-backed stand-in for the four
-- engine surfaces the baker touches. Pinning a painted pixel and an untouched
-- one means a re-copy whose defaults changed shows up here.

local h = require "./harness"
local env = require "./roblox-env"
local fake = require "./texture-baker-fake"

h.title "texture-baker through the Util mount:"

h.equals(
	"the mount resolves to the entry module",
	env.file_for "ReplicatedStorage.Util.texture-baker",
	"src/util/texture-baker/init.luau"
)

local engine = fake.new()
local W, H = 2, 1
engine.register(
	"rbxassetid://base",
	W,
	H,
	fake.paint(W, H, function()
		return 200, 200, 200, 255
	end)
)
engine.register(
	"rbxassetid://mask",
	W,
	H,
	fake.paint(W, H, function(x)
		return 255, 255, 255, if x == 1 then 255 else 0
	end)
)

-- The baker only touches `game` for AssetService, so the fake stands in for
-- the whole DataModel here; require resolution is the loader's, not game's.
local baker = env.load("ReplicatedStorage.Util.texture-baker", {
	globals = { game = engine.game, Content = engine.Content },
})
h.check("the module loaded and exports create", typeof(baker.create) == "function")
h.check("and the tint entry point", typeof(baker.tint) == "function")

local sa = fake.surface_appearance { ColorMap = "rbxassetid://base" }
local factory = baker.create(sa, { "rbxassetid://mask" }, { "color_map" })
local result = factory:generate()

h.equals("one appearance came out of the engine", #engine.appearances, 1)
h.check("it is the result's", engine.appearances[1] == result.surface_appearance)
local r0, g0, b0 = fake.pixel(result.color.pixels, W, 0, 0)
h.check("the uncovered pixel is the source grey", r0 == 200 and g0 == 200 and b0 == 200, `{r0} {g0} {b0}`)
local r1, g1, b1 = fake.pixel(result.color.pixels, W, 1, 0)
h.check("the covered pixel is the hot-pink default", r1 == 255 and g1 == 105 and b1 == 180, `{r1} {g1} {b1}`)
h.equals("no emission canvas without an emission source", result.emission, nil)

h.done()
