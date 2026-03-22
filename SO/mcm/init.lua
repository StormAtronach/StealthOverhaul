local config = require("StormAtronach.SO.config")

local authors = { { name = "Storm Atronach", url = "https://next.nexusmods.com/profile/StormAtronach0" } }

--- @param self mwseMCMInfo|mwseMCMHyperlink
local function center(self)
	self.elements.info.absolutePosAlignX = 0.5
end

--- Adds default text to sidebar. Has a list of all the authors that contributed to the mod.
--- @param container mwseMCMSideBarPage
local function createSidebar(container)
	container.sidebar:createInfo({
		text = "\nWelcome to Stealth Overhaul!\n\nHover over a feature for more info.\n\nMade by:",
		postCreate = center,
	})
	for _, author in ipairs(authors) do
		container.sidebar:createHyperlink({ text = author.name, url = author.url, postCreate = center })
	end
end

local function registerModConfig()
	local template = mwse.mcm.createTemplate({
		name = "Stealth Overhaul",
		config = config,
		defaultConfig = config.default,
		showDefaultSetting = true,
	})
	template:register()
	template:saveOnClose(config.fileName, config)

	-- General page
	local page = template:createSideBarPage({ label = "General", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(page)

	page:createYesNoButton({
		label = "Enable Mod",
		description = "Enable or disable Stealth Overhaul.",
		configKey = "modEnabled",
	})

	page:createLogLevelOptions({ configKey = "logLevel" })

	page:createSlider({
		label = "AI Update Time",
		description = "Interval (in seconds) between NPC AI scans. The mod is balanced around 1 second. Lower values are more responsive but heavier on performance.",
		min = 1,
		max = 5,
		step = 1,
		configKey = "aiUpdateTime",
	})

	-- Detection page
	local detection = template:createSideBarPage({ label = "Detection", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(detection)

	detection:createCategory({ label = "Detection Model" })

	detection:createSlider({
		label = "Base Detection Range (units)",
		description = "Maximum detection range at sneak skill 0. Higher = NPCs spot the player from further away. 1320 units = 60 ft.",
		min = 200,
		max = 4000,
		step = 100,
		configKey = "baseRange",
	})

	detection:createSlider({
		label = "Max Range Reduction (%)",
		description = "How much sneak skill 100 shrinks the detection range relative to base. 75 means a master sneaker reduces NPC range by 75%.",
		min = 10,
		max = 95,
		step = 5,
		configKey = "maxReduce",
	})

	detection:createSlider({
		label = "Sneak Skill Power",
		description = "Curve of sneak skill's effect on range reduction. 1.0 = linear. Above 1.0 = diminishing returns at high sneak (recommended).",
		min = 0.5,
		max = 3.0,
		step = 0.1,
		jump = 0.1,
		decimalPlaces = 1,
		configKey = "sneakPow",
	})

	detection:createSlider({
		label = "Distance Falloff Power",
		description = "How steeply detection drops off with distance. 1.0 = linear. 2.0 = squared (sharp ramp at close range, recommended).",
		min = 1.0,
		max = 4.0,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		configKey = "distPow",
	})

	detection:createSlider({
		label = "Fill Time (seconds)",
		description = "Time to fill the detection bar from 0 to 100% at maximum detection rate (rate = 1.0). Lower = faster detection overall.",
		min = 1.0,
		max = 20.0,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		configKey = "fillTime",
	})

	detection:createSlider({
		label = "Detection Rate Cap",
		description = "Maximum detection rate per second (0–1). Prevents instant detection even at point-blank. Default 0.95.",
		min = 0.1,
		max = 1.0,
		step = 0.05,
		jump = 0.05,
		decimalPlaces = 2,
		configKey = "detCap",
	})

	detection:createSlider({
		label = "Detection Rate Floor",
		description = "Minimum detection rate within NPC detection range. Prevents true invisibility:there is always some risk. Default 0.03.",
		min = 0.0,
		max = 0.2,
		step = 0.01,
		jump = 0.01,
		decimalPlaces = 2,
		configKey = "detFloor",
	})

	detection:createCategory({ label = "Light Mechanic" })

	detection:createYesNoButton({
		label = "Enable Light Mechanic",
		description = "When enabled, the player's elusiveness is reduced while standing inside the radius of a light source in interior cells.",
		configKey = "lightMechanicEnabled",
	})

	detection:createSlider({
		label = "Light Rate Multiplier",
		description = "How much faster detection builds when the player is inside a light source's radius. 2.0 = double the detection rate. Only active when Light Mechanic is enabled.",
		min = 1.0,
		max = 5.0,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		configKey = "lightRateMult",
	})

	detection:createCategory({ label = "Suspicion Decay" })

	detection:createSlider({
		label = "Decay Time (seconds)",
		description = "How many seconds it takes for full suspicion to clear completely once decay begins. Higher = NPCs stay alert longer.",
		min = 1,
		max = 60,
		step = 1,
		configKey = "decayTime",
	})

	detection:createSlider({
		label = "Decay Delay (seconds)",
		description = "How long after the last suspicion increase before decay begins. Keeps NPCs alert for a moment even when the player steps out of detection range.",
		min = 0,
		max = 60,
		step = 1,
		configKey = "suspicionDecayDelay",
	})

	--[[ Steal Suspicion Bonus: disabled while onCrimeWitnessed is commented out.
	detection:createSlider({
		label = "Steal Suspicion Bonus",
		description = "Suspicion spike (as % of the detection bar) added to a witness when the player steals and has not yet been detected. Vanilla crime consequences are suppressed in that case. 50 = half the bar.",
		min = 0,
		max = 100,
		step = 5,
		configKey = "stealSuspicionBonus",
	}) ]]

	detection:createCategory({ label = "Display" })

	detection:createSlider({
		label = "Bar Display Range",
		description = "Distance in game units within which suspicion bars and markers are shown. Only applies while sneaking.",
		min = 500,
		max = 5000,
		step = 100,
		configKey = "barRange",
	})

	detection:createSlider({
		label = "Marker Min Size",
		description = "Size of the warning marker (in game units) at minimum suspicion.",
		min = 5,
		max = 100,
		step = 5,
		configKey = "markerMinSize",
	})

	detection:createSlider({
		label = "Marker Max Size",
		description = "Size of the warning marker (in game units) at full suspicion.",
		min = 5,
		max = 200,
		step = 5,
		configKey = "markerMaxSize",
	})

	-- Sneak Strike page
	local strike = template:createSideBarPage({ label = "Sneak Strike", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(strike)

	strike:createYesNoButton({
		label = "Enable Sneak Strike",
		description = "Enable or disable the sneak strike system. When disabled, vanilla sneak attack behaviour applies.",
		configKey = "sneakStrikeEnabled",
	})

	strike:createYesNoButton({
		label = "Show Sneak Strike Message",
		description = "Display a message showing the damage multiplier when landing a sneak strike.",
		configKey = "showSneakStrikeMessage",
	})

	strike:createCategory({ label = "Non-Lethal Knockout" })
	strike:createInfo({
		text = "Any weapon with a multiplier of exactly 1.0 triggers the knockout mechanic instead of dealing bonus damage: a helmet weight check is performed, and on success the target receives a fatigue dump and stops combat.",
	})

	strike:createCategory({ label = "Damage Multipliers" })
	strike:createInfo({
		text = "Applied to base weapon damage after undoing vanilla's sneak multiplier (4x melee, 1.5x ranged). Set to 1.0 to use the knockout mechanic instead.",
	})

	local mult = config.sneakStrikeMult
	strike:createSlider({
		label = "Hand to Hand",
		description = "Sneak attack multiplier for unarmed strikes. Set to 1.0 for non-lethal knockout.",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "handToHand", table = mult }),
	})
	strike:createSlider({
		label = "Short Blade: Dagger, Tanto, Wakizashi",
		description = "Sneak attack multiplier for one-handed short blades.",
		min = 1,
		max = 15,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "shortBladeOneHand", table = mult }),
	})
	strike:createSlider({
		label = "Long Blade (1H): Saber, Katana, Broadsword",
		description = "Sneak attack multiplier for one-handed long blades.",
		min = 1,
		max = 15,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "longBladeOneHand", table = mult }),
	})
	strike:createSlider({
		label = "Long Blade (2H): Claymore, Dai-Katana",
		description = "Sneak attack multiplier for two-handed long blades.",
		min = 1,
		max = 15,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "longBladeTwoClose", table = mult }),
	})
	strike:createSlider({
		label = "Blunt (1H): Club, Mace, Morning Star",
		description = "Sneak attack multiplier for one-handed blunt weapons. Set to 1.0 for non-lethal knockout.",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "bluntOneHand", table = mult }),
	})
	strike:createSlider({
		label = "Blunt (2H): Warhammer, Maul",
		description = "Sneak attack multiplier for two-handed close blunt weapons.",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "bluntTwoClose", table = mult }),
	})
	strike:createSlider({
		label = "Blunt (2H Wide): Staff",
		description = "Sneak attack multiplier for two-handed wide blunt weapons. Set to 1.0 for non-lethal knockout.",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "bluntTwoWide", table = mult }),
	})
	strike:createSlider({
		label = "Spear: Spear, Lance, Halberd",
		description = "Sneak attack multiplier for spears.",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "spearTwoWide", table = mult }),
	})
	strike:createSlider({
		label = "Axe (1H): Axe, Hatchet",
		description = "Sneak attack multiplier for one-handed axes.",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "axeOneHand", table = mult }),
	})
	strike:createSlider({
		label = "Axe (2H): Battle Axe, War Axe",
		description = "Sneak attack multiplier for two-handed axes.",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "axeTwoHand", table = mult }),
	})
	strike:createSlider({
		label = "Bow: Short Bow, Long Bow",
		description = "Sneak attack multiplier for bows. Vanilla ranged sneak bonus is 1.5x (vs 4x melee).",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "marksmanBow", table = mult }),
	})
	strike:createSlider({
		label = "Crossbow",
		description = "Sneak attack multiplier for crossbows. Vanilla ranged sneak bonus is 1.5x (vs 4x melee).",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "marksmanCrossbow", table = mult }),
	})
	strike:createSlider({
		label = "Thrown: Dart, Throwing Star, Throwing Knife",
		description = "Sneak attack multiplier for thrown weapons. Vanilla ranged sneak bonus is 1.5x (vs 4x melee).",
		min = 1,
		max = 10,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "marksmanThrown", table = mult }),
	})

	-- Stolen items page
	local stolen = template:createSideBarPage({ label = "Stolen Items", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(stolen)

	stolen:createYesNoButton({
		label = "Guard Detection (Stolen Items)",
		description = "Guards will attempt to detect stolen items on the player above a bounty threshold. Disabled by default as it is not yet fully polished.",
		configKey = "stolenItemsMechanic_Guard",
	})

	stolen:createYesNoButton({
		label = "Owner Detection (Stolen Items)",
		description = "Owners can detect items stolen from them when near the player. Disabled by default as it is not yet fully polished.",
		configKey = "stolenItemsMechanic_Owner",
	})

	stolen:createSlider({
		label = "Bounty Threshold",
		description = "Bounty above which guards will attempt to detect stolen items on the player.",
		min = 0,
		max = 1000,
		step = 10,
		configKey = "bountyThreshold",
	})

	stolen:createSlider({
		label = "Guard Max Detection Distance",
		description = "How close you must be to a guard for stolen item detection to trigger. Each unit is roughly 25 feet.",
		min = 1,
		max = 10,
		step = 1,
		configKey = "guardMaxDistance",
	})

	stolen:createSlider({
		label = "Lenience",
		description = "How easy it is to conceal stolen items. 0.5: very hard, 2.0: very easy.",
		min = 0.5,
		max = 2,
		step = 0.25,
		jump = 0.25,
		decimalPlaces = 2,
		configKey = "lenience",
	})

	stolen:createSlider({
		label = "Disposition Drop on Discovery",
		description = "How much disposition drops when the owner finds you with their stolen items.",
		min = 0,
		max = 100,
		step = 1,
		configKey = "dispositionDropOnDiscovery",
	})

	stolen:createSlider({
		label = "Guard Cooldown (seconds)",
		description = "Cooldown before a guard can scan you for stolen items again.",
		min = 1,
		max = 30,
		step = 1,
		configKey = "guardCooldownTime",
	})

	stolen:createSlider({
		label = "Owner Cooldown (seconds)",
		description = "Cooldown before an owner can scan you for stolen items again.",
		min = 1,
		max = 30,
		step = 1,
		configKey = "ownerCooldownTime",
	})
end

event.register(tes3.event.modConfigReady, registerModConfig)
