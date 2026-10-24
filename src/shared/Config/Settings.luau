--!strict
-- Settings: the player's own settings (2026-10-22, the user's pick: the Settings panel,
-- layout A "Sectioned list" on https://claude.ai/artifact/QCU1fmrygg133qdZJxWcHh).
--
-- Every setting is saved per player (SettingsService, the "settings" section of
-- PlayerDataService) and published as a "Setting_<id>" player attribute; the client
-- applies them (Client.Controllers.SettingsController) and the hand-built
-- StarterGui/SettingsPanel changes them (Client.UI.SettingsUI).
--   volume   0..1, a share of the SoundGroup's own mix (its BaseVolume attribute):
--            1 is the game as mixed, lower is quieter
--   toggle   true / false
-- Every word the panel shows is here: each def's `name` and `note`, the sections' names.

local Settings = {}

export type SettingDef = {
	id: string,
	section: string,
	kind: "volume" | "toggle",
	default: number | boolean,
	name: string,
	note: string,
	group: string?, -- volume: the SoundService SoundGroup it scales
}

Settings.Sections = {
	{ id = "Sound", name = "Sound" },
	{ id = "Gameplay", name = "Gameplay" },
	{ id = "Graphics", name = "Graphics" },
}

local LIST: { SettingDef } = {
	{ id = "Music", section = "Sound", kind = "volume", default = 1, group = "Music",
		name = "Music", note = "The world's background tune" },
	{ id = "Ambience", section = "Sound", kind = "volume", default = 1, group = "Ambience",
		name = "Ambience", note = "Birds, wind, water, the campfire" },
	{ id = "Effects", section = "Sound", kind = "volume", default = 1, group = "Effects",
		name = "Sound effects", note = "Hits, pops, footsteps, chopping" },
	{ id = "Interface", section = "Sound", kind = "volume", default = 1, group = "UI",
		name = "Interface", note = "Clicks, coins landing, level up" },
	{ id = "Guide", section = "Gameplay", kind = "toggle", default = true,
		name = "Guide arrow", note = "Points at your quest target" },
	{ id = "Hits", section = "Gameplay", kind = "toggle", default = true,
		name = "Hit bubbles", note = "Damage numbers on enemies" },
	{ id = "SprintZoom", section = "Gameplay", kind = "toggle", default = true,
		name = "Sprint zoom", note = "The camera widens while you sprint" },
	{ id = "Particles", section = "Graphics", kind = "toggle", default = true,
		name = "Particles", note = "Petals, butterflies, fireflies" },
	{ id = "Shadows", section = "Graphics", kind = "toggle", default = true,
		name = "Shadows", note = "Turn off for a faster game on phones" },
}

local BY_ID: { [string]: SettingDef } = {}
for _, def in LIST do
	BY_ID[def.id] = def
end

function Settings.list(): { SettingDef }
	return LIST
end

function Settings.get(id: any): SettingDef?
	return if type(id) == "string" then BY_ID[id] else nil
end

function Settings.attr(id: string): string
	return "Setting_" .. id
end

-- A value as it may be stored for `def`, or nil if it can't be (a wrong type).
-- Volumes are clamped to 0..1 in steps of 0.01.
function Settings.clean(def: SettingDef, value: any): (number | boolean)?
	if def.kind == "volume" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		return math.floor(math.clamp(value, 0, 1) * 100 + 0.5) / 100
	end
	return if type(value) == "boolean" then value else nil
end

-- The player's setting, or its default before the save has loaded.
function Settings.value(player: Player, id: string): any
	local def = BY_ID[id]
	local value = player:GetAttribute(Settings.attr(id))
	if def and Settings.clean(def, value) ~= nil then
		return value
	end
	return def and def.default
end

-- A toggle's state, true by default.
function Settings.on(player: Player, id: string): boolean
	return Settings.value(player, id) ~= false
end

return Settings
