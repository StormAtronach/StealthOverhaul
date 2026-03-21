local config    = require("StormAtronach.SO.config")
local detection = require("StormAtronach.SO.detection")

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

--- Returns the current suspicion level (0.0–1.0) for the given actor reference ID.
---@param actorId string
---@return number
interop.getSuspicion = detection.getSuspicion

--- Adds suspicion to an actor, capped at 1.0. Restarts the decay delay timer.
---@param actorId string
---@param amount number  0.0–1.0
interop.addSuspicion = detection.addSuspicion

--- Clears all suspicion and tracking state for an actor immediately.
---@param actorId string
interop.clearSuspicion = detection.clearSuspicion

return interop
