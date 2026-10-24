--!strict
-- EffectPresets: the look of every effect, as data. Tune or add presets here;
-- Effects reads them by name. Textures are Roblox's built-in particle images,
-- so no uploads are needed.
--
-- kind = "burst"      a one-shot particle burst (+ optional light flash)
--        emitter      ParticleEmitter properties (Color/Size/Transparency may be
--                     plain values or sequences)
--        count        particles per burst
--        light        { Color, Brightness, Range, Time } -- a brief PointLight
-- kind = "shockwave"  an expanding flat ring
-- kind = "flash"      a Highlight that fades out on a model
-- kind = "trail"      a Trail along a held weapon

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function seq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

local function colors(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

return {
	-- Weapon connects with an enemy.
	HitSpark = {
		kind = "burst",
		count = 14,
		emitter = {
			Texture = SPARKLE,
			Color = colors(Color3.fromRGB(255, 244, 170), Color3.fromRGB(255, 160, 50)),
			Size = seq(0.55, 0),
			Transparency = seq(0, 1),
			Lifetime = NumberRange.new(0.16, 0.3),
			Speed = NumberRange.new(14, 26),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 6,
			Acceleration = Vector3.new(0, -30, 0),
			LightEmission = 1,
			RotSpeed = NumberRange.new(-300, 300),
		},
		light = { Color = Color3.fromRGB(255, 220, 140), Brightness = 3, Range = 9, Time = 0.12 },
	},
	-- The Fairy's wand zap: a pop of pink-gold fairy dust where the player stands.
	FairyZap = {
		kind = "burst",
		count = 26,
		emitter = {
			Texture = SPARKLE,
			Color = colors(Color3.fromRGB(255, 236, 160), Color3.fromRGB(255, 150, 220)),
			Size = seq(0.7, 0),
			Transparency = seq(0, 1),
			Lifetime = NumberRange.new(0.35, 0.6),
			Speed = NumberRange.new(6, 12),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 5,
			Acceleration = Vector3.new(0, 4, 0),
			LightEmission = 1,
			RotSpeed = NumberRange.new(-200, 200),
		},
		light = { Color = Color3.fromRGB(255, 190, 230), Brightness = 2.5, Range = 10, Time = 0.18 },
	},
	-- The Spider Queen's rear-up slam: crystal shards (cyan, lilac, pink) burst up
	-- and out where her legs come down, then fall.
	CrystalBurst = {
		kind = "burst",
		count = 36,
		emitter = {
			Texture = SPARKLE,
			Color = colors(Color3.fromRGB(143, 228, 247), Color3.fromRGB(255, 168, 216)),
			Size = seq(1.1, 0.2),
			Transparency = seq(0, 1),
			Lifetime = NumberRange.new(0.5, 0.85),
			Speed = NumberRange.new(14, 26),
			SpreadAngle = Vector2.new(70, 70),
			Drag = 2,
			Acceleration = Vector3.new(0, -40, 0),
			LightEmission = 1,
			RotSpeed = NumberRange.new(-240, 240),
		},
		light = { Color = Color3.fromRGB(170, 230, 255), Brightness = 4, Range = 18, Time = 0.25 },
	},
	-- Water: the bobber landing, a fish biting or leaping out (FishingController).
	Splash = {
		kind = "burst",
		count = 14,
		emitter = {
			Texture = SMOKE,
			Color = colors(Color3.fromRGB(235, 248, 255), Color3.fromRGB(170, 215, 240)),
			Size = seq(0.5, 1.4),
			Transparency = seq(0.2, 1),
			Lifetime = NumberRange.new(0.35, 0.6),
			Speed = NumberRange.new(6, 11),
			SpreadAngle = Vector2.new(35, 35),
			Drag = 2,
			Acceleration = Vector3.new(0, -30, 0),
			RotSpeed = NumberRange.new(-60, 60),
			EmissionDirection = Enum.NormalId.Top,
		},
	},
	-- Heavy footfalls, a charge, landing.
	Dust = {
		kind = "burst",
		count = 10,
		emitter = {
			Texture = SMOKE,
			Color = colors(Color3.fromRGB(214, 190, 150), Color3.fromRGB(180, 160, 130)),
			Size = seq(0.9, 2.6),
			Transparency = seq(0.35, 1),
			Lifetime = NumberRange.new(0.45, 0.8),
			Speed = NumberRange.new(4, 9),
			SpreadAngle = Vector2.new(80, 180),
			Drag = 4,
			Acceleration = Vector3.new(0, 3, 0),
			RotSpeed = NumberRange.new(-60, 60),
		},
	},
	-- An enemy is defeated.
	Poof = {
		kind = "burst",
		count = 22,
		emitter = {
			Texture = SMOKE,
			Color = colors(Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 220, 230)),
			Size = seq(1.4, 3.4),
			Transparency = seq(0.15, 1),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(6, 12),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 5,
			Acceleration = Vector3.new(0, 4, 0),
			RotSpeed = NumberRange.new(-90, 90),
		},
	},
	-- An enemy is defeated (WorldEnemyController, with Poof, a Shockwave and the
	-- EnemyPop sound): gold and white stars fly out and drop, with a warm flash.
	DeathPop = {
		kind = "burst",
		count = 20,
		emitter = {
			Texture = SPARKLE,
			Color = colors(Color3.fromRGB(255, 226, 90), Color3.fromRGB(255, 255, 255)),
			Size = seq(0.95, 0),
			Transparency = seq(0, 1),
			Lifetime = NumberRange.new(0.45, 0.8),
			Speed = NumberRange.new(14, 24),
			SpreadAngle = Vector2.new(180, 180),
			Drag = 4,
			Acceleration = Vector3.new(0, -12, 0),
			RotSpeed = NumberRange.new(-180, 180),
			LightEmission = 0.6,
		},
		light = { Color = Color3.fromRGB(255, 220, 140), Brightness = 3, Range = 12, Time = 0.18 },
	},
	-- Healing, pickups.
	Heal = {
		kind = "burst",
		count = 16,
		emitter = {
			Texture = SPARKLE,
			Color = colors(Color3.fromRGB(170, 255, 170), Color3.fromRGB(80, 220, 120)),
			Size = seq(0.45, 0),
			Transparency = seq(0, 1),
			Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(40, 180),
			Acceleration = Vector3.new(0, 8, 0),
			LightEmission = 1,
		},
	},
	-- A healing potion drunk (HurtController, 2026-10-22): green + signs float up and away
	-- (art/tools/ui/hurt_fx.py -> art/ui/hud/heal_plus.png).
	HealPlus = {
		kind = "burst",
		count = 9,
		emitter = {
			Texture = "rbxassetid://90672393638076",
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(0.2, 0.75),
				NumberSequenceKeypoint.new(1, 0.55),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.6, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(3, 5.5),
			SpreadAngle = Vector2.new(70, 180),
			Acceleration = Vector3.new(0, 5, 0),
			Drag = 2.5,
			LightEmission = 0,
		},
	},
	-- A player taking a hit (HurtController, 2026-10-22): a red glow on the whole body, as
	-- long as WeaponHud/HitFlash's red screen flash takes to fade (its FadeSeconds, 0.45).
	PlayerHurt = {
		kind = "flash",
		color = Color3.fromRGB(255, 40, 40),
		fillTransparency = 0.3,
		time = 0.45,
	},
	-- A ground slam / heavy impact.
	Shockwave = {
		kind = "shockwave",
		color = Color3.fromRGB(255, 240, 210),
		startSize = 1,
		endSize = 9,
		thickness = 0.15,
		time = 0.35,
		transparency = 0.35,
	},
	-- A heavy weapon hits the ground (weapon impact = "Slam", the Corn Cob).
	-- WeaponController fires SlamDust once per direction around the spot (each
	-- burst is aimed outward along its Front face), so the dust rolls out in a
	-- low ring; SlamDebris kicks clods up that fall back; SlamRing is the flash
	-- of the shock across the ground.
	SlamDust = {
		kind = "burst",
		count = 5,
		emitter = {
			Texture = SMOKE,
			EmissionDirection = Enum.NormalId.Front,
			Color = colors(Color3.fromRGB(196, 168, 124), Color3.fromRGB(150, 124, 92)),
			Size = seq(1.8, 4.6),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.4, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(14, 22),
			SpreadAngle = Vector2.new(14, 22),
			Drag = 5,
			Acceleration = Vector3.new(0, 2.5, 0),
			RotSpeed = NumberRange.new(-80, 80),
		},
	},
	SlamDebris = {
		kind = "burst",
		count = 16,
		emitter = {
			Texture = SMOKE,
			Color = colors(Color3.fromRGB(122, 92, 60), Color3.fromRGB(92, 70, 46)),
			Size = seq(0.55, 0.4),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.75, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(0.55, 0.85),
			Speed = NumberRange.new(14, 24),
			SpreadAngle = Vector2.new(38, 38),
			Acceleration = Vector3.new(0, -70, 0),
			RotSpeed = NumberRange.new(-200, 200),
		},
	},
	-- The Weathervane Spear's Gust (impact = "Gust", 2026-10-19): WeaponController fires
	-- GustWind across the front of the sweep, right to left, each burst aimed outward
	-- (Front), pale streaks of wind that shoot out and stretch thin; GustDust kicks a
	-- little dust off the ground under them.
	GustWind = {
		kind = "burst",
		count = 6,
		emitter = {
			Texture = SMOKE,
			EmissionDirection = Enum.NormalId.Front,
			Color = colors(Color3.fromRGB(244, 252, 255), Color3.fromRGB(196, 232, 244)),
			Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.6),
				NumberSequenceKeypoint.new(0.3, 1.6),
				NumberSequenceKeypoint.new(1, 2.4),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.5, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(0.35, 0.55),
			Speed = NumberRange.new(26, 38),
			SpreadAngle = Vector2.new(8, 10),
			Drag = 6,
			RotSpeed = NumberRange.new(-260, 260),
		},
	},
	GustDust = {
		kind = "burst",
		count = 4,
		emitter = {
			Texture = SMOKE,
			EmissionDirection = Enum.NormalId.Front,
			Color = colors(Color3.fromRGB(214, 196, 158), Color3.fromRGB(176, 156, 120)),
			Size = seq(1.2, 3.2),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.25),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(0.45, 0.7),
			Speed = NumberRange.new(10, 16),
			SpreadAngle = Vector2.new(18, 10),
			Drag = 5,
			Acceleration = Vector3.new(0, 2, 0),
		},
	},
	-- The Pumpkin King's Mace (impact = "Pumpkin", 2026-10-19): orange sparks and a glow
	-- where the head lands, and cream pumpkin seeds that jump and fall back.
	PumpkinSparks = {
		kind = "burst",
		count = 22,
		emitter = {
			Texture = SPARKLE,
			Color = colors(Color3.fromRGB(255, 196, 64), Color3.fromRGB(240, 110, 24)),
			LightEmission = 1,
			Size = seq(0.9, 0.2),
			Transparency = seq(0, 1),
			Lifetime = NumberRange.new(0.3, 0.55),
			Speed = NumberRange.new(16, 28),
			SpreadAngle = Vector2.new(60, 60),
			Acceleration = Vector3.new(0, -30, 0),
			RotSpeed = NumberRange.new(-180, 180),
		},
		light = { Color = Color3.fromRGB(255, 150, 40), Brightness = 3, Range = 12, Time = 0.25 },
	},
	PumpkinSeeds = {
		kind = "burst",
		count = 12,
		emitter = {
			Texture = SMOKE,
			Color = colors(Color3.fromRGB(250, 238, 200), Color3.fromRGB(232, 214, 168)),
			Size = seq(0.35, 0.3),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.8, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Lifetime = NumberRange.new(0.6, 0.9),
			Speed = NumberRange.new(12, 20),
			SpreadAngle = Vector2.new(45, 45),
			Acceleration = Vector3.new(0, -60, 0),
			RotSpeed = NumberRange.new(-300, 300),
		},
	},
	SlamRing = {
		kind = "shockwave",
		color = Color3.fromRGB(255, 236, 196),
		startSize = 2,
		endSize = 18,
		thickness = 0.12,
		time = 0.45,
		transparency = 0.3,
	},
	-- Something takes damage.
	HurtFlash = {
		kind = "flash",
		color = Color3.fromRGB(255, 255, 255),
		fillTransparency = 0.35,
		time = 0.15,
	},
	-- A weapon's swing arc.
	SlashTrail = {
		kind = "trail",
		Color = colors(Color3.fromRGB(255, 255, 255), Color3.fromRGB(220, 230, 255)),
		Transparency = seq(0.25, 1),
		Lifetime = 0.15,
		LightEmission = 0.5,
		WidthScale = seq(1, 0.25),
		MinLength = 0.05,
		FaceCamera = false,
		-- Where along the weapon (fractions of its length from the grip) the trail runs.
		from = 0.35,
		to = 1,
	},
}
