local fileName = "StormAtronach.GTV"

---@class template.defaultConfig
local default = {
	enabled = true,
	logLevel = mwse.logLevel.trace,
	detectionAngle = 80, -- degrees
	detectionCooldwon = 5, -- seconds, cooldown for stolen ITEMs check
	wanderRangeInterior = 500,
	wanderRangeExterior = 2000,
	minTravelTime 		= 1, -- seconds, minimum time that the NPC will travel to the destination while investigating
	maxTravelTime		= 15, -- seconds, maximum time that the NPC will travel to the destination
	---@type mwseKeyMouseCombo
	someKey = {
		keyCode = tes3.scanCode.p,
		isShiftDown = false,
		isAltDown = true,
		isControlDown = false,
	},
}

---@class template.config : template.defaultConfig
---@field version string A [semantic version](https://semver.org/).
---@field default template.defaultConfig Access to the default config can be useful in the MCM.
---@field fileName string

local config = mwse.loadConfig(fileName, default) --[[@as template.config]]
config.version = "0.1.0"
config.default = default
config.fileName = fileName

return config
