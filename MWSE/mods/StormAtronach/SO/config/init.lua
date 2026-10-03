local fileName = "Stealth_Overhaul"

---@class template.defaultConfig
local default = {
	modEnabled = true,
	setAlarmToThreshold = true,
	alarmThreshold = 50,
	stolenItemsTracking = false, -- scan the inventory for stolen goods after each pickup; off by default, cost grows with inventory size
	stolenItemsMechanic_Guard = false,
	stolenItemsMechanic_Owner = false,
	logLevel = mwse.logLevel.error,
	dispositionDropOnDiscovery = 20,
	bountyThreshold = 10,
	guardCooldownTime = 5,
	ownerCooldownTime = 5,
	guardMaxDistance = 4, -- in steps of 250 units (about 25 feet)
	lenience = 1.1,
	-- NPC AI scan interval (seconds)
	aiUpdateTime = 1,
	-- Seconds between forced engine detection re-checks for an actor at full suspicion with line of sight. 0 = every frame.
	engineRecheckInterval = 0.25,
	-- Suspicion model (0.0 to 1.0 per actor)
	baseRange = 1320, -- max detection range at sneak=0 (game units; 1320 = 60 ft)
	sneakPow = 1.2, -- power curve for sneak scaling (>1 = diminishing returns at high sneak)
	maxReduce = 75, -- how much sneak 100 shrinks detection range (%)
	distPow = 2.0, -- distance falloff exponent (2 = squared, sharper at close range)
	detCap = 1.0, -- max detection rate per second; keeps point-blank detection from being instant
	detFloor = 0.03, -- min detection rate within range; there is always some risk
	fillTime = 1.0, -- seconds to fill the bar at rate 1.0
	hidingBonus = 0.1, -- subtracted from the rate while standing still behind an actor and outside any light; 0 disables
	combatHidingTimer = 0, -- seconds after an enemy last saw the sneaking player before its suspicion may decay; 0 = as soon as it loses sight
	startStealthSuspicionMultiplier = 1, -- scales the suspicion seeded on nearby actors when the player starts sneaking
	combatDetectionMultiplier = 1, -- while the player is in combat, every actor with line of sight uses detCap * this as its rate
	-- Light mechanic
	lightMechanicEnabled = false, -- faster detection while the player stands inside an interior light's radius
	lightRateMult = 1.5, -- rate multiplier while in a light
	decayTime = 10, -- seconds to clear full suspicion (1->0) after decay delay
	suspicionDecayDelay = 3, -- seconds before decay begins after last increase
	stealSuspicionBonus = 50, -- suspicion added to a witness of an undetected theft, in percent; unused while onCrimeWitnessed is disabled
	-- HUD
	crosshairColorEnabled = true,
	keepVanillaCrosshair = false,
	crosshairScale = 1,
	crosshairAnimated = true,
	crosshairOpenSpeed = 6,
	crosshairCloseSpeed = 6,
	fillbarEnabled = false,
	markerEnabled = true,
	barRange = 2000, -- bars/markers only shown within this distance (units)
	eiInteropEnabled = true,
	eiCrosshairOnlyWhenSneaking = false,
	-- Sneak strike
	sneakStrikeEnabled = true,
	showSneakStrikeMessage = true, -- show the damage multiplier when a sneak strike lands
	sneakSkillMultEnabled = true,
	sneakSkillMultSteps = true, -- true = use nearest lower breakpoint; false = linear interpolation
	sneakSkillMult = { skill0 = 0.5, skill25 = 0.75, skill50 = 1.0, skill75 = 1.5, skill100 = 2.0 },
	-- Per-weapon sneak strike multipliers. They replace vanilla's bonus (4x melee, 1.5x ranged). Exactly 1.0 = knockout instead of bonus damage.
	sneakStrikeMult = {
		handToHand = 1.0, -- knockout
		shortBladeOneHand = 8.0,
		longBladeOneHand = 4.0,
		longBladeTwoClose = 3.0,
		bluntOneHand = 1.0, -- knockout
		bluntTwoClose = 2,
		bluntTwoWide = 1.0, -- knockout
		spearTwoWide = 2.0,
		axeOneHand = 3.0,
		axeTwoHand = 2.0,
		marksmanBow = 1.5,
		marksmanCrossbow = 1.5,
		marksmanThrown = 1.5,
	},
	-- Sneak XP
	detectionExpMultiplier = 1,
	stealItemExpMultiplier = 1,
	pickPocketExpMultiplier = 1,
	sneakStrikeExpMultiplier = 1,
	interopExpMultiplier = 1,
	containersGiveXP = true,
	bonusStealWindow = 0.5, -- extra seconds during which a nearby actor still counts for stealing XP
	-- Interop
	shakeOnDiscovered = true,
	shakeSpeed = 25.0,
	shakeSize = 1.5,
	-- Experimental: NPC investigation (walk to a suspicious spot, look around, return).
	-- The module is loaded only when this is on; it exposes investigation.startTravel /
	-- startWander through the interop table and has no in-game trigger of its own yet.
	experimentalInvestigation = false,
	wanderRangeInterior = 500, -- wander radius (units) at the investigated spot, interiors
	wanderRangeExterior = 2000, -- wander radius (units) at the investigated spot, exteriors
	minTravelTime = 1, -- seconds the NPC is given to reach the spot, lower bound
	maxTravelTime = 15, -- seconds the NPC is given to reach the spot, upper bound
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
