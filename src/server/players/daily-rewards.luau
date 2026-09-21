const ReplicatedStorage = game:GetService "ReplicatedStorage"
const ServerScriptService = game:GetService "ServerScriptService"

const strings = require(ReplicatedStorage.Shared.strings)
const rules = require(ReplicatedStorage.Shared.economy["daily-rewards"])
const S = require(ReplicatedStorage.Shared.settings).daily

-- The economy log directly rather than through `Util.analytics`, for the same
-- reason as `receipts.luau`: the index also pulls in the funnel logger, which
-- binds a remote handler at require time.
const economy = require(ReplicatedStorage.Util.analytics.__analytics_economy)

const datastore = require(script.Parent.Parent.data.datastore)
const reminders = require(script.Parent["daily-reminders"])

const T = strings.daily

-- Claiming a daily reward: the one write, and the four things that happen after
-- it. The RULES -- which day, whether it is claimable, what it pays -- are in
-- `src/shared/economy/daily-rewards.luau` and nothing here re-decides them.
--
-- THE CLAIM IS DECIDED INSIDE THE TRANSACTION, not before it. "Have they
-- claimed today" and "credit them" have to be the same write, or two claims
-- arriving together (two servers, or one client sending twice) both read "not
-- claimed yet" and both pay. lyra may run the transform more than once, so it
-- resets its outputs at the top and touches nothing outside `data`.
--
-- WHAT A GAME CHANGES HERE. Nothing, usually: the schedule is
-- `settings.daily.SCHEDULE` and each entry credits the currencies it names. A
-- game that wants the rewards locked behind something -- a tutorial, a level,
-- an event -- registers a `set_gate` instead of editing this file.

-- `(data) -> allowed`. Runs INSIDE the transaction, so it must be a pure
-- function of the save: no yielding, no reaching for the player or the world,
-- and safe to run twice. With no gate registered the rewards are open to
-- everyone, which is what a template should do.
export type Gate = (data: any) -> boolean

export type Verdict = "rewarded" | "claimed" | "locked"

local gate: Gate? = nil

function set_gate(fn: Gate)
	gate = fn
end

-- Claims today's reward for `player`, if there is one. Never raises: every
-- outcome, including the failure, ends in an alert saying which it was.
function claim(player: Player)
	const now = os.time()
	const today = rules.day_of(now)

	local verdict: Verdict = "locked"
	local day = 0
	const paid: { [string]: number } = {}
	const ending: { [string]: number } = {}

	datastore
		:update(player, function(data): boolean
			-- RESET AT THE TOP, not at declaration: an abandoned attempt's
			-- numbers would otherwise be reported as this one's.
			verdict = "locked"
			day = 0
			table.clear(paid)
			table.clear(ending)

			const allowed = gate
			if allowed and not allowed(data) then
				return false
			end
			if rules.claimed(data.daily, today) then
				verdict = "claimed"
				return false
			end

			day = rules.next_day(data.daily, today)
			const balances = data.currency :: any
			for currency, amount in rules.reward(day) do
				if amount == 0 then
					continue
				end
				balances[currency] = (balances[currency] or 0) + amount
				paid[currency] = amount
				ending[currency] = balances[currency]
			end

			data.daily.streak = day
			data.daily.last_day = today
			-- `or 0` for a save written before this field existed.
			data.daily.best_streak = math.max(data.daily.best_streak or 0, day)
			verdict = "rewarded"
			return true
		end)
		:andThen(function()
			if verdict ~= "rewarded" then
				return nil
			end
			-- SAVED BEFORE ANYTHING ACTS ON IT. An update lives in lyra's
			-- session until something flushes it, and a server that dies first
			-- loses the credit AND the `last_day` that says it was paid -- so
			-- the player claims again on the next server and is paid twice.
			-- One write per player per day is not a cost worth carrying that
			-- for, and it is also what makes the reminder below honest.
			return datastore:save(player)
		end)
		:andThen(function()
			if verdict == "rewarded" then
				-- Scheduled AFTER the save, so a reminder never exists for a
				-- claim that did not survive. Does nothing unless
				-- `assets.notifications.DAILY_READY` is set.
				reminders.schedule(player.UserId, day, now)
				for currency, amount in paid do
					economy.source(player, currency, amount, ending[currency] or 0, "TimedReward", `daily_day_{day}`)
				end
			end
			if player.Parent == nil then
				-- They left mid-claim. The reward is theirs and is already
				-- saved; there is just nobody to tell.
				return
			end
			-- REQUIRED HERE, not at the top of the file. The alert service
			-- reaches the server's network layer at require time, and paying a
			-- daily reward and telling the player about it are separable: the
			-- claim has to work whether or not there is a wire, and keeping the
			-- require inside the branch that needs it is also what lets this
			-- module be loaded outside the engine. Roblox caches requires, so
			-- this costs one table lookup per claim.
			const alert = require(ReplicatedStorage.Shared.services.alert)
			if verdict == "rewarded" then
				alert.send_to(player, strings.fill(T.REWARDED, { day = day, reward = rules.reward_text(day) }))
			elseif verdict == "claimed" then
				alert.send_to(player, T.ALREADY_CLAIMED)
			else
				alert.send_to(player, T.LOCKED)
			end
			return
		end)
		:catch(function(err)
			-- Includes a failed save, which is why the player is told rather
			-- than left looking at a button that did nothing. Nothing was paid
			-- as far as anyone else can tell, and the claim is still available.
			warn(`[daily-rewards] could not reward {player.Name}: {tostring(err)}`)
			if player.Parent then
				require(ReplicatedStorage.Shared.services.alert).send_to(player, T.FAILED)
			end
		end)
end

local started = false
function start()
	if started then
		return
	end
	started = true

	-- Both required HERE rather than at module scope, for the same reason as the
	-- alert above: the wire is needed to receive a claim, not to make one. The
	-- limiter is built once, at the first `start`, because `validate.limiter`
	-- registers a window table that is never released.
	const server_network = require(ServerScriptService.Server.net["server-network"])
	const validate = require(ServerScriptService.Server.net.validate)
	const claim_limiter = validate.limiter(S.CLAIM_RATE, S.CLAIM_WINDOW)

	server_network.daily.claim:connect(function(player: Player)
		-- Silently: a client over the limit is either broken or lying, and
		-- neither is worth a round trip. The claim is idempotent anyway -- a
		-- dropped one costs a button press, not a reward.
		if not claim_limiter(player) then
			return
		end
		claim(player)
	end)
end

return table.freeze {
	start = start,
	claim = claim,
	set_gate = set_gate,
}
