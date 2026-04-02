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
	baseRange = 1320, -- max detection range at sneak=0 (game units; 1320 = 60 ft)
	sneakPow = 1.2, -- power curve for sneak scaling (>1 = diminishing returns at high sneak)
	maxReduce = 75, -- how much sneak 100 shrinks detection range (%)
	distPow = 2.0, -- distance falloff exponent (2 = squared, sharper at close range)
	detCap = 1.0, -- max detection rate per second (prevents instant-fill)
	detFloor = 0.03, -- min detection rate within range (prevents true invisibility)
	fillTime = 1.0, -- seconds at rate=1.0 to fill bar from 0→100%
	-- Light mechanic
	lightMechanicEnabled = true, -- increase detection rate when player is inside a light source's radius
	lightRateMult = 2.0, -- detection rate multiplier when player is in a light source (>1 = faster detection)
	decayTime = 10, -- seconds to clear full suspicion (1→0) after decay delay
	suspicionDecayDelay = 3, -- seconds before decay begins after last increase
	stealSuspicionBonus = 50, -- bonus added on undetected theft (0–100 maps to 0.0–1.0 of progress)
	-- Stealth bar / marker display
	crosshairColorEnabled = true,
	keepVanillaCrosshair = false,
	crosshairSize = 4.0,
	crosshairAnimated = true,
	crosshairOpenSpeed = 6,
	crosshairCloseSpeed = 6,
	fillbarEnabled = false,
	markerEnabled = true,
	barRange = 2000, -- bars/markers only shown within this distance (units)
	markerMinSize = 10, -- marker size at 1% suspicion (game units)
	markerMaxSize = 30, -- marker size at 100% suspicion (game units)
	-- Sneak strike
	sneakStrikeEnabled = true,
	showSneakStrikeMessage = true, -- show a messageBox with the damage multiplier on a sneak strike
	sneakSkillMultEnabled = true,
	sneakSkillMultSteps = true, -- true = use nearest lower breakpoint; false = linear interpolation
	sneakSkillMult = { skill0 = 0.5, skill25 = 0.75, skill50 = 1.0, skill75 = 1.5, skill100 = 2.0 },
	-- Per-weapon sneak strike multipliers (applied after undoing vanilla's 4x)
	sneakStrikeMult = {
		handToHand = 1.0, -- non-lethal by default, no damage bonus
		shortBladeOneHand = 8.0,
		longBladeOneHand = 4.0,
		longBladeTwoClose = 3.0,
		bluntOneHand = 1.0, -- non-lethal by default
		bluntTwoClose = 2,
		bluntTwoWide = 1.0, -- non-lethal by default
		spearTwoWide = 2.0,
		axeOneHand = 3.0,
		axeTwoHand = 2.0,
		marksmanBow = 1.5,
		marksmanCrossbow = 1.5,
		marksmanThrown = 1.5,
	},
	-- Debug
	debugLines = false,
}

---@class template.config : template.defaultConfig
---@field version string A [semantic version](https://semver.org/).
---@field default template.defaultConfig Access to the default config can be useful in the MCM.
---@field fileName string

local config = mwse.loadConfig(fileName, default) --[[@as template.config]]

-- Migrate stale flat sneakSkillMult value (was a number in older versions)
if type(config.sneakSkillMult) ~= "table" then
	config.sneakSkillMult = default.sneakSkillMult
end

config.version = "2.0.0"
config.default = default
config.fileName = fileName

return config
