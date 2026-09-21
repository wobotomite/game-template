--!nocheck
-- server/players/receipts: the purchase-id ledger.
-- Run with:
--   lune run tests/receipts.spec.luau
--
-- WHY THIS ONE FILE HAS A SPEC AND THE OTHER SERVICES DO NOT. Every other way
-- this template can be wrong shows up as something visibly missing. This one
-- shows up as REAL MONEY, in either direction, and quietly: a ledger that has
-- stopped catching replays grants the same purchase again every time Roblox
-- redelivers it, and a ledger whose cap evicts the wrong end forgets the ids
-- that are still in flight while keeping two hundred that are not. Neither
-- prints anything. Neither is visible in a playtest, because a playtest buys a
-- product once and it works.
--
-- WHAT IS COVERED: the replay, the cap's eviction order, and the rule that a
-- grant which could not be saved is not reported as granted.
--
-- WHAT IS NOT: `process` itself. It answers in `Enum.ProductPurchaseDecision`
-- values, and the stubbed Enum here hands back a fresh table per index, so
-- `got == Enum.ProductPurchaseDecision.PurchaseGranted` is false even when the
-- code is right -- an assertion that could only ever fail. That is why the
-- decision is made by `settle`, which answers in strings, and why `process` is
-- the thin mapping from one to the other.

local h = require "./harness"
local env = require "./roblox-env"

h.title "receipts:"

-- ============================== the fake store =============================

-- Stands in for lyra. Only the two methods the receipt service calls are real:
-- a transaction that can be discarded by returning false, and a flush that can
-- be made to fail.
local live: { [any]: any } = {}
local saved: { [any]: any } = {}
local save_fails = false

local function clone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for key, inner in value do
		out[key] = clone(inner)
	end
	return out
end

local store = {}

-- Transform runs against a COPY, and its result is kept only if the transform
-- says it changed something -- which is lyra's contract, and the half of it
-- this file depends on.
function store:updateAsync(player: any, transform: (any) -> boolean): boolean
	local draft = clone(live[player])
	local changed = transform(draft)
	if changed then
		live[player] = draft
	end
	return changed
end

function store:saveAsync(player: any)
	if save_fails then
		error "datastore unavailable"
	end
	saved[player] = clone(live[player])
end

local fake_lyra = {
	createPlayerStore = function(): any
		return store
	end,
	-- `src/server/data/datastore/migrations.luau` builds its steps at require
	-- time, so the stand-in needs this even though no migration runs here.
	MigrationStep = {
		addFields = function(id: string, fields: any): any
			return { id = id, fields = fields }
		end,
	},
}

-- greentea builds the save's runtime type, and cannot be required outside the
-- engine. Nothing here exercises the schema -- the fake store never validates --
-- so a stand-in that answers the shape-building calls is enough.
local fake_greentea = {
	build = function(inner: any): any
		return {
			matches = function(): (boolean, nil)
				return true, nil
			end,
		}
	end,
	struct = function(fields: any): any
		return fields
	end,
	array = function(of: any): any
		return { of }
	end,
	number = function(): any
		return "number"
	end,
	string = function(): any
		return "string"
	end,
	boolean = function(): any
		return "boolean"
	end,
}

-- charm-sync replicates the save to its owner's client. The datastore module
-- publishes through it, and it cannot load outside the engine; nothing about a
-- receipt depends on replication, so these are no-ops.
local fake_charm_sync = {
	client = { addSignals = function() end },
	server = {
		addSignalsToClient = function() end,
		removeClient = function() end,
	},
}

local receipts = env.load("ServerScriptService.Server.players.receipts", {
	realm = "server",
	packages = { lyra = fake_lyra, greentea = fake_greentea, ["charm-sync"] = fake_charm_sync },
})
local products = env.load "ReplicatedStorage.Shared.records.products"
local commerce = env.load("ReplicatedStorage.Shared.settings").commerce

local product = products.by_key.COINS_SMALL
h.check("the example product grants a currency", (product.grants.coins or 0) > 0)

-- ============================= the replay =================================

do
	local ledger = {}
	h.check("a new purchase id is recorded", receipts.remember(ledger, "a"))
	h.equals("and lands in the ledger", #ledger, 1)

	-- THE CASE THIS FILE EXISTS FOR. Roblox re-delivers a receipt until a
	-- server answers PurchaseGranted, and the answer can be lost on the way
	-- back, so the SAME purchase id arriving twice is the normal case rather
	-- than the strange one.
	h.check("the same id a second time is refused", not receipts.remember(ledger, "a"))
	h.equals("and does not grow the ledger", #ledger, 1)

	h.check("a different id is still recorded", receipts.remember(ledger, "b"))
	h.equals("ledger holds both", #ledger, 2)
end

-- ============================ the cap =====================================

do
	local ledger = {}
	local overflow = 5
	for index = 1, commerce.RECEIPT_LEDGER_MAX + overflow do
		receipts.remember(ledger, `id-{index}`)
	end

	h.equals("the ledger stops at its cap", #ledger, commerce.RECEIPT_LEDGER_MAX)

	-- THE ORDER IS THE POINT. Eviction has to take the OLDEST id, because that
	-- is the one Roblox stopped retrying days ago. Evicting the newest instead
	-- leaves the ledger full of ids nobody will ever present again while
	-- forgetting the one being presented right now -- and the only symptom is a
	-- player who is occasionally granted a purchase twice.
	h.equals("the oldest ids are the ones dropped", ledger[1], `id-{overflow + 1}`)
	h.equals("and the newest is still there", ledger[#ledger], `id-{commerce.RECEIPT_LEDGER_MAX + overflow}`)

	h.check("an evicted id is no longer recognised", receipts.remember(ledger, "id-1"))
end

-- ========================== granting, for real ============================

local player = { Name = "tester", UserId = 7, Parent = nil }

local function fresh()
	live[player] = { currency = { coins = 0 }, commerce = { granted = {} } }
	saved[player] = nil
	save_fails = false
end

do
	fresh()
	local verdict = receipts.settle(player, product, "purchase-1")
	h.equals("a first receipt is granted", verdict, "granted")
	h.equals("the currency arrives", live[player].currency.coins, product.grants.coins)
	h.equals("and the purchase id was banked", #saved[player].commerce.granted, 1)

	-- The redelivery. Same purchase, same server, minutes later.
	local again = receipts.settle(player, product, "purchase-1")
	h.equals("the redelivery is a duplicate", again, "duplicate")
	h.equals("and grants nothing further", live[player].currency.coins, product.grants.coins)

	-- A DIFFERENT purchase of the SAME product is a second sale, not a replay.
	local second = receipts.settle(player, product, "purchase-2")
	h.equals("a new purchase id grants again", second, "granted")
	h.equals("and the currency adds up", live[player].currency.coins, product.grants.coins * 2)
end

-- =========================== the failed save ==============================

do
	fresh()
	save_fails = true

	local verdict = receipts.settle(player, product, "purchase-3")
	-- nil is what `process` turns into NotProcessedYet, which asks Roblox to
	-- deliver the receipt again. Answering PurchaseGranted here would throw the
	-- purchase away the moment this server died.
	h.equals("a grant that could not be saved reports nothing", verdict, nil)
	h.equals("and nothing durable was written", saved[player], nil)
end

h.done()
