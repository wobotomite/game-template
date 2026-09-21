--!strict
-- The example service test: `src/server/data/award.luau`.
-- Run it with:
--   lune run scripts/run-jest
--
-- WHY THIS MODULE AND NOT A PURER ONE. `award` is the smallest thing in this
-- tree that a Lune spec genuinely cannot reach. It requires the player
-- datastore, and that module calls `game:GetService "DataStoreService"`, probes
-- API access and builds a live lyra store at module scope -- so the require
-- fails before any of `award`'s own arithmetic runs. Jest Roblox runs inside
-- Roblox, where those calls are real, and replaces them. docs/testing-services.md
-- has the rest.
--
-- This file is NOT part of `lune run tests/run` and must not become part of it:
-- see the comment at the top of `scripts/run-jest.luau` for how the two runners
-- stay out of each other's way.

local ReplicatedStorage = game:GetService "ReplicatedStorage"
local ServerScriptService = game:GetService "ServerScriptService"

-- Everything a test uses is required explicitly: Jest Roblox installs no
-- globals at all, so an `it` or an `expect` that is not on this list is simply
-- nil. https://roblox.github.io/jest-roblox/api lists what is here.
local jest_globals = require(ReplicatedStorage.Packages.JestGlobals)

local beforeEach = jest_globals.beforeEach
local describe = jest_globals.describe
local expect = jest_globals.expect
local it = jest_globals.it
local jest = jest_globals.jest

-- THE TWO MODULES THIS FILE REPLACES, and why each has to go.
--
-- `datastore` is the engine half: DataStoreService, the API-access probe, a
-- real lyra player store and the `changedCallbacks` that push into
-- `player-data`. None of that is what `award` is being asked about.
--
-- `server-network` is THE WIRE, and it is the one that matters. Requiring it
-- runs `sendbufs.create_server`, which parents `_SB_RELIABLE`,
-- `_SB_UNRELIABLE` and `_SB_FUNCTION` into ReplicatedStorage with NO dedupe. A
-- second set does not error -- it silently kills the client sync for the whole
-- session, and in Studio it gets SAVED into the place file and kills every
-- session after it too. See the comment at the top of
-- `src/server/net/server-network.luau`. A test must never be the thing that
-- creates them, which is most of the reason this file mocks.
--
-- `jest.mock` takes the module INSTANCE, and it is keyed on that instance
-- alone: `Runtime_private:_shouldMock` sets `local moduleID = moduleName` and
-- never consults which module is doing the requiring. So a mock registered
-- here also intercepts a require made DEEP inside the code under test, which is
-- exactly what is needed -- nothing below requires `server-network` directly.
local datastore_module = ServerScriptService.Server.data.datastore
local server_network_module = ServerScriptService.Server.net["server-network"]
local award_module = ServerScriptService.Server.data.award

-- `ReplicatedStorage.Shared.services.alert` is deliberately left REAL. It is
-- the module that actually reaches the wire, and it reaches it LAZILY --
-- `alert.send_to` requires `server-network` INSIDE the call, not at module
-- scope. Leaving it real is what makes the last test in this file mean
-- something: it proves the interception covers a transitive, deferred require,
-- not just the two requires written above.

-- The stand-in for the player's saved data. The shape is
-- `src/shared/datastore/datastore-template.luau`: `{ currency = { coins = 0 } }`.
local saved: { currency: { [string]: number } }

-- Every `send_alert` payload the code under test pushed at the (mocked) wire.
local alerts: { { message: string, sound: string? } }

-- A Player CANNOT be constructed from a script, so the tests hand `award` a
-- stand-in. That is honest HERE AND ONLY HERE, because nothing on this path
-- indexes the player: `award` passes it straight through to `datastore:update`
-- and `alert.send_to`, and both of those are replaced below. A service that
-- reads `player.UserId`, `player.Character` or anything else off it cannot be
-- tested this way and needs a real session.
local FAKE_PLAYER = (Instance.new "Folder" :: any) :: Player

describe("award", function()
	beforeEach(function()
		saved = { currency = { coins = 25 } }
		alerts = {}

		-- ORDER MATTERS, and this is the shape the upstream docs use.
		-- `resetModules` empties the MODULE registry, so the `require` in each
		-- test below re-runs `award` and it picks the mocks up; it leaves the
		-- MOCK registry alone (`Runtime_private:resetModules` clears
		-- `_moduleRegistry` and `_mockRegistry`, while `_explicitShouldMock`
		-- survives until the file's teardown), so registering after it is safe.
		jest.resetModules()

		jest.mock(datastore_module, function()
			return {
				-- The real one is lyra's: `update(self, player, transform)`
				-- returning a Promise<boolean> that resolves to whether the
				-- transform committed. `award` only FORWARDS that promise, so
				-- this returns the transform's own boolean and the promise is
				-- not part of what this file pins. A service that CHAINED off
				-- the promise would need a real one.
				update = function(_self: any, _player: Player, transform: (any) -> boolean): boolean
					return transform(saved)
				end,
			}
		end)

		jest.mock(server_network_module, function()
			return {
				core = {
					send_alert = {
						fire = function(_self: any, _player: Player, payload: { message: string, sound: string? })
							table.insert(alerts, payload)
						end,
					},
				},
			}
		end)
	end)

	it("adds the reward amount to what the player already holds", function()
		local award = require(award_module)

		expect(award(FAKE_PLAYER, "currency/coins/100")).toBe(true)
		expect(saved.currency.coins).toBe(125)
	end)

	it("treats a currency the player has never held as zero", function()
		saved = { currency = {} }

		local award = require(award_module)
		award(FAKE_PLAYER, "currency/coins/100")

		expect(saved.currency.coins).toBe(100)
	end)

	it("sends the player one alert naming the amount and the currency", function()
		local award = require(award_module)
		award(FAKE_PLAYER, "currency/coins/100")

		expect(#alerts).toBe(1)
		-- `toMatch` takes a LUA STRING PATTERN here rather than a regex
		-- (https://roblox.github.io/jest-roblox/deviations). The line is
		-- `GOT <font color="#ffc800">+ 100 Coins</font>`; these two assertions
		-- are on the parts a player actually reads, so re-dressing the text
		-- does not break them.
		expect(alerts[1].message).toMatch "100"
		expect(alerts[1].message).toMatch "Coins"
	end)

	it("never builds the sendbufs remotes", function()
		local award = require(award_module)
		award(FAKE_PLAYER, "currency/coins/100")

		-- THE POINT OF THE MOCKS, asserted rather than assumed. The moment the
		-- interception stops reaching `alert.send_to`'s deferred require, this
		-- is the line that says so -- before a stray remote set is saved into
		-- somebody's place file.
		for _, name in { "_SB_RELIABLE", "_SB_UNRELIABLE", "_SB_FUNCTION" } do
			expect(ReplicatedStorage:FindFirstChild(name)).toBeNil()
		end
	end)
end)

return nil
