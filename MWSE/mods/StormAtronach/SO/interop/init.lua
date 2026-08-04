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

--- Returns the current suspicion level (0.0-1.0) for the given actor reference ID.
----@param actorId string
----@return number
interop.getSuspicion = detection.getSuspicion

--- Adds suspicion to an actor, capped at 1.0. Restarts the decay delay timer.
----@param actorId string
----@param amount number  0.0-1.0
interop.addSuspicion = detection.addSuspicion

--- Clears all suspicion and tracking state for an actor immediately.
----@param actorId string
interop.clearSuspicion = detection.clearSuspicion


--- As Stealth Overhaul takes control over leveling, you need to use this function to train the sneak skill in any other way than what is already covered by this mod (already covered includes: Just sneaking around, stealing stuff while sneaking, pickpocketing, and executing sneak strikes)
--- @param amount number The amount of experience to level Sneak. Mimics the ordinary tes3.exceciseSkill() function in amount actually trained.
function interop.exerciseSneak(amount) 
	experience.levelSneak(experience.Source.interop, amount)
end

return interop
