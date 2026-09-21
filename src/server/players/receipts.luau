const MarketplaceService = game:GetService "MarketplaceService"
const Players = game:GetService "Players"
const ReplicatedStorage = game:GetService "ReplicatedStorage"

const products = require(ReplicatedStorage.Shared.records.products)
const commerce = require(ReplicatedStorage.Shared.settings).commerce
const strings = require(ReplicatedStorage.Shared.strings)

-- The economy log directly rather than through `Util.analytics`: the index also
-- pulls in the funnel logger, which binds a remote handler at require time, and
-- a receipt service that cannot be required without the network layer is one
-- whose ledger cannot be checked outside the engine either.
const economy = require(ReplicatedStorage.Util.analytics.__analytics_economy)

const datastore = require(script.Parent.Parent.data.datastore)

-- `MarketplaceService.ProcessReceipt`: the one callback in the engine where
-- getting it slightly wrong costs real money in both directions.
--
-- THE CONTRACT. Roblox hands the server a receipt and keeps handing it over --
-- to this server, to the next one, on the next join, for days -- until some
-- server answers `PurchaseGranted`. Answering `NotProcessedYet` is not a
-- failure: it is "ask me again later", and it is the ONLY correct answer when
-- the grant could not be made durable. Answering `PurchaseGranted` for a grant
-- that was not saved throws the purchase away; answering it twice for the same
-- receipt grants twice.
--
-- Two rules follow from that, and everything in this file is one of them:
--
--   1. GRANT IDEMPOTENTLY. The purchase id goes into a ledger inside the
--      player's own save, in the SAME transaction as the grant, so "was this
--      already granted" is answered by the same write that answers "does this
--      player have the coins". A ledger held in server memory answers the
--      question only for receipts that arrive on the server that granted them,
--      which is the easy half.
--
--   2. SAVE BEFORE YOU SAY YES. An update lives in lyra's session until it is
--      flushed, and a server that dies with it unflushed loses the grant AND
--      the ledger entry. `PurchaseGranted` is returned only after the profile
--      is written.
--
-- WHAT A GAME CHANGES HERE. Nothing, usually. A product's effect is data --
-- `settings.commerce.PRODUCTS[i].grants` -- and the default `credit` below
-- applies it. A product that grants something other than currency registers an
-- `apply` through `set_apply` instead.

-- `(data, product) -> changed`. Runs INSIDE the datastore transaction, so it
-- may be called more than once for one purchase (lyra retries the transform on
-- a conflicting write) and must be a pure function of `data` -- no yielding, no
-- reaching for anything outside the save.
export type Apply = (data: any, product: products.Product) -> boolean

-- Fired after a purchase has been granted AND saved, outside the transaction.
-- Anything that yields, touches the world or talks to the client goes here.
export type OnGranted = (player: Player, product: products.Product) -> ()

local apply: Apply? = nil
local on_granted: OnGranted? = nil

function set_apply(fn: Apply)
	apply = fn
end

function set_on_granted(fn: OnGranted)
	on_granted = fn
end

-- The ledger write. Returns false when this purchase id is already recorded,
-- which is the whole duplicate defence.
--
-- Exported because it is the one piece of arithmetic in this file that a later
-- edit could break silently: a cap applied with `table.remove(ledger)` instead
-- of `table.remove(ledger, 1)` evicts the NEWEST id, so the ledger keeps two
-- hundred ids that no longer matter and forgets the one Roblox is still
-- retrying. `tests/receipts.spec.luau` drives it.
function remember(ledger: { string }, purchase_id: string): boolean
	if table.find(ledger, purchase_id) ~= nil then
		return false
	end
	table.insert(ledger, purchase_id)
	while #ledger > commerce.RECEIPT_LEDGER_MAX do
		table.remove(ledger, 1)
	end
	return true
end

-- The default `apply`: add each `grants` entry to the matching currency.
function credit(data: any, product: products.Product): boolean
	local changed = false
	for currency, amount in product.grants do
		if amount == 0 then
			continue
		end
		const balances = data.currency :: any
		balances[currency] = (balances[currency] or 0) + amount
		changed = true
	end
	return changed
end

export type Verdict = "granted" | "duplicate"

-- Grants `product` to `player` and makes it durable. Returns the verdict, or
-- nil when nothing could be saved -- which the caller must turn into
-- `NotProcessedYet`.
function settle(player: Player, product: products.Product, purchase_id: string): Verdict?
	local verdict: Verdict = "duplicate"
	const ending: { [string]: number } = {}
	const ok, err = pcall(function()
		datastore:updateAsync(player, function(data): boolean
			-- RESET AT THE TOP, not at declaration. lyra may run this transform
			-- again after a conflicting write, and a `verdict` left over from
			-- the abandoned attempt would be reported as this one's answer.
			verdict = "duplicate"
			table.clear(ending)
			if not remember(data.commerce.granted, purchase_id) then
				return false
			end
			const grant = apply or credit
			grant(data, product)
			for currency in product.grants do
				ending[currency] = (data.currency :: any)[currency] or 0
			end
			verdict = "granted"
			-- True even when `grant` changed nothing: the LEDGER changed, and
			-- returning false here would discard it and re-grant on the retry.
			return true
		end)
		datastore:saveAsync(player)
	end)
	if not ok then
		warn(`[receipts] could not bank {player.Name}'s purchase: {tostring(err)}`)
		return nil
	end
	if verdict == "granted" then
		for currency, amount in product.grants do
			if amount > 0 then
				economy.source(player, currency, amount, ending[currency] or 0, "IAP", product.key)
			end
		end
	end
	return verdict
end

function process(receipt: any): Enum.ProductPurchaseDecision
	const player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- The buyer is mid-teleport, or bought from a server they have since
		-- left. Roblox will deliver this again wherever they land.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	const product = products.by_id[receipt.ProductId]
	if product == nil then
		-- A product created on the dashboard and not yet added to
		-- `assets.products`, or one deleted from the data files while it was
		-- still on sale. NOT `PurchaseGranted`: that would quietly pocket the
		-- Robux. Leaving it unprocessed keeps the receipt alive until the data
		-- files catch up, and the warn is how anyone finds out.
		warn(`[receipts] no product matches id {receipt.ProductId}; leaving it unprocessed`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- `tostring`, because a PurchaseId is bigger than a double holds exactly and
	-- two purchases that round together would look like one replay.
	const verdict = settle(player, product, tostring(receipt.PurchaseId))
	if verdict == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- A duplicate is `PurchaseGranted` too: the grant exists, and this is how
	-- Roblox is told to stop re-delivering it. Only the fresh grant gets the
	-- toast and the hook.
	if verdict == "granted" and player.Parent ~= nil then
		-- REQUIRED HERE, not at the top of the file. The alert service reaches
		-- the server's network layer at require time, and granting a purchase
		-- and telling the player about it are separable: the ledger has to work
		-- whether or not there is a wire, and keeping the require inside the one
		-- branch that needs it is also what lets `tests/receipts.spec.luau` load
		-- this module outside the engine. Roblox caches requires, so this costs
		-- one table lookup per purchase.
		const alert = require(ReplicatedStorage.Shared.services.alert)
		alert.send_to(player, strings.fill(strings.commerce.GRANTED, { name = product.name }))
		const hook = on_granted
		if hook then
			task.spawn(hook, player, product)
		end
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

local started = false
function start()
	if started then
		return
	end
	started = true

	-- ONE HANDLER PER SERVER, and assigning a second one silently replaces the
	-- first. That is why this is a `start()` rather than a module-scope
	-- assignment: the boot list in `src/server/init.server.luau` is the single
	-- place that decides who owns the callback.
	MarketplaceService.ProcessReceipt = process
end

return table.freeze {
	start = start,
	set_apply = set_apply,
	set_on_granted = set_on_granted,
	settle = settle,
	remember = remember,
	credit = credit,
}
