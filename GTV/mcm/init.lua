local config = require("StormAtronach.GTV.config")
local log = mwse.Logger.new()

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
		name = "Grand Theft Vvardenfell",
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

	page:createSlider({
		label = "Detection Angle",
		description = "The angle at which the player can be detected by NPCs.",
		min = 0,
		max = 180,
		defaultSetting = config and config.default and config.default.detectionAngle or 90,
		step = 1,
		configKey = "detectionAngle",
		postCreate = center,
	})


	page:createLogLevelOptions({
		configKey = "logLevel",
	})
end

event.register(tes3.event.modConfigReady, registerModConfig)
