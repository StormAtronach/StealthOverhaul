local config = require("StormAtronach.SO.config")
local detection = require("StormAtronach.SO.detection")
local experience = require("StormAtronach.SO.experience")

---@class SA_SO_Interop
local interop = {}

--- Semantic version of the mod.
interop.version = config.version

--- Returns true if the mod is currently enabled.
---@return boolean
function interop.isEnabled()
	return config.modEnabled == true
end

--- Custom event names.
interop.events = {
	--- Fired when an NPC's suspicion reaches 1.0. Payload is the detectSneakEventData.
	detected = "SA_SO_detected",
}

--- Returns the current suspicion level (0.0-1.0) for the given actor reference. 0 if untracked.
---@param ref tes3reference
---@return number
function interop.getSuspicion(ref)
	return detection.getSuspicion(ref)
end

--- Adds suspicion to an actor, capped at 1.0. Restarts the decay delay timer.
---@param ref tes3reference
---@param amount number  0.0-1.0
function interop.addSuspicion(ref, amount)
	detection.addSuspicion(ref, amount)
end

--- Clears all suspicion and tracking state for an actor immediately.
---@param ref tes3reference
function interop.clearSuspicion(ref)
	detection.clearSuspicion(ref)
end

--- True if the actor fully detects the player or is fighting them. This is the gate the mod
--- uses for sneak strikes; prefer it over the engine's isPlayerDetected flag.
---@param mobile tes3mobileActor
---@return boolean
function interop.isDetectedBy(mobile)
	return detection.isDetectedBy(mobile)
end

--- Experimental NPC investigation (startTravel / startWander). nil unless
--- config.experimentalInvestigation is on.
interop.investigation = config.experimentalInvestigation and require("StormAtronach.SO.investigation") or nil


--- Stealth Overhaul blocks every other Sneak skill gain. Other mods call this to train Sneak for anything the mod does not already reward (sneaking near actors, stealing while sneaking, pickpocketing, sneak strikes).
--- @param amount number XP amount, as tes3.mobilePlayer:exerciseSkill would take it.
function interop.exerciseSneak(amount)
	experience.levelSneak(experience.Source.interop, amount)
end

return interop
