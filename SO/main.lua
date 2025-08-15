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
local guardCooldown = 0
local npcCooldown = {}


-- Housekeeping

local function forceStealthCheck(e)
		tes3.worldController.mobManager.processManager:detectPresence(tes3.mobilePlayer, true)
end

---@param e loadEventData
local function onLoad(e)
	npcCooldown = {} 		 -- Clean up the npcsTracking table
	guardCooldown = 0		 -- Reset the guard cooldown
	util.getData() 			 -- Update or create the playerData container
	util.updateFactionList() -- Update or create the faction list
	timer.start({type = timer.simulate, callback = "forceStealthCheck", duration = 2, iterations = -1})
end
event.register(tes3.event.loaded,onLoad)

--- Got caught stealing? Let's roll the dice and see what happens
--- @param e detectSneakEventData
local function detected(e)
	local data = util.getData()
	-- If there is not current crime, do nothing
	if (data.currentCrime.size == 0) and (data.currentCrime.value == 0) then return end

	--- Guard detection stream
	local cooldownActive = (tes3.getSimulationTimestamp(false) - guardCooldown) < (config.guardCooldownTime or 5)
	if e.detector.object.isGuard and (not cooldownActive) then
		-- Basic score taking into account player sneak and security
		local playerScore = math.clamp(tes3.mobilePlayer.sneak.current + tes3.mobilePlayer.security.current,0,250)
		-- Distance term
		local distanceTerm = math.clamp(e.detector.position:distance(tes3.player.position)/250,0.5,5)
		playerScore = playerScore * distanceTerm
		local detectionChance = math.clamp(math.round(100*data.currentCrime.size / playerScore, 0),0,100)
		local check = detectionChance >= math.random(5,95) -- Easter egg, let's see if anyone reads the code. this would be nice for perks, though
		if check then
			util.gotCaughtGuard()
		else
			if detectionChance < 6 then
				-- Nothing
			elseif detectionChance < 25 then
				tes3.messageBox("The guard is suspicious. You should get away")
			elseif detectionChance < 50 then
				tes3.messageBox("The guard is giving me a knowning eye. You should get away fast")
			elseif detectionChance < 75 then
				tes3.messageBox("That was a close call. Run away from the guards!")
			elseif detectionChance < 95 then
				tes3.messageBox("RUN AWAY NOW! HIDE!")
			end
		end

		guardCooldown = tes3.getSimulationTimestamp(false)
	end

-- Owner detection stream
	local ownerName = e.detector.object.name:lower()
	local isOwner   = data.currentCrime.npcs[ownerName] and true or false
	local ownerCooldownActive = tes3.getSimulationTimestamp(false) - (npcCooldown[ownerName] or 0) < config.ownerCooldownTime
	if isOwner and (not ownerCooldownActive) then
		-- Basic score taking into account player sneak and security
		local playerScore 	= math.clamp(tes3.mobilePlayer.sneak.current + tes3.mobilePlayer.security.current,0,250)
		-- Distance term
		local distanceTerm 	= math.clamp(e.detector.position:distance(tes3.player.position)/250,0.5,5)
		playerScore 		= playerScore * distanceTerm

		-- Basic score for the owner taking into account value and size of the loot
		local ownerStuff 	= data.currentCrime.npcs[ownerName]
		local npcScore 		= 0.75*(e.detector.sneak.current + e.detector.security + e.detector.mercantile)
		local lootScore 	= ownerStuff.size + 0.1*ownerStuff.value
		local detectionChance = math.clamp(math.round(100*(lootScore + npcScore)/(playerScore), 0),0,100)
		local check = detectionChance >= math.random(5,95) -- Easter egg, let's see if anyone reads the code. this would be nice for perks, though
		if check then
			util.gotCaughtOwner(e.detector.reference.id)
		else
			if detectionChance < 6 then
				-- Nothing
			elseif detectionChance < 25 then
				tes3.messageBox("The n'wah is suspicious. You should get away")
			elseif detectionChance < 50 then
				tes3.messageBox("This mark is getting restless. You should get away fast")
			elseif detectionChance < 75 then
				tes3.messageBox("That was a close call. Get to safety fast!")
			elseif detectionChance < 95 then
				tes3.messageBox("RUN!")
			end
		end
		npcCooldown[ownerName] = tes3.getSimulationTimestamp(false)
	end
end
event.register("SA_SO_visualDetection", detected)


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
