local config = require("StormAtronach.SO.config")
local interop = require("StormAtronach.SO.interop")
local util = require("StormAtronach.SO.util.")
local investigation = require("StormAtronach.SO.investigation")

local log = mwse.Logger.new({
	name = "Stealth Overhaul",
	level = config.logLevel,
})

dofile("StormAtronach.SO.mcm")

-- VARIABLES



-- Housekeeping

local function forceStealthCheck(e)
	if config.modEnabled then
		tes3.worldController.mobManager.processManager:detectPresence(tes3.mobilePlayer, true)
	end
end

---@param e loadEventData
local function onLoad(e)
	npcsTracking = {} 		 -- clean up the npcsTracking table
	util.getData() 			 -- Update or create the playerData container
	util.updateFactionList() -- Update or create the faction list
	timer.start({type = timer.simulate, callback = "forceStealthCheck", duration = 2, iterations = -1})
end
event.register(tes3.event.loaded,onLoad)



--- Updating the list of stolen items
--- @param e itemTileUpdatedEventData
local function itemTileUpdatedCallback(e)
-- Don't do stuff in the menu, only when picking up things in the world
if tes3ui.menuMode() then return end
util.updateCurrentCrime()
end
event.register(tes3.event.itemTileUpdated, itemTileUpdatedCallback)

-- Also update when closing menu mode. Hopefully this also fires when closing a container
--- @param e menuExitEventData
local function menuExitCallback(e)
		util.updateCurrentCrime()
end
event.register(tes3.event.menuExit, menuExitCallback)


















--- @param e attackHitEventData
local function attackHitCallback(e)
if e.reference ~= tes3.player then return end
if not tes3.mobilePlayer.isSneaking then return end
--e.targetMobile:hitStun({knockDown = true})
e.targetMobile:applyFatigueDamage(3000)
local victim = e.targetMobile
timer.delayOneFrame(function() if victim then victim:stopCombat(true) end end)
end
event.register(tes3.event.attackHit, attackHitCallback)


--event.register(tes3.event.detectSneak, detectSneakCallback)
