--!strict
-- DiceHands: pure logic to detect the best poker-style hand for 1..5 dice and
-- return its multiplier (R-C12, R-C13). No `game` state is read besides the
-- Balance config, so this module is deterministic and unit-testable.
--
-- Multipliers come from Balance.HandMultipliers; hand names below match its keys.
-- Hands requiring more dice than the player owns are naturally unavailable
-- because they can never satisfy the frequency/shape checks with fewer dice
-- (e.g. two pair needs >=4 dice, four of a kind needs >=4, full house/straight/
-- five of a kind need exactly 5).

local Balance = require(script.Parent.Parent.Config.Balance)

local DiceHands = {}

-- Best-to-worst ranking, used only for documentation/reference. Detection below
-- checks in this order and returns the first match.
DiceHands.Ranking = {
	"fiveOfAKind",
	"fourOfAKind",
	"fullHouse",
	"straight",
	"threeOfAKind",
	"twoPair",
	"onePair",
	"highCard",
}

export type HandResult = {
	hand: string, -- one of the Balance.HandMultipliers keys
	multiplier: number,
}

-- Multiplier for a named hand; falls back to highCard for unknown names.
function DiceHands.multiplierFor(hand: string): number
	local mult = Balance.HandMultipliers[hand]
	if mult == nil then
		return Balance.HandMultipliers.highCard
	end
	return mult
end

local function result(hand: string): HandResult
	return { hand = hand, multiplier = DiceHands.multiplierFor(hand) }
end

-- Detect the best hand for the given dice face values (each 1..faces).
-- `dice` length is expected to be 1..maxDice; empty/nil is treated as highCard.
function DiceHands.evaluate(dice: { number }): HandResult
	local n = #dice
	if n == 0 then
		return result("highCard")
	end

	-- Frequency of each face value.
	local countsByValue: { [number]: number } = {}
	for _, value in dice do
		countsByValue[value] = (countsByValue[value] or 0) + 1
	end

	-- Sorted list of counts (descending) plus distinct-value bookkeeping.
	local freqs: { number } = {}
	local distinct = 0
	local minValue = math.huge
	local maxValue = -math.huge
	for value, count in countsByValue do
		table.insert(freqs, count)
		distinct += 1
		if value < minValue then
			minValue = value
		end
		if value > maxValue then
			maxValue = value
		end
	end
	table.sort(freqs, function(a, b)
		return a > b
	end)

	local top = freqs[1] or 0
	local second = freqs[2] or 0

	-- Best-to-worst checks. Each shape implicitly requires enough dice.
	if top >= 5 then
		return result("fiveOfAKind")
	end
	if top >= 4 then
		return result("fourOfAKind")
	end
	if top >= 3 and second >= 2 then
		-- 3 of one value + 2 of another => exactly 5 dice.
		return result("fullHouse")
	end
	-- Straight: exactly 5 distinct, consecutive values (needs 5 dice by definition).
	if n == 5 and distinct == 5 and (maxValue - minValue) == 4 then
		return result("straight")
	end
	if top >= 3 then
		return result("threeOfAKind")
	end
	if top >= 2 and second >= 2 then
		-- Two distinct values each appearing >=2 => needs >=4 dice.
		return result("twoPair")
	end
	if top >= 2 then
		return result("onePair")
	end

	return result("highCard")
end

return DiceHands
