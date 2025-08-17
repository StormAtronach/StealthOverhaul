local config = require("StormAtronach.SO.config")

local authors = {
	{
		name = "Storm Atronach",
		url = "https://next.nexusmods.com/profile/StormAtronach0",
	},
}


--- @param self mwseMCMInfo|mwseMCMHyperlink
local function center(self)
	self.elements.info.absolutePosAlignX = 0.5
end

--- Adds default text to sidebar. Has a list of all the authors that contributed to the mod.
--- @param container mwseMCMSideBarPage
local function createSidebar(container)
	container.sidebar:createInfo({
		text = "\nWelcome to Template Mod!\n\nHover over a feature for more info.\n\nMade by:",
		postCreate = center,
	})
	for _, author in ipairs(authors) do
		container.sidebar:createHyperlink({
			text = author.name,
			url = author.url,
			postCreate = center,
		})
	end
end

local function registerModConfig()
	local template = mwse.mcm.createTemplate({
		name = "Stealth Overhaul",
		--headerImagePath = "MWSE/mods/template/mcm/Header.tga",
		config = config,
		defaultConfig = config.default,
		showDefaultSetting = true,
	})
	template:register()
	template:saveOnClose(config.fileName, config)

	local page = template:createSideBarPage({
		label = "Settings",
		showReset = true,
	}) --[[@as mwseMCMSideBarPage]]
	createSidebar(page)

	page:createYesNoButton({
        label = "Enable Mod",
        description = "Enable or disable Stealth Overhaul.",
        configKey = "modEnabled",
        defaultSetting = config.default.modEnabled,
    })

    page:createLogLevelOptions({
        configKey = "logLevel",
    })

    page:createSlider({
        label = "Detection Angle",
        description = "The angle at which the player can be detected by NPCs.",
        min = 0,
        max = 180,
        step = 1,
        configKey = "detectionAngle",
        defaultSetting = config.default.detectionAngle,
        postCreate = center,
    })

    page:createSlider({
        label = "Detection Cooldown (seconds)",
        description = "Cooldown for stolen item checks.",
        min = 1,
        max = 30,
        step = 1,
        configKey = "detectionCooldown",
        defaultSetting = config.default.detectionCooldown,
    })

    page:createSlider({
        label = "Disposition Drop on Discovery",
        description = "How much disposition drops when discovered.",
        min = 0,
        max = 100,
        step = 1,
        configKey = "dispositionDropOnDiscovery",
        defaultSetting = config.default.dispositionDropOnDiscovery,
    })

    page:createSlider({
        label = "Wander Range (Interior)",
        description = "How far NPCs wander when investigating (interior).",
        min = 100,
        max = 2000,
        step = 50,
        configKey = "wanderRangeInterior",
        defaultSetting = config.default.wanderRangeInterior,
    })

    page:createSlider({
        label = "Wander Range (Exterior)",
        description = "How far NPCs wander when investigating (exterior).",
        min = 500,
        max = 5000,
        step = 100,
        configKey = "wanderRangeExterior",
        defaultSetting = config.default.wanderRangeExterior,
    })

    page:createSlider({
        label = "Guard Cooldown Time (seconds)",
        description = "Cooldown before guards can detect you again.",
        min = 1,
        max = 30,
        step = 1,
        configKey = "guardCooldownTime",
        defaultSetting = config.default.guardCooldownTime,
    })

    page:createSlider({
        label = "Owner Cooldown Time (seconds)",
        description = "Cooldown before owners can detect you again.",
        min = 1,
        max = 30,
        step = 1,
        configKey = "ownerCooldownTime",
        defaultSetting = config.default.ownerCooldownTime,
    })

    page:createSlider({
        label = "Sneak Skill Multiplier",
        description = "Multiplier for sneak skill in detection calculations.",
        min = 50,
        max = 200,
        step = 5,
        configKey = "sneakSkillMult",
        defaultSetting = config.default.sneakSkillMult,
    })

    page:createSlider({
        label = "Boot Multiplier",
        description = "Penalty for wearing heavier boots.",
        min = 0,
        max = 50,
        step = 1,
        configKey = "bootMultiplier",
        defaultSetting = config.default.bootMultiplier,
    })

    page:createSlider({
        label = "Sneak Distance Base",
        description = "Base value for sneak distance calculations.",
        min = 0,
        max = 200,
        step = 1,
        configKey = "sneakDistanceBase",
        defaultSetting = config.default.sneakDistanceBase,
    })

    page:createSlider({
        label = "Sneak Distance Multiplier",
        description = "Multiplier for sneak distance calculations.",
        min = 100,
        max = 2000,
        step = 50,
        configKey = "sneakDistanceMultiplier",
        defaultSetting = config.default.sneakDistanceMultiplier,
    })

    page:createSlider({
        label = "Invisibility Bonus",
        description = "Bonus to sneaking while invisible.",
        min = 0,
        max = 100,
        step = 1,
        configKey = "invisibilityBonus",
        defaultSetting = config.default.invisibilityBonus,
    })

    page:createSlider({
        label = "NPC Sneak Bonus",
        description = "Bonus to NPCs' sneak detection.",
        min = 0,
        max = 100,
        step = 1,
        configKey = "npcSneakBonus",
        defaultSetting = config.default.npcSneakBonus,
    })

    page:createSlider({
        label = "View Multiplier",
        description = "Multiplier for NPC visual detection.",
        min = 1,
        max = 10,
        step = 1,
        configKey = "viewMultiplier",
        defaultSetting = config.default.viewMultiplier,
    })

    page:createSlider({
        label = "Hearing Multiplier",
        description = "Multiplier for NPC hearing detection.",
        min = 1,
        max = 10,
        step = 1,
        configKey = "hearingMultiplier",
        defaultSetting = config.default.hearingMultiplier,
    })

    page:createSlider({
        label = "Sneak Difficulty",
        description = "Difficulty threshold for sneaking.",
        min = 0,
        max = 200,
        step = 1,
        configKey = "sneakDifficulty",
        defaultSetting = config.default.sneakDifficulty,
    })

    page:createSlider({
        label = "Min Travel Time (seconds)",
        description = "Minimum time NPCs travel while investigating.",
        min = 1,
        max = 30,
        step = 1,
        configKey = "minTravelTime",
        defaultSetting = config.default.minTravelTime,
    })

    page:createSlider({
        label = "Max Travel Time (seconds)",
        description = "Maximum time NPCs travel while investigating.",
        min = 5,
        max = 60,
        step = 1,
        configKey = "maxTravelTime",
        defaultSetting = config.default.maxTravelTime,
    })


	page:createLogLevelOptions({
		configKey = "logLevel",
	})
end

event.register(tes3.event.modConfigReady, registerModConfig)
