local config = require("StormAtronach.SO.config")
local interop = require("StormAtronach.SO.interop")
local util = require("StormAtronach.SO.util")
require("StormAtronach.SO.detection")
require("StormAtronach.SO.sneakstrike")
require("StormAtronach.SO.stealthbar")
require("StormAtronach.SO.stealingcheck")

local log = mwse.Logger.new({ moduleName = "main", level = config.logLevel })

if config.experimentalInvestigation then
	require("StormAtronach.SO.investigation")
	log:info("Experimental investigation module loaded")
end

require("StormAtronach.SO.mcm")

-- State
local guardCooldown = 0
local npcCooldown = {}

local eiInterop = require("StormAtronach.SO.eiInterop")

-- Event handlers

-- Apply the configured AI scan interval and alarm floor to each mobile as it activates.
---@param e mobileActivatedEventData
local function setAIIntervalTime(e)
	if e.mobile and e.mobile.scanInterval then
    	e.mobile.scanInterval = config.aiUpdateTime
	end
	if config.setAlarmToThreshold and e.mobile.alarm and e.mobile.alarm < config.alarmThreshold then
		e.mobile.alarm = config.alarmThreshold
	end
end
event.register(tes3.event.mobileActivated,  setAIIntervalTime)


---@param e loadEventData
local function onLoad(e)
	npcCooldown = {} 		 -- per-owner cooldowns
	guardCooldown = 0		 -- Reset the guard cooldown
	util.getData() 			 -- create the save data table if missing
	util.updateFactionList() -- rebuild the faction id set
	eiInterop.toggleEssentialIndicatorCrosshair()
end
event.register(tes3.event.loaded,onLoad)

--- Stolen-goods checks when an actor fully detects the player: guards roll against the bounty, owners against their own goods.
--- @param e detectSneakEventData  (passed through from SA_SO_detected)
local function detected(e)
	if not config.modEnabled then return end
	local data = util.getData()
	-- Nothing stolen: nothing to check.
	if (data.currentCrime.size == 0) and (data.currentCrime.value == 0) then return end

	local bounty = tes3.mobilePlayer.bounty

	-- Guard check
	local cooldownActive = (tes3.getSimulationTimestamp(false) - guardCooldown) < (config.guardCooldownTime or 5)
	if config.stolenItemsMechanic_Guard and e.detector.object.isGuard and (not cooldownActive) and (bounty > config.bountyThreshold) then
		-- Player score: Sneak + Security, capped.
		local playerScore = math.clamp(tes3.mobilePlayer.sneak.current + tes3.mobilePlayer.security.current,0,250)
		-- Distance term
		local distanceTerm = math.clamp(e.detector.position:distance(tes3.player.position)/250,0.5,5)
		playerScore = config.lenience*playerScore * distanceTerm
		local detectionChance = math.clamp(math.round(100*data.currentCrime.size / playerScore, 0),0,100)
		local check = detectionChance >= math.random(5,95) -- roll is clamped to 5..95 so neither side is ever certain
		-- No checks beyond the configured distance.
		if distanceTerm >= config.guardMaxDistance then
			check = false
			detectionChance = 0
		end
		if check then
			local guardSH = tes3.makeSafeObjectHandle(e.detector.reference)
			util.gotCaughtGuard(guardSH)
		else
			if detectionChance < 6 then
				-- below 6%: no warning
			elseif detectionChance < 25 then
				tes3.messageBox("The guard is suspicious. You should get away")
			elseif detectionChance < 50 then
				tes3.messageBox("The guard is giving you a hard look. Get away, fast")
			elseif detectionChance < 75 then
				tes3.messageBox("That was close. Get away from the guards!")
			elseif detectionChance < 95 then
				tes3.messageBox("RUN AWAY NOW! HIDE!")
			end
		end

		guardCooldown = tes3.getSimulationTimestamp(false)
	end

-- Owner check
	local ownerName = (e.detector.object.name or "none"):lower()
	local isOwner   = data.currentCrime.npcs[ownerName] and true or false
	local ownerCooldownActive = tes3.getSimulationTimestamp(false) - (npcCooldown[ownerName] or 0) < config.ownerCooldownTime
	if config.stolenItemsMechanic_Owner and isOwner and (not ownerCooldownActive) then
		-- Player score: Sneak + Security, capped.
		local playerScore 	= config.lenience*math.clamp(tes3.mobilePlayer.sneak.current + tes3.mobilePlayer.security.current,0,250)
		-- Distance term
		local distanceTerm 	= math.clamp(e.detector.position:distance(tes3.player.position)/250,0.5,5)
		playerScore 		= playerScore * distanceTerm

		-- Loot score: total size plus a tenth of the value of this owner's goods.
		local ownerStuff 	= data.currentCrime.npcs[ownerName]
		local npcScore 		= 0 -- owner skill term disabled: it made owners far too strong
		local lootScore 	= ownerStuff.size + 0.1*ownerStuff.value
		local detectionChance = math.clamp(math.round(100*(lootScore + npcScore)/(playerScore), 0),0,100)
		local check = detectionChance >= math.random(5,95) -- roll is clamped to 5..95 so neither side is ever certain
		if check then
			-- Create a safe handle and pass it to gotCaughtOwner
			local npcSH = tes3.makeSafeObjectHandle(e.detector.reference)
			util.gotCaughtOwner(npcSH)
		else
			if detectionChance < 6 then
				-- below 6%: no warning
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
event.register("SA_SO_detected", detected)


--- Updating the list of stolen items. itemTileUpdated fires in bursts (one per tile redraw),
--- so coalesce into a single rescan on the next simulate frame via a dirty flag.
local crimeDirty = false

--- @param e itemTileUpdatedEventData
local function itemTileUpdatedCallback(e)
	if not config.modEnabled then return end
	-- Only world pickups; menu transfers are handled on menu exit.
	if tes3ui.menuMode() then return end
	crimeDirty = true
end
event.register(tes3.event.itemTileUpdated, itemTileUpdatedCallback)

-- Menu exit covers container and barter transfers.
--- @param e menuExitEventData
local function menuExitCallback(e)
	if not config.modEnabled then return end
	crimeDirty = true
end
event.register(tes3.event.menuExit, menuExitCallback)

-- Drain the dirty flag once per frame so the rescan runs at most once per burst.
local function updateCrimeIfDirty(e)
	if not crimeDirty then return end
	crimeDirty = false
	util.updateCurrentCrime()
end
event.register(tes3.event.simulate, updateCrimeIfDirty)

local sneakedLastFrame = false
local function updateEiCursorState()
	if not config.eiCrosshairOnlyWhenSneaking then return end
	if tes3.mobilePlayer.isSneaking ~= sneakedLastFrame then
		eiInterop.toggleEssentialIndicatorCrosshair()
	end
	sneakedLastFrame = tes3.mobilePlayer.isSneaking
end
if eiInterop.ei then
	event.register(tes3.event.simulate, updateEiCursorState)
end