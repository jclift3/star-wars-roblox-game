--!strict
--[[
	Palette.luau

	Single source of truth for colour across the whole game. Costumes, ships and
	world geometry all pull from here, which is what keeps the art direction
	coherent instead of every module inventing its own shade of grey.

	Values are eyeballed from the films rather than from Roblox's BrickColor
	palette -- BrickColor is a small fixed set and its greys read as toy plastic.
]]

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local Palette = {
	-- Armour / uniforms ---------------------------------------------------
	StormtrooperWhite = rgb(242, 243, 245),
	StormtrooperShadow = rgb(206, 209, 214),
	StormtrooperLens = rgb(18, 18, 20),
	SandtrooperTan = rgb(214, 201, 173),
	ImperialGrey = rgb(74, 78, 84),
	ImperialOfficerGreen = rgb(88, 92, 78),
	ImperialBlack = rgb(24, 25, 28),
	DeathTrooperBlack = rgb(38, 39, 43),
	RoyalGuardRed = rgb(155, 30, 34),

	RebelOrange = rgb(226, 122, 40),
	RebelTan = rgb(196, 178, 143),
	RebelOlive = rgb(96, 102, 74),
	RebelBlue = rgb(58, 82, 122),

	CloneWhite = rgb(236, 238, 240),
	CloneBlue = rgb(52, 96, 168),

	-- Cloth ---------------------------------------------------------------
	JediBrown = rgb(96, 71, 48),
	JediCream = rgb(198, 178, 148),
	SithBlack = rgb(20, 20, 24),
	SmugglerBrown = rgb(74, 56, 42),
	JawaBrown = rgb(64, 44, 32),
	TuskenWrap = rgb(150, 132, 104),
	NabooRoyal = rgb(122, 36, 62),

	-- Skin ----------------------------------------------------------------
	SkinPale = rgb(225, 190, 165),
	SkinLight = rgb(205, 165, 135),
	SkinMid = rgb(168, 124, 92),
	SkinDeep = rgb(112, 78, 56),
	SkinDark = rgb(74, 52, 38),

	TwilekBlue = rgb(96, 140, 190),
	TwilekRed = rgb(168, 62, 58),
	TwilekGreen = rgb(126, 158, 96),
	RodianGreen = rgb(108, 152, 88),
	KaminoanGrey = rgb(206, 210, 216),
	WookieeBrown = rgb(112, 78, 46),
	TrandoshanScale = rgb(140, 148, 82),
	GunganTan = rgb(178, 152, 110),
	ZabrakRust = rgb(178, 88, 62),

	-- The Underlevels. Sunless skin over an industrial sump, and the horn
	-- that grows over the hands of something that climbs for a living.
	MutantFlesh = rgb(126, 132, 118),
	MutantPallor = rgb(154, 150, 132),
	MutantClaw = rgb(58, 52, 44),

	-- Droids --------------------------------------------------------------
	DroidGold = rgb(198, 158, 54),
	DroidSilver = rgb(178, 182, 188),
	DroidWhiteBlue = rgb(232, 234, 238),
	AstromechBlue = rgb(48, 96, 168),
	DroidRust = rgb(122, 88, 62),
	BattleDroidTan = rgb(188, 158, 106),

	-- Sabers & energy ------------------------------------------------------
	SaberBlue = rgb(88, 176, 255),
	SaberGreen = rgb(96, 240, 118),
	SaberRed = rgb(255, 62, 52),
	SaberPurple = rgb(178, 96, 255),
	SaberYellow = rgb(248, 224, 88),
	SaberWhite = rgb(240, 248, 255),
	BlasterRed = rgb(255, 74, 48),
	BlasterGreen = rgb(96, 255, 108),
	BlasterBlue = rgb(96, 190, 255),

	-- Hardware -------------------------------------------------------------
	Gunmetal = rgb(58, 60, 66),
	DarkMetal = rgb(38, 40, 45),
	WornSteel = rgb(126, 130, 138),
	CopperTrim = rgb(150, 104, 62),
	HullGrey = rgb(158, 160, 164),
	HullWhite = rgb(224, 226, 228),
	CockpitGlass = rgb(96, 128, 140),

	-- World ----------------------------------------------------------------
	TatooineSand = rgb(214, 184, 138),
	TatooineRock = rgb(166, 134, 98),
	HothSnow = rgb(238, 244, 250),
	HothIce = rgb(186, 214, 232),
	MustafarBasalt = rgb(46, 38, 36),
	MustafarLava = rgb(255, 108, 24),
	NabooGrass = rgb(112, 156, 78),
	NabooStone = rgb(206, 194, 168),
	KaminoSea = rgb(62, 88, 110),
	CoruscantPlate = rgb(102, 106, 116),
	CoruscantLight = rgb(255, 214, 138),
}

return Palette
