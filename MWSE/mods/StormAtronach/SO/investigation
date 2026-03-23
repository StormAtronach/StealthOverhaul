local config = require("StormAtronach.SO.config")

local log = mwse.Logger.new()

local investigation = {}

-- The following is a refactoring of Celediel's More Attentive Guards sneak module
-- All credit for the original work goes to Celediel. Thanks! :)

local function generateIdles()
	local idles = {}
	for i = 1, 4 do
		idles[i] = math.random(0, 60)
	end
	idles[5] = 0
	for i = 6, 8 do
		idles[i] = math.random(0, 60)
	end
	return idles
end

---@param npcRef tes3reference
---@return boolean cantContinue
local function doChecks(npcRef)
	local mob = npcRef.mobile
	if not mob then
		log:debug("NPC %s does not have a mobile", npcRef.id or "none")
		return true
	end
	if mob.isKnockedDown or mob.isHitStunned or mob.isParalyzed or mob.isDead or mob.inCombat then
		log:debug("NPC %s can't continue (incapacitated or in combat)", npcRef.id or "none")
		return true
	end
	return false
end

---@param npcRef tes3reference
investigation.startWander = function(npcRef)
	if not (npcRef and npcRef.mobile) then
		log:debug("No ref or mobile in startWander")
		return
	end
	local wanderRange = npcRef.mobile.cell.isOrBehavesAsExterior and config.wanderRangeExterior or
	                    config.wanderRangeInterior
	tes3.setAIWander({ reference = npcRef, range = wanderRange, reset = true, idles = generateIdles() })
end

---@param e mwseTimerCallbackData
local function returnToOriginalPosition(e)
	local data = e.timer.data
	if not data then
		log:debug("Payload for returnToOriginalPosition is missing")
		return
	end

	local npcRefSH = data.npcRef
	if not npcRefSH:valid() then
		log:debug("Reference no longer valid in returnToOriginalPosition")
		return
	end
	local npcRef = npcRefSH:getObject()

	local mob = npcRef.mobile
	if not mob or mob.isDead or mob.isParalyzed or mob.inCombat then
		log:debug("NPC %s cannot return: dead, paralyzed, or in combat", npcRef.id)
		return
	end

	tes3.setAITravel({ reference = npcRef, destination = data.originalPosition, reset = true })

	-- Notify the detection system to clear this NPC's suspicion - investigation resolved
	event.trigger("SA_SO_investigationComplete", { reference = npcRef })
	log:debug("NPC %s returning to original position", npcRef.id)
end

---@param e mwseTimerCallbackData
local function checkDestination(e)
	local data = e.timer.data
	if not data then
		log:debug("Timer data payload not present")
		e.timer:cancel()
		return
	end

	local npcRefSH = data.npcRef
	if not npcRefSH:valid() then
		log:debug("Reference no longer valid in checkDestination")
		e.timer:cancel()
		return
	end

	local npcRef = npcRefSH:getObject()
	local mob = npcRef.mobile

	if not mob or not mob.aiPlanner then
		log:debug("aiPlanner for %s is not active", npcRef.id)
		return
	end

	local pkg = mob.aiPlanner.currentPackageIndex
	local AITravel = pkg == tes3.aiPackage.travel
	local AIWander = pkg == tes3.aiPackage.wander

	if not (AITravel or AIWander) then
		log:debug("NPC %s is no longer travelling or wandering", npcRef.id)
		e.timer:cancel()
		return
	end

	-- If the NPC entered combat or was incapacitated, cancel without forcing a wander
	if mob.inCombat or mob.isDead or mob.isKnockedDown or mob.isHitStunned or mob.isParalyzed then
		log:debug("NPC %s interrupted (combat/incapacitated), cancelling investigation", npcRef.id)
		e.timer:cancel()
		return
	end

	if not mob.position then
		log:debug("Nil position for %s before distance check", npcRef.id)
		return
	end
	local destination = data.destination or mob.position:copy()
	local remainingDistance = mob.position:distance(destination)

	if remainingDistance <= 5 or AIWander then
		e.timer:cancel()
		investigation.startWander(npcRef)
		local investigationTime = math.random(3, 8)
		log:debug("NPC %s arrived at destination, wandering for %ds", npcRef.id, investigationTime)

		local npcRefSHExit = tes3.makeSafeObjectHandle(npcRef)
		timer.start({
			type = timer.simulate,
			duration = investigationTime,
			callback = "SA_SO_startTripBack",
			iterations = 1,
			persist = true,
			data = { npcRef = npcRefSHExit, originalPosition = data.originalPosition },
		})
	end
end

-- Register timer callbacks once at module load
timer.register("SA_SO_checkIfNPCArrived", checkDestination)
timer.register("SA_SO_startTripBack", returnToOriginalPosition)

---@param npcRef tes3reference
---@param destination tes3vector3
investigation.startTravel = function(npcRef, destination)
	if (not npcRef) or (not destination) then
		log:debug("Investigation start: missing npcRef or destination")
		return
	end
	if doChecks(npcRef) then
		log:debug("NPC is doing other stuff")
		return
	end

	-- Avoid aquatic creatures going on land
	if npcRef.object and npcRef.object.swims then
		local waterLevel = tes3.player.cell.waterLevel or -20000
		if destination.z > waterLevel then
			log:debug("Avoiding aquatic creature going on land")
			return
		end
	end

	local originalPosition = npcRef.position:copy()
	local distance = npcRef.position:distance(destination)
	local duration = math.round(math.clamp(distance / 50, config.minTravelTime, config.maxTravelTime), 0)

	local npcRefSafe = tes3.makeSafeObjectHandle(npcRef)
	timer.delayOneFrame(function()
		if not npcRefSafe:valid() then
			log:debug("NPC ref handle got invalidated before travel")
			return
		end
		tes3.setAITravel({ reference = npcRefSafe:getObject(), destination = destination })
	end)

	log:debug("NPC %s investigating, travel duration %ds", npcRef.id, duration)
	timer.start({
		type = timer.simulate,
		duration = 1,
		callback = "SA_SO_checkIfNPCArrived",
		iterations = duration,
		persist = true,
		data = { npcRef = npcRefSafe, destination = destination, originalPosition = originalPosition },
	})
end

return investigation
