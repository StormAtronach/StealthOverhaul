local config = require("StormAtronach.SO.config")
local eiInterop = require("StormAtronach.SO.eiInterop")

local authors = {
	{ name = "Storm Atronach", url = "https://next.nexusmods.com/profile/StormAtronach0" },
	{ name = "Rhjelte", url = "https://www.nexusmods.com/profile/rhjelte" },
}

--- @param self mwseMCMInfo|mwseMCMHyperlink
local function center(self)
	self.elements.info.absolutePosAlignX = 0.5
end

--- Adds default text to sidebar. Has a list of all the authors that contributed to the mod.
--- @param container mwseMCMSideBarPage
local function createSidebar(container)
	container.sidebar:createInfo({
		text = "\nStealth Overhaul\n\nHover over a setting for details.\n\nMade by:",
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
		label = "Enable mod",
		description = "Turn the whole mod on or off.",
		configKey = "modEnabled",
		callback = function()
			eiInterop.toggleEssentialIndicatorCrosshair()
		end,
	})

	page:createLogLevelOptions({ configKey = "logLevel" })

	page:createSlider({
		label = "AI scan interval (seconds)",
		description = "Seconds between NPC AI scans. The mod is tuned for 1. Lower is more responsive and costs more per frame.",
		min = 1,
		max = 5,
		step = 1,
		configKey = "aiUpdateTime",
	})

	page:createOnOffButton({
		label = "Set alarm to threshold when NPCs load in",
		description = "Raise each NPC's AI Alarm to the threshold below when it loads, so NPCs with a low Alarm still react to theft.",
		configKey = "setAlarmToThreshold"
	})

	page:createSlider({
		label = "Alarm threshold",
		description = "The Alarm value NPCs are raised to when the option above is on. NPCs already above it are left alone.",
		min = 0,
		max = 100,
		step = 1,
		configKey = "alarmThreshold",
	})

	-- Detection page
	local detection = template:createSideBarPage({ label = "Detection", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(detection)

	detection:createCategory({ label = "Detection model" })

	detection:createSlider({
		label = "Base detection range (units)",
		description = "How far an NPC can detect you at Sneak 0. 1320 units is 60 feet.",
		min = 200,
		max = 4000,
		step = 100,
		configKey = "baseRange",
	})

	detection:createSlider({
		label = "Max range reduction (%)",
		description = "How much Sneak 100 shrinks that range. At 75, a master sneaker can only be detected within a quarter of the base range.",
		min = 10,
		max = 95,
		step = 5,
		configKey = "maxReduce",
	})

	detection:createSlider({
		label = "Sneak skill curve",
		description = "Shape of the Sneak skill's effect on range. 1.0 is linear. Above 1.0, each point matters less at high Sneak. Default 1.2.",
		min = 0.5,
		max = 3.0,
		step = 0.1,
		jump = 0.1,
		decimalPlaces = 1,
		configKey = "sneakPow",
	})

	detection:createSlider({
		label = "Distance falloff curve",
		description = "How fast detection drops with distance. 1.0 is linear. 2.0 is squared, so close range is far more dangerous than mid range. Default 2.0.",
		min = 1.0,
		max = 4.0,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		configKey = "distPow",
	})

	detection:createSlider({
		label = "Fill time (seconds)",
		description = "Seconds to fill the suspicion bar from empty at the maximum rate. Lower means faster detection everywhere.",
		min = 1.0,
		max = 20.0,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		configKey = "fillTime",
	})

	detection:createSlider({
		label = "Detection rate cap",
		description = "Highest detection rate per second, 0 to 1. Keeps point-blank detection from being instant. Default 1.0.",
		min = 0.1,
		max = 1.0,
		step = 0.05,
		jump = 0.05,
		decimalPlaces = 2,
		configKey = "detCap",
	})

	detection:createSlider({
		label = "Detection rate floor",
		description = "Lowest detection rate while you are inside an NPC's range. Above 0 there is always some risk. Default 0.03.",
		min = 0.0,
		max = 0.2,
		step = 0.01,
		jump = 0.01,
		decimalPlaces = 2,
		configKey = "detFloor",
	})

	detection:createSlider({
		label = "Engine re-check interval (seconds)",
		description = "While an actor fully detects you and can see you, the mod re-runs the engine's own detection check so the actor reacts without waiting for its next AI scan. This is the gap between those checks, per actor. 0 is every frame: the most responsive, and the most expensive in a crowded cell. Default 0.25.",
		min = 0,
		max = 2,
		step = 0.05,
		jump = 0.05,
		decimalPlaces = 2,
		configKey = "engineRecheckInterval",
	})

	detection:createCategory({ label = "Light mechanic" })

	detection:createYesNoButton({
		label = "Enable light mechanic (experimental, off by default)",
		description = "Detection builds faster while you stand inside a light source's radius in an interior. Campfires and fireplaces work well. It misses some light sources and ignores lights that mods such as Douse the Lights or Midnight Oil switch on and off, which is why it is off by default.",
		configKey = "lightMechanicEnabled",
	})

	detection:createSlider({
		label = "Light rate multiplier",
		description = "Detection rate multiplier while you stand in a light. 2.0 doubles it. Only used when the light mechanic is on.",
		min = 1.0,
		max = 5.0,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		configKey = "lightRateMult",
	})

	detection:createCategory({ label = "Suspicion decay" })

	detection:createSlider({
		label = "Decay time (seconds)",
		description = "Seconds for full suspicion to fall to zero once decay starts. Higher keeps NPCs alert longer.",
		min = 1,
		max = 60,
		step = 1,
		configKey = "decayTime",
	})

	detection:createSlider({
		label = "Decay delay (seconds)",
		description = "Seconds after the last suspicion increase before decay starts. Keeps NPCs alert for a moment after you step out of range.",
		min = 0,
		max = 60,
		step = 1,
		configKey = "suspicionDecayDelay",
	})

	detection:createSlider({
		label = "Hiding bonus",
		description = "Standing still behind an NPC, outside any light, subtracts this from the rate at which its suspicion rises. Large values can make suspicion fall even while you are in range. 0 turns it off.",
		min = 0,
		max = 0.4,
		step = 0.01,
		decimalPlaces = 2,
		configKey = "hidingBonus",
	})

	detection:createSlider({
		label = "Combat hiding timer (seconds)",
		description = "An enemy fighting you stays fully aware while it can see you, which means you are not sneaking or it has line of sight. This is how many seconds after it last saw you, while you sneak, before its suspicion may start to fall. 0 means it starts falling as soon as it loses sight of you. When suspicion reaches zero the enemy gives up the fight.",
		min = 0,
		max = 5,
		step = 1,
		configKey = "combatHidingTimer",
	})

	detection:createSlider({
		label = "Combat detection multiplier",
		description = "While you are fighting anyone, every other actor's detection rate is the rate cap times this value. The intent is that you cannot hide mid-fight. Set it below 1 to make that easier.",
		min = 0,
		max = 2,
		step = 0.1,
		decimalPlaces = 1,
		configKey = "combatDetectionMultiplier",
	})

	detection:createSlider({
		label = "Start stealth suspicion multiplier",
		description = "When you crouch, each actor that can see you starts with some suspicion, based on whether you are in front of it and on your Sneak skill. This scales that starting value.",
		min = 0.1,
		max = 2,
		step = 0.1,
		decimalPlaces = 1,
		configKey = "startStealthSuspicionMultiplier",
	})

	detection:createCategory({ label = "Interop" })

	detection:createOnOffButton({
		label = "Camera shake when discovered (Modernized 1st Person Experience)",
		description = "Shake the camera when an actor fully detects you while you sneak. Needs Modernized 1st Person Experience.",
		configKey = "shakeOnDiscovered"
	})

	detection:createSlider({
		label = "Camera shake size",
		description = "Strength of that shake.",
		min = 0.5,
		max = 3,
		step = 0.1,
		decimalPlaces = 2,
		configKey = "shakeSize",
	})

	detection:createSlider({
		label = "Camera shake speed",
		description = "Speed of that shake.",
		min = 15,
		max = 40,
		step = 0.1,
		decimalPlaces = 1,
		configKey = "shakeSpeed",
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

	-- HUD page
	local hud = template:createSideBarPage({ label = "HUD", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(hud)

	hud:createCategory({ label = "Crosshair" })

	hud:createYesNoButton({
		label = "Sneak eye crosshair",
		description = "While you sneak, replaces the crosshair with an eye that opens as suspicion rises: shut at 0, fully open at 1. It shows the highest suspicion among nearby actors. Once the eye is fully open, enemies in sight will attack you and bystanders in sight will report crimes they see.",
		configKey = "crosshairColorEnabled",
		callback = function()
			eiInterop.toggleEssentialIndicatorCrosshair()
		end,
	})

	hud:createSlider({
		label = "Sneak eye scale",
		description = "Size of the eye. 1.0 is the drawn size, 2.0 is double.",
		min = 0.1,
		max = 2,
		step = 0.1,
		decimalPlaces = 1,
		configKey = "crosshairScale",
		callback = function()
			event.trigger("SA_SO_crosshairRecreate")
			eiInterop.rescaleEiIndicator()
		end,
	})

	hud:createYesNoButton({
		label = "Keep vanilla crosshair",
		description = "Leave the vanilla crosshair dot visible under the eye. Off hides the dot while the eye is shown.",
		configKey = "keepVanillaCrosshair",
	})

	hud:createYesNoButton({
		label = "Animate crosshair transitions",
		description = "Animate the eye between its five stages instead of snapping.",
		configKey = "crosshairAnimated",
	})

	hud:createSlider({
		label = "Crosshair opening speed",
		description = "How fast the eye opens as suspicion rises. The default of 6 takes about half a second per stage.",
		min = 1,
		max = 20,
		step = 1,
		configKey = "crosshairOpenSpeed",
	})

	hud:createSlider({
		label = "Crosshair closing speed",
		description = "How fast the eye closes as suspicion falls. The default of 6 takes about half a second per stage.",
		min = 1,
		max = 20,
		step = 1,
		configKey = "crosshairCloseSpeed",
	})

	hud:createCategory({ label = "Suspicion indicators" })

	hud:createYesNoButton({
		label = "Suspicion markers",
		description = "Show an eye above each nearby NPC while you sneak. It opens as that NPC's suspicion rises, so you can see who is about to notice you.",
		configKey = "markerEnabled",
	})

	hud:createYesNoButton({
		label = "Suspicion fill bars (debug)",
		description = "Show a suspicion bar above each nearby NPC while you sneak. Meant for debugging. Off by default.",
		configKey = "fillbarEnabled",
	})



	hud:createSlider({
		label = "Display range (units)",
		description = "Markers and bars are only shown for NPCs within this distance. Only applies while sneaking.",
		min = 500,
		max = 5000,
		step = 100,
		configKey = "barRange",
	})

	hud:createCategory({ label = "Interop"})

	hud:createYesNoButton({
		label = "Essential Indicators interop",
		description = "With Essential Indicators 1.7 or newer installed, keep all of its behaviour but draw its crosshair in the sneak eye's style.",
		configKey = "eiInteropEnabled",
		callback = function()
			eiInterop.toggleEssentialIndicatorCrosshair()
		end,
	})

	hud:createYesNoButton({
		label = "Only override the Essential Indicators crosshair while sneaking",
		description = "Only swap in the sneak eye style while you sneak, so you can use any other crosshair the rest of the time. Does nothing unless the interop above is on.",
		configKey = "eiCrosshairOnlyWhenSneaking",
		callback = function()
			eiInterop.toggleEssentialIndicatorCrosshair()
		end,
	})

	-- Sneak Strike page
	local strike = template:createSideBarPage({ label = "Sneak strike", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(strike)

	strike:createYesNoButton({
		label = "Enable sneak strike",
		description = "Turn the sneak strike system on or off. Off means vanilla sneak attacks.",
		configKey = "sneakStrikeEnabled",
	})

	strike:createYesNoButton({
		label = "Show sneak strike message",
		description = "Show the damage multiplier when a sneak strike lands.",
		configKey = "showSneakStrikeMessage",
	})

	strike:createCategory({ label = "Non-lethal knockout" })
	strike:createInfo({
		text = "A weapon whose multiplier is exactly 1.0 knocks out instead of dealing bonus damage. Your skill with that weapon is checked against the target's helmet weight. On success the target loses all fatigue and drops out of combat.",
	})

	strike:createCategory({ label = "Sneak skill scaling" })
	strike:createInfo({
		text = "Sneak strike damage is also multiplied by a factor from your Sneak skill. The final multiplier never drops below 1.0, so a low skill means no bonus rather than a penalty. Knockout weapons, those set to exactly 1.0, ignore skill scaling.",
	})

	strike:createYesNoButton({
		label = "Enable skill scaling",
		description = "Multiply sneak strike damage by the Sneak skill factor set with the breakpoints below.",
		configKey = "sneakSkillMultEnabled",
	})

	strike:createYesNoButton({
		label = "Step mode",
		description = "Use the value of the nearest breakpoint at or below your skill, so Sneak 60 uses the Sneak 50 value, as in Oblivion. Off interpolates between breakpoints.",
		configKey = "sneakSkillMultSteps",
	})

	local skillMult = config.sneakSkillMult
	strike:createSlider({
		label = "Multiplier at Sneak 0",
		min = 0.1,
		max = 4.0,
		step = 0.05,
		jump = 0.05,
		decimalPlaces = 2,
		variable = mwse.mcm.createTableVariable({ id = "skill0", table = skillMult }),
	})
	strike:createSlider({
		label = "Multiplier at Sneak 25",
		min = 0.1,
		max = 4.0,
		step = 0.05,
		jump = 0.05,
		decimalPlaces = 2,
		variable = mwse.mcm.createTableVariable({ id = "skill25", table = skillMult }),
	})
	strike:createSlider({
		label = "Multiplier at Sneak 50",
		min = 0.1,
		max = 4.0,
		step = 0.05,
		jump = 0.05,
		decimalPlaces = 2,
		variable = mwse.mcm.createTableVariable({ id = "skill50", table = skillMult }),
	})
	strike:createSlider({
		label = "Multiplier at Sneak 75",
		min = 0.1,
		max = 4.0,
		step = 0.05,
		jump = 0.05,
		decimalPlaces = 2,
		variable = mwse.mcm.createTableVariable({ id = "skill75", table = skillMult }),
	})
	strike:createSlider({
		label = "Multiplier at Sneak 100",
		min = 0.1,
		max = 4.0,
		step = 0.05,
		jump = 0.05,
		decimalPlaces = 2,
		variable = mwse.mcm.createTableVariable({ id = "skill100", table = skillMult }),
	})

	-- Weapon Multipliers page
	local weapons = template:createSideBarPage({ label = "Weapon multipliers", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(weapons)

	weapons:createInfo({
		text = "A multiplier of exactly 1.0 means no bonus damage: the weapon knocks out instead. Your skill with the weapon is checked against the target's helmet weight, and on success the target loses all fatigue and drops out of combat.\n\nThese multipliers replace vanilla's sneak bonus (4x melee, 1.5x ranged).",
	})

	local mult = config.sneakStrikeMult
	local nonLethalNote = "Set to 1.0 to knock out instead of dealing bonus damage."

	weapons:createCategory({ label = "Unarmed" })
	weapons:createSlider({
		label = "Hand to Hand",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "handToHand", table = mult }),
	})

	weapons:createCategory({ label = "Blades" })
	weapons:createSlider({
		label = "Short Blade: Dagger, Tanto, Wakizashi",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "shortBladeOneHand", table = mult }),
	})
	weapons:createSlider({
		label = "Long Blade (1H): Saber, Katana, Broadsword",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "longBladeOneHand", table = mult }),
	})
	weapons:createSlider({
		label = "Long Blade (2H): Claymore, Dai-Katana",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "longBladeTwoClose", table = mult }),
	})

	weapons:createCategory({ label = "Blunt" })
	weapons:createSlider({
		label = "Blunt (1H): Club, Mace, Morning Star",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "bluntOneHand", table = mult }),
	})
	weapons:createSlider({
		label = "Blunt (2H): Warhammer, Maul",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "bluntTwoClose", table = mult }),
	})
	weapons:createSlider({
		label = "Blunt (2H Wide): Staff",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "bluntTwoWide", table = mult }),
	})

	weapons:createCategory({ label = "Other melee" })
	weapons:createSlider({
		label = "Spear: Spear, Lance, Halberd",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "spearTwoWide", table = mult }),
	})
	weapons:createSlider({
		label = "Axe (1H): Axe, Hatchet",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "axeOneHand", table = mult }),
	})
	weapons:createSlider({
		label = "Axe (2H): Battle Axe, War Axe",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "axeTwoHand", table = mult }),
	})

	weapons:createCategory({ label = "Ranged (vanilla bonus 1.5x)" })
	weapons:createSlider({
		label = "Bow: Short Bow, Long Bow",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "marksmanBow", table = mult }),
	})
	weapons:createSlider({
		label = "Crossbow",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "marksmanCrossbow", table = mult }),
	})
	weapons:createSlider({
		label = "Thrown: Dart, Throwing Star, Throwing Knife",
		description = nonLethalNote,
		min = 1,
		max = 16,
		step = 0.5,
		jump = 0.5,
		decimalPlaces = 1,
		variable = mwse.mcm.createTableVariable({ id = "marksmanThrown", table = mult }),
	})

	-- Experience tweak page
	local experiencePage = template:createSideBarPage({ label = "Experience", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(experiencePage)

	experiencePage:createSlider({
		label = "XP multiplier: avoiding detection",
		description = "Each second you spend inside someone's detection range without being fully seen earns a little Sneak XP. This scales it.",
		step = 0.1,
		decimalPlaces = 1,
		min = 0,
		max = 5,
		configKey = "detectionExpMultiplier"
	})

	experiencePage:createSlider({
		label = "XP multiplier: pickpocketing",
		description = "XP for each pickpocket, scaled by this. Does nothing if Mort's Pickpocket is installed; that mod hands out the XP instead.",
		step = 0.1,
		decimalPlaces = 1,
		min = 0,
		max = 5,
		configKey = "pickPocketExpMultiplier"
	})

	experiencePage:createSlider({
		label = "XP multiplier: sneak strikes",
		description = "XP for each sneak strike that lands, scaled by this.",
		step = 0.1,
		decimalPlaces = 1,
		min = 0,
		max = 5,
		configKey = "sneakStrikeExpMultiplier"
	})

	experiencePage:createSlider({
		label = "XP multiplier: other mods",
		description = "XP that other mods, such as Sneaky Snatcher, grant through this mod's interop, scaled by this.",
		step = 0.1,
		decimalPlaces = 1,
		min = 0,
		max = 5,
		configKey = "interopExpMultiplier"
	})

	experiencePage:createOnOffButton({
		label = "Owned containers give XP",
		description = "Opening an owned container while sneaking and unseen gives XP as if you stole an item, once per cell visit. Easy to exploit, so you can turn it off.",
		configKey = "containersGiveXP"
	})

	experiencePage:createSlider({
		label = "Extra time in the stealing XP window (seconds)",
		description = "Stealing only gives XP if someone was close enough to catch you. An NPC counts for one and a half AI scan periods plus half a second after it last checked on you, which is 3.5 seconds at the default scan interval. This adds seconds to that window.\n\n0 or 1 is recommended.",
		step = 0.1,
		decimalPlaces = 1,
		min = 0,
		max = 2,
		configKey = "bonusStealWindow"
	})

	-- Stolen items page
	local stolen = template:createSideBarPage({ label = "Stolen items", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(stolen)

	stolen:createYesNoButton({
		label = "Track stolen items",
		description = "Scan your inventory for stolen goods after each pickup so the two mechanics below have current data. Off by default. The scan's cost grows with inventory size, and the mechanics below do nothing without it.",
		configKey = "stolenItemsTracking",
	})

	stolen:createYesNoButton({
		label = "Guard detection",
		description = "Guards near you may notice stolen goods once your bounty is above the threshold below. Off by default; not finished.",
		configKey = "stolenItemsMechanic_Guard",
	})

	stolen:createYesNoButton({
		label = "Owner detection",
		description = "An NPC near you may notice goods stolen from them. Off by default; not finished.",
		configKey = "stolenItemsMechanic_Owner",
	})

	stolen:createSlider({
		label = "Bounty threshold",
		description = "Guards only check you for stolen goods when your bounty is above this.",
		min = 0,
		max = 1000,
		step = 10,
		configKey = "bountyThreshold",
	})

	stolen:createSlider({
		label = "Guard max detection distance",
		description = "How close a guard must be to check you. Each step is about 25 feet.",
		min = 1,
		max = 10,
		step = 1,
		configKey = "guardMaxDistance",
	})

	stolen:createSlider({
		label = "Lenience",
		description = "How easy stolen goods are to hide. 0.5 is very hard, 2.0 very easy.",
		min = 0.5,
		max = 2,
		step = 0.25,
		jump = 0.25,
		decimalPlaces = 2,
		configKey = "lenience",
	})

	stolen:createSlider({
		label = "Disposition drop on discovery",
		description = "How much an owner's disposition falls when they catch you with their goods.",
		min = 0,
		max = 100,
		step = 1,
		configKey = "dispositionDropOnDiscovery",
	})

	stolen:createSlider({
		label = "Guard cooldown (seconds)",
		description = "Seconds before a guard can check you again.",
		min = 1,
		max = 30,
		step = 1,
		configKey = "guardCooldownTime",
	})

	stolen:createSlider({
		label = "Owner cooldown (seconds)",
		description = "Seconds before an owner can check you again.",
		min = 1,
		max = 30,
		step = 1,
		configKey = "ownerCooldownTime",
	})

	-- Experimental page
	local experimental = template:createSideBarPage({ label = "Experimental", showReset = true }) --[[@as mwseMCMSideBarPage]]
	createSidebar(experimental)

	experimental:createCategory({ label = "NPC investigation" })
	experimental:createInfo({
		text = "Unfinished. Sends an NPC to a suspicious spot to look around, then back. Nothing in the mod triggers it yet; other mods can call it through the interop table. Needs a restart to load or unload.",
	})

	experimental:createYesNoButton({
		label = "Load investigation module",
		description = "Load the module at startup and expose it as interop.investigation. Takes effect after a restart.",
		configKey = "experimentalInvestigation",
	})

	experimental:createSlider({
		label = "Wander range, interiors (units)",
		description = "How far the NPC wanders around the spot in interior cells.",
		min = 100,
		max = 2000,
		step = 50,
		configKey = "wanderRangeInterior",
	})

	experimental:createSlider({
		label = "Wander range, exteriors (units)",
		description = "How far the NPC wanders around the spot in exterior cells.",
		min = 100,
		max = 5000,
		step = 100,
		configKey = "wanderRangeExterior",
	})

	experimental:createSlider({
		label = "Minimum travel time (seconds)",
		description = "Least time an NPC gets to reach the spot before it gives up.",
		min = 1,
		max = 30,
		step = 1,
		configKey = "minTravelTime",
	})

	experimental:createSlider({
		label = "Maximum travel time (seconds)",
		description = "Most time an NPC gets to reach the spot before it gives up.",
		min = 1,
		max = 60,
		step = 1,
		configKey = "maxTravelTime",
	})
end

event.register(tes3.event.modConfigReady, registerModConfig)
