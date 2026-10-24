--!strict
-- Leaderboards: 6 boards, 3 stats x 2 periods (2026-10-19, the user's design; the
-- panel is option A "tabs and podium" on https://claude.ai/artifact/E7RQQXPYH2ZCKBB6V4YaWk).
-- Daily boards were dropped on 2026-10-22 (the user: a daily payout means "constantly
-- pumping out rewards"): Weekly boards pay out, All-time boards are for bragging rights.
--   Coins   coins EARNED in the period (kills, quests, rewards from Dale...), never coins
--           held, so spending doesn't drop you; Robux bundles and admin grants don't count.
--           All-time: lifetime coins earned.
--   Levels  levels GAINED in the period. All-time: the player's total EXP, shown as
--           their level (EXP breaks ties).
--   Kills   every kill: regular enemies, bosses and secret enemies.
-- Weekly boards reset at Monday 00:00 UTC. The top 50 show.
-- When a weekly board resets, its #1, #2 and #3 get their rewards (Rewards below; the
-- user kept it to the top 3 on 2026-10-22), waiting in a mailbox until they next join,
-- plus a gold / silver / bronze medal (over their head and in the player list) and, for
-- #1, that board's trail, both until the next reset, and a trophy kept for good (the
-- Ranks panel's Trophies view). All-time boards give none. Never weapons, and never
-- upgrade levels (they'd dodge the per-world cap). Amounts are placeholders to tune.

local Leaderboards = {}

Leaderboards.Stats = { "Coins", "Levels", "Kills" }
Leaderboards.Periods = { "Weekly", "All" }
Leaderboards.TOP = 50

-- How often a server writes its players' scores and re-reads the boards (seconds).
Leaderboards.WRITE_EVERY = 120
Leaderboards.READ_EVERY = 60

local DAY = 86400

-- The day number of a time (UTC), and the week number with weeks starting on Monday
-- (1970-01-01, day 0, was a Thursday, so Monday-based weeks start 3 days later).
function Leaderboards.dayOf(t: number): number
	return math.floor(t / DAY)
end
function Leaderboards.weekOf(t: number): number
	return math.floor((Leaderboards.dayOf(t) + 3) / 7)
end

-- The key naming a period's board ("W2911" / "All") at time t.
function Leaderboards.periodKey(period: string, t: number): string
	if period == "Weekly" then
		return "W" .. Leaderboards.weekOf(t)
	end
	return "All"
end

-- When the current period ends (server time), or nil for all-time.
function Leaderboards.resetsAt(period: string, t: number): number?
	if period == "Weekly" then
		return ((Leaderboards.weekOf(t) + 1) * 7 - 3) * DAY
	end
	return nil
end

-- The OrderedDataStore that holds a board.
function Leaderboards.storeName(stat: string, period: string, key: string?): string
	return ("LB_%s_%s"):format(stat, key or "All")
end

-- Reward tiers, by period. Each reward: coins, exp, potions { { kind, count } } (at the
-- tier of the player's world band, Potions.tierAt), boosts { { id, minutes } }
-- (Config/Shop's timed boosts), materials (how many of each of the player's highest
-- world's enemy materials, never cores or quest items), tag (the chat tag until the
-- next reset; %s = the board's name) and trophy (the medal worn until the next reset and
-- the cup counted for good, per board, in the Ranks panel's Trophies view).
export type Reward = {
	coins: number?,
	exp: number?,
	potions: { { kind: string, count: number } }?,
	boosts: { { id: string, minutes: number } }?,
	materials: number?,
	tag: string?,
	trophy: string?, -- "Gold" | "Silver" | "Bronze"
}
export type Tier = { label: string, from: number, to: number, reward: Reward }

Leaderboards.Rewards = {
	Weekly = {
		{ label = "#1", from = 1, to = 1, reward = { coins = 5000, potions = { { kind = "Strength", count = 3 }, { kind = "Stoneskin", count = 3 }, { kind = "Health", count = 3 } }, boosts = { { id = "Luck", minutes = 30 }, { id = "Coins", minutes = 30 } }, tag = "#1 Weekly %s", trophy = "Gold" } },
		{ label = "#2", from = 2, to = 2, reward = { coins = 2500, potions = { { kind = "Strength", count = 2 }, { kind = "Health", count = 2 } }, materials = 15, trophy = "Silver" } },
		{ label = "#3", from = 3, to = 3, reward = { coins = 1500, exp = 1000, potions = { { kind = "Health", count = 2 } }, materials = 10, trophy = "Bronze" } },
	},
} :: { [string]: { Tier } }

-- The places a board pays (the last tier's `to`): only these are read when a week ends.
function Leaderboards.paidPlaces(period: string): number
	local last = 0
	for _, tier in Leaderboards.Rewards[period] or {} do
		last = math.max(last, tier.to)
	end
	return last
end

-- The three medals and cups (2026-10-22, medal A and trophy view B on the "Leaderboard
-- rewards" canvas, https://claude.ai/artifact/Sjkt4yWCvqYH2dWYRot9Vg; art from
-- art/tools/icons/leader_icons.py), best first. `fill` / `rim` colour the player-list chip.
Leaderboards.MedalOrder = { "Gold", "Silver", "Bronze" }
Leaderboards.Medals = {
	Gold = { place = 1, medal = "rbxassetid://75772137275815", cup = "rbxassetid://117647447537398", fill = Color3.fromHex("ffd23f"), rim = Color3.fromHex("c98a0b") },
	Silver = { place = 2, medal = "rbxassetid://127820547528025", cup = "rbxassetid://123632312963232", fill = Color3.fromHex("e4ebf2"), rim = Color3.fromHex("8f9cad") },
	Bronze = { place = 3, medal = "rbxassetid://73982180655503", cup = "rbxassetid://123487059752347", fill = Color3.fromHex("eaa46a"), rim = Color3.fromHex("9c5a26") },
}

function Leaderboards.tierFor(period: string, rank: number): Tier?
	for _, tier in Leaderboards.Rewards[period] or {} do
		if rank >= tier.from and rank <= tier.to then
			return tier
		end
	end
	return nil
end

-- Every word the panel and the reward messages show.
Leaderboards.Text = {
	title = "Leaderboards",
	stat = { Coins = "Coins earned", Levels = "Levels gained", Kills = "Kills" },
	statShort = { Coins = "Coins", Levels = "Levels", Kills = "Kills" },
	period = { Weekly = "Weekly", All = "All time", Trophies = "Trophies" },
	resetsIn = "Resets in %s",
	never = "Never resets",
	you = "You · #%s",
	youUnranked = "You · 50+",
	rewards = "Rewards",
	allTime = "All time",
	allTimeNote = "All-time boards never reset, so they give no rewards. Finishing in the weekly top 3 earns a trophy.",
	-- the medal chip in the player list and over the head ("#1 Coins")
	medalChip = "#%d %s",
	-- the Trophies view
	trophiesTitle = "My trophies",
	trophyPlace = { Gold = "#1", Silver = "#2", Bronze = "#3" },
	trophyCount = "x%d", -- a plain x: Luckiest Guy has no × sign
	noTrophies = "Finish in the weekly top 3 to earn one.",
	empty = "No one yet. Be the first!",
	level = "Lv %s",
	-- the reward message (chat)
	won = "You finished %s on the %s %s board! Rewards: %s",
	coins = "%s coins",
	exp = "%s EXP",
	potion = "%d× %s",
	boost = "%d min %s",
	materials = "%d of each material",
	tag = "the [%s] tag",
	trophy = "%s trophy",
}

local function commas(n: number): string
	local s = tostring(math.floor(n))
	while true do
		local swapped, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = swapped
		if count == 0 then
			return s
		end
	end
end

-- The reward's contents as words, for the chips and the chat message.
function Leaderboards.describe(reward: Reward): { string }
	local t = Leaderboards.Text
	local out = {}
	if reward.tag then
		table.insert(out, "Chat tag")
	end
	if reward.coins then
		table.insert(out, t.coins:format(commas(reward.coins)))
	end
	if reward.exp then
		table.insert(out, t.exp:format(commas(reward.exp)))
	end
	for _, p in reward.potions or {} do
		table.insert(out, t.potion:format(p.count, p.kind))
	end
	for _, b in reward.boosts or {} do
		table.insert(out, t.boost:format(b.minutes, "2× " .. b.id))
	end
	if reward.materials then
		table.insert(out, t.materials:format(reward.materials))
	end
	if reward.trophy then
		table.insert(out, t.trophy:format(reward.trophy))
	end
	return out
end

return Leaderboards
