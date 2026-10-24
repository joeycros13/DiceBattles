--!strict
-- Client bootstrap: loads util, controllers, and UI, then inits/starts them in
-- dependency order via the shared Loader (util -> controllers -> UI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared:WaitForChild("Loader"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UTIL_ORDER = {
	-- first: sizes every pixel-only UI value (outlines, text caps...) for this screen
	"Responsive",
	-- the UI and reward sounds (Assets/Sounds/UI): clicks, panels, coins landing, level up
	"UiSound",
	-- the hover and click effect on every clickable button (an "FxScale" UIScale on it)
	"ButtonFx",
	"DamagePopup",
	"HudFly",
	"FontDrop",
	-- the comic "BONK!" when an enemy is defeated
	"BonkPop",
	"Format",
	-- the shared weapon tile every screen clones
	"WeaponTile",
	-- every stat's shown total, for any player (the Stats panel and the profile cards)
	"StatSheet",
	-- sizes the text in icon + text rows so they stay centred
	"CenterRow",
}

local CONTROLLER_ORDER = {
	"InteractionController",
	"NpcIdleController",
	"WorldEnemyController",
	"EnemyAnimator",
	"CritterController",
	"SprintController",
	-- Before WeaponController: both pose joints each frame, and the weapon arm and
	-- swings must win over the idle / walk / sprint pose.
	"PlayerAnimator",
	"WeaponController",
	"LootController",
	"SpinnerController",
	"FlowController",
	"QuestController",
	"GuideController",
	"ChatTagController",
	"PromptController",
	-- the black fade around teleports (secret rooms, the Worlds menu)
	"FadeController",
	-- the World 2 lookout telescope's zoom onto the fairy ring
	"TelescopeController",
	-- local sky/lighting for special places (the stump room's twilight)
	"AmbienceController",
	-- each world's background sounds (birds, wind, music) only while you're in it
	"WorldAudioController",
	-- the Infuser altars: the Infuse prompt and the infusion reveal
	"InfuserController",
	-- World 3's secret: the three breathing crystals and their colour code
	"SecretCrystalController",
	-- trees and rocks you break with your weapon for materials
	"GatherController",
	-- casting, the bobber and the line, bites and the reel-in (FishingRingUI draws the rings)
	"FishingController",
	-- the healing fountain's sparkles and "+HP" popup (HealZoneService heals)
	"HealZoneController",
	-- applies the player's settings (volumes, guide arrow, particles, shadows; Config/Settings)
	"SettingsController",
	-- a hit's red glow, recoil and stumble; the low-health edge glow; a healing potion's + signs
	"HurtController",
	-- the weekly leaderboard winners' medal over the head and #1 trail
	"LeaderFlairController",
	-- every other player's name over their head in the game's font (Roblox's own is hidden)
	"NameTagController",
}

local UI_ORDER = {
	"PanelWindow",
	"InventoryUI",
	"PlayerCardUI",
	"HotbarUI",
	"ShopUI",
	"CraftingUI",
	-- the World 1 Upgrades stand (Config/Upgrades, UpgradeService)
	"UpgradesUI",
	-- the World 1 Daily Rewards stand and promo codes (Config/DailyRewards, DailyRewardService)
	"DailyRewardsUI",
	-- the HUD's Stats panel: every multiplier and where it comes from
	"StatsUI",
	-- the player card (yours from the HUD avatar, anyone's from the player list) and
	-- the press-E peek on other players
	"ProfileUI",
	"InspectUI",
	-- the HUD's Leaderboards panel (LeaderboardService)
	"LeaderboardUI",
	-- the HUD's Settings panel (Config/Settings; SettingsController applies them)
	"SettingsUI",
	"RobuxShopUI",
	"IndexUI",
	"IndexPopup",
	"CoinsUI",
	-- crafting materials picked up: a toast on the right
	"MaterialToastUI",
	"DialogueUI",
	"QuestTrackerUI",
	"GateUI",
	"WorldBannerUI",
	"AdminUI",
	"BoostHudUI",
	-- the Infuser altar's panel (opened by InfuserController)
	"InfuserUI",
	-- the Worlds menu: teleport to any unlocked world (HUD globe button)
	"WorldsUI",
	-- the fishing minigame's closing rings (FishingController starts them)
	"FishingRingUI",
	-- our own player list, top right (name, level, coins; replaces Roblox's)
	"PlayerListUI",
	-- last: loads every asset and draws every panel once behind the join cover
	"Preloader",
}

print("[Client] bootstrap starting")

local util = Loader.requireChildren(script:WaitForChild("Util"))
local controllers = Loader.requireChildren(script:WaitForChild("Controllers"))
local ui = Loader.requireChildren(script:WaitForChild("UI"))

local deps = {
	Remotes = Remotes,
	Util = util,
	Controllers = controllers,
	UI = ui,
}

-- Init in dependency order: util first, then controllers, then UI.
Loader.initModules(util, deps, UTIL_ORDER)
Loader.initModules(controllers, deps, CONTROLLER_ORDER)
Loader.initModules(ui, deps, UI_ORDER)

Loader.startModules(util, UTIL_ORDER)
Loader.startModules(controllers, CONTROLLER_ORDER)
Loader.startModules(ui, UI_ORDER)

print("[Client] bootstrap complete")
