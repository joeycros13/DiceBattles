--!strict
-- Admin: who may use the admin panel (AdminService checks every request on the
-- server; the panel only shows for them), and every word the panel shows (the
-- user's rule: UI text lives in code).
--
-- An admin is anyone in `userIds`, the place's owner once it is published (a
-- user-owned place's creator, or a group place's owner rank), or anyone at all
-- while testing in Studio.

local Admin = {}

Admin.userIds = {
	335876692, -- the game's creator (PENGUIN_MONSTERS)
}

-- Anyone is an admin in a Studio playtest.
Admin.studioAlways = true

-- The key that opens and closes the panel (admins only).
Admin.toggleKey = Enum.KeyCode.F2

-- Biggest single coin / EXP change, so a typo can't break a save.
Admin.maxAmount = 1e9

-- Highest max health the panel can set.
Admin.maxHealth = 1e6

-- Give All tops every material up to this many (and each secret-weapon core to 1).
Admin.giveAllMaterials = 100
Admin.giveAllPotions = 10 -- of every potion, all three tiers (2026-10-19)

-- The Damage card's multiplier range (your own weapon damage, this session only).
Admin.minDamage = 0.1
Admin.maxDamage = 1000

-- The quick-add chips beside each amount box (Quick1, Quick2).
Admin.quick = {
	coins = { 1000, 100000 },
	exp = { 100, 1000 },
}

Admin.Text = {
	title = "Admin Panel",
	hint = "F2 opens and closes",
	tabs = { PagePlayer = "Player", PageWeapons = "Weapons", PageArmor = "Armor", PageTools = "Tools", PageMaterials = "Materials", PagePotions = "Potions", PageUpgrades = "Upgrades", PageQuests = "Quests", PageMobs = "Mobs" },
	coinsTitle = "Coins",
	expTitle = "EXP",
	levelTitle = "Level",
	healthTitle = "Health",
	damageTitle = "Damage",
	giveAll = "Give All",
	giveAllDone = "Gave %d weapons, %d tools, %d armor sets, %d of every material and %d of every potion",
	potionsEnded = "Every running potion ended",
	-- the Upgrades page (2026-10-22)
	upgradeNote = "Level %d of %d · %s", -- level, max, what it gives now (Upgrades.describe)
	setLevel = "Set",
	upOne = "+1",
	allUpgrades = "All upgrades",
	allUpgradesNote = "Every upgrade at once",
	maxAll = "Max all",
	resetAll = "Reset all",
	upgradeSet = "%s: level %d",
	upgradesAll = "Every upgrade now at level %d",
	-- the Quests page (2026-10-19)
	questNote = "Step %d of %d · %s", -- step, steps, state (Offer / Active / Ready)
	questFinished = "All %d steps done",
	questSet = "%s: now on step %d of %d",
	questDone = "%s: finished",
	questAlreadyDone = "%s is already finished",
	skip = "Skip",
	goTo = "Go",
	damageBadge = "×%s",
	damageReset = "×1",
	damageDone = "Your damage is now ×%s",
	damageResetDone = "Your damage is back to ×1",
	heal = "Heal",
	youHave = "You have %s",
	expInto = "%s / %s into level %s",
	add = "Add",
	take = "Take",
	set = "Set",
	levelUp = "+1 Level",
	quick = "+%s",
	give = "Give",
	remove = "Remove",
	starter = "Starter",
	materialStep = 10, -- the materials page's Give / Take buttons move this many
	potionStep = 1, -- the potions page's Give / Take buttons move this many
	tierHeader = "Tier %s · Worlds %d–%d", -- the potions page's sections
	giveMany = "+%d",
	takeMany = "-%d",
	materialCount = "×%s",
	armorDef = "%d%% Def",
	worldHeader = "World %d · %s",
	mobNote = "%d in the world · %d dead",
	mobNoteAllAlive = "%d in the world · all alive",
	bossNote = "Boss · %s",
	bossAlive = "alive",
	bossDead = "dead",
	respawnMany = "Respawn %d",
	respawnOne = "Respawn",
	noMobs = "No enemies here yet",
	coinsDone = "%s coins", -- the signed amount
	expDone = "%s EXP",
	levelDone = "Now level %s",
	giveDone = "Gave %s",
	giveHave = "You already have %s",
	removeDone = "Removed %s",
	removeStarter = "%s is the starter weapon; it can't be removed",
	removeMissing = "You don't have %s",
	materialDone = "%s %s", -- the signed amount, the material's name
	armorDone = "Gave %s",
	armorRemoved = "Removed %s",
	respawnDone = "Respawned %d %s",
	healthDone = "Max health set to %s",
	healthReset = "Max health back to your level's %s",
	healDone = "Healed to %s",
	healDead = "You need to be alive to heal",
	badNumber = "Type a number first",
	notAdmin = "Admins only",
	unknown = "Unknown action",
}

return Admin
