local config = require("StormAtronach.GTV.config")
local interop = require("StormAtronach.GTV.interop")

local log = mwse.Logger.new({
	name = "Grand Theft Vvardenfell",
	level = config.logLevel,
})

local util = require("StormAtronach.GTV.util")
dofile("StormAtronach.GTV.mcm")

-- VARIABLES

-- Item pickup
---@param e activateEventData
local function onItemPickup(e)
	-- Check if the mod is enabled
    if not (config.enabled and interop.GTVenabled) then return end
	-- Check if the activator is the player
	if e.activator ~= tes3.player then return end
	-- Check if the reference is an item
	local item = e.target.object
	-- If it is not a carriable item, we do not care
	if not item.isCarriable then log:debug("Activator: %s, is carriable: %s", item.id, item.isCarriable) return end
   	-- Check if it has an owner
	local owner = tes3.getOwner({reference = e.target})
	if not (owner and owner.id) then log:trace("Item has no owner") return end


	-- We update the crime in the data:
	local aux 		= {} -- my dear auxiliary, can hold everything
	aux.ownerID = owner.id:lower()
	aux.itemID 	= item.id
	aux.size 	= util.getMaxSize(item) or 0
	aux.count 	= item.count or 0
	aux.value 	= tes3.getValue({item = item}) or 0
	util.updateData(aux)
	local timeStamp = tes3.getSimulationTimestamp()

	-- We update the current crime time and space data
	local currentCell 				= tes3.dataHandler.currentCell.id
	local currentCrime 				= data.currentCrime
	currentCrime.cells[currentCell] = timeStamp

	-- And we force-update the rest of current crime in the next frame
	timer.delayOneFrame(function() util.updateCurrentCrime() end)

end
event.register("activate", onItemPickup)



--[[ Detection mechanism
--- @param e detectSneakEventData
local function detectSneakCallback(e)
	if e.target ~= tes3.mobilePlayer then return end
	-- Detect if the player has stuff belonging to the owner. For that, I need a list of items populated by the owner? No, it is enough to store value I think. What about weight? Store it separately and clear it out? 
	-- Let's start with value and then on to more interesting stuff
	-- 

	-- 
	local sawYou = tes3.testLineOfSight({reference1 = e.detector.reference, reference2 = e.target.reference})





	--TESTING STUFF
	local detector = e.detector and e.detector.reference and e.detector.reference.id or "None"
	local messageText = string.format("Detected by: " .. detector)
	local timestamp = os.clock()
	print(string.format(messageText .. " at: %s", timestamp))
	tes3.messageBox({ message = messageText }) 
end
--]]

--- @param e loadedEventData
local function loadedCallback(e)
-- Housekeeping to be done while the mod loads:
	util.getData() -- Update or create the playerData container
	util.updateFactionList() -- Update or create the faction list
end

event.register(tes3.event.loaded, loadedCallback)
event.register(tes3.event.detectSneak, detectSneakCallback)