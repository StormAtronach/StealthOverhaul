local config = require("StormAtronach.SO.config")

local log = mwse.Logger.new({ moduleName = "detection", level = config.logLevel })

local detection = {}

-- Per-actor suspicion progress: 0.0 (unseen) → 1.0 (fully detected).
-- Read by stealthbar.lua.
detection.suspicion = {}

-- Per-actor vanilla detection state, updated each detectSneak tick.
-- [actorId] = { detecting = bool, lastUpdate = os.clock() }
local detectionState = {}

-- Per-actor decay delay timers: while a timer is alive, decay is suppressed.
local decayTimers = {}

-- Throttle for sneak chance debug logging: [actorId] = last log time (os.clock())
local sneakChanceLogTime = {}

-- Light mechanic: interior light sources and whether the player is currently inside one.
local lightSources = {} -- { ref = tes3reference, radius = number }
local playerInLight = false
local lightCheckTimer = nil

-- Sneak transition tracking: used to detect when the player enters sneak mode.
local wasSneaking = false

--- Restart the per-actor decay delay timer.
---@param actorId string
local function restartDecayTimer(actorId)
	if decayTimers[actorId] then
		decayTimers[actorId]:cancel()
	end
	decayTimers[actorId] = timer.start({
		type = timer.simulate,
		duration = config.suspicionDecayDelay,
		iterations = 1,
		callback = function()
			decayTimers[actorId] = nil
		end,
	})
end

--- Scan an interior cell for world-placed light sources and cache them.
---@param cell tes3cell
local function scanCellLights(cell)
	lightSources = {}
	if not cell or not cell.isInterior then
		return
	end
	for ref in cell:iterateReferences(tes3.objectType.light) do
		local light = ref.object --[[@as tes3light]]
		if not ref.disabled and light.radius and light.radius > 0 then
			table.insert(lightSources, { ref = ref, radius = light.radius })
		end
	end
	log:debug("[light] Scanned %d light sources in %s", #lightSources, cell.name or "?")
end

--- Check every 0.5s whether the player is within any cached light's radius.
local function checkPlayerLight()
	if not config.lightMechanicEnabled then
		return
	end
	local playerPos = tes3.player.position
	playerInLight = false
	for _, ls in ipairs(lightSources) do
		if not ls.ref.disabled then
			local dist = playerPos:distance(ls.ref.position)
			if dist <= ls.radius then
				playerInLight = true
				log:trace("[light] Player inside light %s (dist=%.0f radius=%.0f)", ls.ref.id, dist, ls.radius)
				break
			end
		end
	end
end

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

---@param e cellChangedEventData
local function onCellChanged(e)
	playerInLight = false
	if lightCheckTimer then
		lightCheckTimer:cancel()
		lightCheckTimer = nil
	end
	scanCellLights(e.cell)
	if #lightSources > 0 then
		lightCheckTimer = timer.start({ type = timer.simulate, duration = 0.5, iterations = -1, callback = checkPlayerLight })
	end
end
event.register(tes3.event.cellChanged, onCellChanged)

local function onLoad()
	for _, t in pairs(decayTimers) do
		t:cancel()
	end

	if lightCheckTimer then
		lightCheckTimer:cancel()
		lightCheckTimer = nil
	end
	detection.suspicion = {}
	detectionState = {}
	decayTimers = {}
	sneakChanceLogTime = {}
	lightSources = {}
	playerInLight = false
	wasSneaking = false
	log:debug("Detection system reset on load")
end
event.register(tes3.event.loaded, onLoad)

local function getAngleFactor(angle)
	return 0.25 + 0.75 * (1 + math.cos(math.rad(angle))) * 0.5
end

--- Compute the detection rate per second for a given detector and distance.
--- Rate is in bar-fills per second; multiply by dt/fillTime to get per-frame progress.
--- Based on the design model in morrowind_sneak_detection_model.md.
---@param detector tes3mobileNPC|tes3mobileCreature
---@param distance number -- game units
---@param actorId string
---@return number -- rate per second, clamped to [0, detCap]
local function computeDetectionRate(detector, distance, actorId)
	local player = tes3.mobilePlayer

	-- Effective detection range shrinks with sneak skill.
	-- When not sneaking (invisible/chameleon only), sneak reduction is 25% as effective.
	-- Clamp skill to 100 so uncapping mods don't push reduction past maxReduce.
	local sneakSkill = math.min(player.sneak.current, 100)
	local sneakReductionMult = player.isSneaking and 1.0 or 0.25
	local sneakReduction = config.maxReduce * ((sneakSkill / 100) ^ config.sneakPow) * sneakReductionMult
	local effectiveRange = config.baseRange * (1 - sneakReduction / 100)

	-- Distance factor: squared falloff, reaches 0 at effectiveRange
	local distanceFactor = math.max(0, 1 - distance / effectiveRange) ^ config.distPow

	-- Angle factor: continuous from 0.25 (directly behind NPC) to 1.0 (face-on)
	-- getViewToActor: 0 = directly in front, ±180 = directly behind
	local angle = detector:getViewToActor(player)

	local angleFactor = getAngleFactor(angle)

	local rawRate = distanceFactor * angleFactor

	local standingStill = player.velocity:length() < 5
	-- Modifiers
	local standStillMult = standingStill and 0.8 or 1.0
	local lightFactor = (config.lightMechanicEnabled and playerInLight) and config.lightRateMult or 1.0
	local shoeFactor = 1 + player:getBootsWeight() / 50

	local modifiedRate = rawRate * standStillMult * lightFactor * shoeFactor

	-- Add the chameleon factor and clamp
	local rate = math.clamp(modifiedRate, config.detFloor, config.detCap)

	local now = os.clock()
	if (now - (sneakChanceLogTime[actorId] or 0)) >= 0.25 then
		sneakChanceLogTime[actorId] = now
		--log:trace("[rate:%s] dist=%.0f effRange=%.0f distFactor=%.3f angle=%.1f angleFactor=%.2f rawRate=%.3f", actorId,
		--          distance, effectiveRange, distanceFactor, angle, angleFactor, rawRate)
		--log:trace(
		--"[rate:%s] standStill=%.2f light=%.2f shoe=%.2f chameleon=%.0f => rate=%.4f/s (fillTime=%.1fs) | sneakXP: %.2f",
		--actorId, standStillMult, lightFactor, shoeFactor, chameleon, rate, config.fillTime,
		--tes3.mobilePlayer.skillProgress[tes3.skill.sneak])
	end
	return rate
end

--[==[
TODO: onCrimeWitnessed is disabled until e.block behaviour is confirmed.
The intent is: if the witness hasn't fully detected the player (suspicion < 1.0),
block vanilla crime consequences and apply a suspicion spike instead.

--- Intercept witnessed theft per NPC.
---@param e crimeWitnessedEventData
local function onCrimeWitnessed(e)
	log:trace("[crimeWitnessed] type=%s", tostring(e.type))
	if e.type ~= "theft" then return end
	local ref = e.witness
	local mob = e.witnessMobile --[[@as tes3mobileNPC|tes3mobileCreature]]
	if not ref or not mob then return end
	if mob.isPlayerDetected then
		log:debug("[crimeWitnessed] %s already detects player: vanilla handles it", ref.id)
		return
	end
	local actorId = ref.id
	local bonus = config.stealSuspicionBonus / 100
	local current = math.min((detection.suspicion[actorId] or 0) + bonus, 1.0)
	detection.suspicion[actorId] = current
	restartDecayTimer(actorId)
	e.block = true  -- suppress vanilla crime consequences
	log:debug("[crimeWitnessed] suppressed vanilla for %s: suspicion +%.2f -> %.2f", actorId, bonus, current)
end
event.register("crimeWitnessed", onCrimeWitnessed, { priority = 1000 })
]==]

---@param e skillRaisedEventData
local function onSkillRaised(e)
	if e.skill == tes3.skill.sneak then
		log:debug("[sneak] level up! new level: %d | xp progress reset to: %.2f (source: %s)", e.level,
		          tes3.mobilePlayer.skillProgress[tes3.skill.sneak + 1], tostring(e.source))
	end
end
event.register(tes3.event.skillRaised, onSkillRaised)


--- detectSneak fires per actor per AI tick.
--- We only record vanilla's detection state here; accumulation happens in simulate.
---@param e detectSneakEventData
local function detectSneakCallback(e)
	if not config.modEnabled then
		return
	end
	if e.target ~= tes3.mobilePlayer then
		return
	end
	local mp = tes3.mobilePlayer
	if not mp.isSneaking and mp.chameleon <= 0 and mp.invisibility <= 0 then
		return
	end


	-- Checks if the NPC is in combat, in which case onSimulate handles their logic
	if e.detector.inCombat then
		return
	end

	-- Checks if the player is in combat with another NPC, in which case the NPC should immediately detect the player when they try to in this function
	local playerInCombat = false
	for id, state in pairs(detectionState) do
		if state and state.inCombat then
			playerInCombat = true
			break
		end
	end

	if playerInCombat then
		e.isDetected = true
		e.detector.isPlayerDetected = true
		e.detector.isPlayerHidden = false
		return
	end

	local detectorType = e.detector.actorType
	if detectorType ~= tes3.actorType.npc and detectorType ~= tes3.actorType.creature then
		return
	end

	local detector = e.detector --[[@as tes3mobileNPC|tes3mobileCreature]]
	local ref = detector.reference
	local actorId = ref.id

	local previouslyDetected = e.detector.isPlayerDetected

	-- Compute detection rate and store for the simulate loop
	local distance = detector.reference.position:distance(tes3.player.position)
	local rate = computeDetectionRate(detector, distance, actorId)
	local state = detectionState[actorId] or {}
	state.rate = rate

	-- Allow the actor suspicion to go stale if suspicion is zero
	local mob = ref.mobile
	local angle = mob:getViewToActor(tes3.mobilePlayer)
	local angleFactor = getAngleFactor(angle)
	local hidingTerm = (1 - angleFactor) * config.hidingBonus

	local shouldWeLetActorGoStale = math.clamp(rate - hidingTerm, 0, config.detCap)
	if shouldWeLetActorGoStale > 0 then
		state.lastUpdate = os.clock()
	end


	detectionState[actorId] = state


	log:trace("[detectSneak] %s distance=%.0f rate=%.4f/s", actorId, distance, rate)

	-- Override vanilla with our accumulator-based result
	local nowDetected = (detection.suspicion[actorId] or 0) >= 1.0

	e.isDetected = nowDetected
	detector.isPlayerDetected = nowDetected
	detector.isPlayerHidden = not nowDetected

	if nowDetected and not previouslyDetected then
		log:debug("Detected by %s! Progress reached 1.0.", actorId)
		event.trigger("SA_SO_detected", e)
	end
end
event.register(tes3.event.detectSneak, detectSneakCallback, { priority = 1000 })

--- Simulate runs every frame. This is where time-based accumulation/decay happens,
--- matching the OpenMW approach: progress changes at velocity * dt, independent of
--- AI tick frequency.
---@param e simulateEventData
local function onSimulate(e)
	if not config.modEnabled then
		return
	end

	-- On sneak start: initialize already-detected nearby actors to an initial suspicion based on their sneak skill and rotation from NPC
	-- so the player can't escape detection by simply pressing sneak.
	local isSneaking = tes3.mobilePlayer.isSneaking
	if isSneaking and not wasSneaking then
		local nearby = tes3.findActorsInProximity({ reference = tes3.player, range = config.baseRange })
		if nearby then
			for _, mob in ipairs(nearby) do
				---@cast mob tes3mobileActor
				if mob ~= tes3.mobilePlayer and tes3.testLineOfSight({ reference1 = mob.reference, reference2 = tes3.player}) then
					local ref = mob.reference
					if ref then
						local angle = mob:getViewToActor(tes3.mobilePlayer)
						local angleFactor = getAngleFactor(angle)
						local sneakSkill = math.min(tes3.mobilePlayer.sneak.current, 100)
						detection.suspicion[ref.id] = detection.suspicion[ref.id] or 0
						detection.suspicion[ref.id] = math.max(detection.suspicion[ref.id], angleFactor + (0.5 * (1-(sneakSkill/100))))
						local pm = tes3.worldController.mobManager.processManager
						pm:detectSneak(mob, tes3.mobilePlayer, true)
					end
				end
			end
		end
	end
	wasSneaking = isSneaking

	-- Nothing to process if no actor is being tracked
	if not next(detection.suspicion) and not next(detectionState) then
		return
	end

	local dt = e.delta
	-- Seconds to fall to 0 from 1.0 (when not detected, after delay)
	local dv = 1.0 / config.decayTime
	-- A detectionState entry is considered stale if no detectSneak tick arrived
	-- within this window (actor likely left range)
	local staleThreshold = config.aiUpdateTime * 2 + 0.5

	-- Collect all actor IDs that need processing this frame
	local toProcess = {}
	for id in pairs(detection.suspicion) do
		toProcess[id] = true
	end
	for id in pairs(detectionState) do
		toProcess[id] = true
	end

	
	local standingStill = tes3.mobilePlayer.velocity:length() < 5
	local chameleon = tes3.mobilePlayer.chameleon or 0
	local invisible = tes3.mobilePlayer.invisibility > 0 or chameleon >= 100
	
	for actorId in pairs(toProcess) do
		local current = detection.suspicion[actorId] or 0
		local state = detectionState[actorId]
		local inCombat = state and state.inCombat or false
		local inCombatDecayCooldown = false
		
		local ref = tes3.getReference(actorId)
		if not ref then
			detection.suspicion[actorId] = nil
			detectionState[actorId] = nil
			sneakChanceLogTime[actorId] = nil

			if decayTimers[actorId] then
				decayTimers[actorId]:cancel()
				decayTimers[actorId] = nil
			end
			goto continue
		end

		if inCombat then
			local combatStarted = state.combatStarted
			if os.clock() - combatStarted <= 3 then
				restartDecayTimer(actorId)
				state.lastUpdate = os.clock()
				current = 1
				inCombatDecayCooldown = true
				local distance = ref.position:distance(tes3.player.position)
				if distance < config.baseRange * 2 then
					local playerSeen = tes3.testLineOfSight({ reference1 = ref, reference2 = tes3.player})
					if playerSeen then
						state.combatStarted = os.clock()
					end
				end
			end
		end

		local lastUpdate = state and state.lastUpdate or 0
		local isStale = (not state) or (os.clock() - lastUpdate) >= staleThreshold
		local active = not isStale

		local mob = ref.mobile
		if active and not inCombatDecayCooldown then

			local angle = mob:getViewToActor(tes3.mobilePlayer)
			local angleFactor = getAngleFactor(angle)
			local rate = state.rate or config.detFloor
			

			-- Apply chameleon
			rate = math.clamp(rate * (1 - (chameleon / 100)), config.detFloor, config.detCap)

			-- Apply invisiblity
			if invisible then
                rate = config.detFloor
            end
           

            if standingStill and (not playerInLight or invisible) then
                local hidingTerm = (1 - angleFactor) * config.hidingBonus
                rate = math.clamp(rate - hidingTerm, 0, config.detCap)
            end

			local delta = rate * dt / config.fillTime
			current = math.min(1.0, current + delta)

			if current >= 1 then
				local pm = tes3.worldController.mobManager.processManager
				pm:detectSneak(mob, tes3.mobilePlayer, true)
			end


			restartDecayTimer(actorId)
			log:trace("Suspicion ↑ for %s: %.3f (+%.4f/frame) rate=%.4f/s", actorId, current, delta, rate)
		elseif not decayTimers[actorId] then
			current = math.max(0.0, current - dv * dt)
			if current > 0 then
				log:trace("Suspicion ↓ for %s: %.3f (-%.4f/frame)", actorId, current, dv * dt)
			end
		end

		-- Clean up fully decayed actors
		if current <= 0 and not active then
			if inCombat then
				if mob then
					mob:stopCombat(true)
					local wanderRange = mob.cell.isOrBehavesAsExterior and 2000 or 400
					tes3.setAIWander({ reference = ref, range = wanderRange, reset = true, idles = generateIdles() })
				end
			end
			detection.suspicion[actorId] = nil
			detectionState[actorId] = nil
			sneakChanceLogTime[actorId] = nil
			if decayTimers[actorId] then
				decayTimers[actorId]:cancel()
				decayTimers[actorId] = nil
			end
		else --If still running, just set the updated value
			detection.suspicion[actorId] = current
		end
		::continue::
	end
end
event.register(tes3.event.simulate, onSimulate)

local function onDeath(e)
	local ref = e.reference
	if not ref then
		 return 
	end
	local actorId = ref.id
	if log.level >= mwse.logLevel.debug then
		tes3.messageBox("Actor dead, cleaning up values for: %s", actorId)
	end
	detection.suspicion[actorId] = nil
	detectionState[actorId] = nil
	sneakChanceLogTime[actorId] = nil
	if decayTimers[actorId] then
		decayTimers[actorId]:cancel()
		decayTimers[actorId] = nil
	end
end
event.register(tes3.event.death, onDeath)

event.register(tes3.event.combatStopped, function(e)
	if not e.actor or not e.actor.reference then return end
    local actorId = e.actor.reference.id
    if detectionState[actorId] then
        detectionState[actorId].inCombat = false
    end
end)

local function onCombatStarted(e)
    if e.target ~= tes3.mobilePlayer then return end
    if not e.actor then return end

    local actorId = e.actor.reference.id
    local state = detectionState[actorId] or {}

    state.inCombat = true
    state.combatStarted = os.clock()
    state.lastUpdate = os.clock()

    detectionState[actorId] = state

	if log.level >= mwse.logLevel.debug then
		tes3.messageBox(string.format"Started combat with: %s", actorId)
	end
end
event.register(tes3.event.combatStarted, onCombatStarted)

--- Returns the current suspicion level (0.0–1.0) for the given actor ID.
---@param actorId string
---@return number
function detection.getSuspicion(actorId)
	return detection.suspicion[actorId] or 0
end

--- Adds suspicion to an actor, capped at 1.0. Restarts the decay delay timer.
---@param actorId string
---@param amount number  0.0–1.0
function detection.addSuspicion(actorId, amount)
	local current = math.min((detection.suspicion[actorId] or 0) + amount, 1.0)
	detection.suspicion[actorId] = current
	restartDecayTimer(actorId)
end

--- Clears all suspicion and tracking state for an actor immediately.
---@param actorId string
function detection.clearSuspicion(actorId)
	detection.suspicion[actorId] = nil
	detectionState[actorId] = nil
	sneakChanceLogTime[actorId] = nil
	if decayTimers[actorId] then
		decayTimers[actorId]:cancel()
		decayTimers[actorId] = nil
	end
end

return detection