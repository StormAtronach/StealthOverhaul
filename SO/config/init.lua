local fileName = "Stealth_Overhaul"

---@class template.defaultConfig
local default = {
	modEnabled = true,
	stolenItemsMechanic_Guard = false,
	stolenItemsMechanic_Owner = false,
	logLevel = mwse.logLevel.error,
	dispositionDropOnDiscovery = 20,
	bountyThreshold = 10,
	guardCooldownTime = 5,
	ownerCooldownTime = 5,
	guardMaxDistance = 4, -- roughly 100 feet / 30 meters
	lenience = 1.1,
	-- AI update time
	aiUpdateTime = 1,
	-- Cumulative suspicion system (progress is 0.0–1.0)
	-- Detection model
	baseRange = 1320,   -- max detection range at sneak=0 (game units; 1320 = 60 ft)
	sneakPow = 1.2,     -- power curve for sneak scaling (>1 = diminishing returns at high sneak)
	maxReduce = 75,     -- how much sneak 100 shrinks detection range (%)
	distPow = 2.0,      -- distance falloff exponent (2 = squared, sharper at close range)
	detCap = 0.95,      -- max detection rate per second (prevents instant-fill)
	detFloor = 0.03,    -- min detection rate within range (prevents true invisibility)
	fillTime = 5.0,     -- seconds at rate=1.0 to fill bar from 0→100%
	-- Light mechanic
	lightMechanicEnabled = false, -- increase detection rate when player is inside a light source's radius
	lightRateMult = 2.0,          -- detection rate multiplier when player is in a light source (>1 = faster detection)
	decayTime = 15,             -- seconds to clear full suspicion (1→0) after decay delay
	suspicionDecayDelay = 5,    -- seconds before decay begins after last increase
	stealSuspicionBonus = 50,   -- bonus added on undetected theft (0–100 maps to 0.0–1.0 of progress)
	-- Stealth bar / marker display
	barRange = 2000,     -- bars/markers only shown within this distance (units)
	markerMinSize = 20,  -- marker size at 1% suspicion (game units)
	markerMaxSize = 60,  -- marker size at 100% suspicion (game units)
	-- Debug
	debugLines = false,
}

---@class template.config : template.defaultConfig
---@field version string A [semantic version](https://semver.org/).
---@field default template.defaultConfig Access to the default config can be useful in the MCM.
---@field fileName string

local config = mwse.loadConfig(fileName, default) --[[@as template.config]]
config.version = "1.4.0"
config.default = default
config.fileName = fileName

return config
