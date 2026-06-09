local config = require("StormAtronach.SO.config")

local log = mwse.Logger.new({ moduleName = "detection", level = config.logLevel })

local detection = {}

local onSimulateTime = 0

-- Per-actor suspicion progress: 0.0 (unseen) → 1.0 (fully detected).
-- Read by stealthbar.lua.
detection.suspicion = {}

-- Per-actor vanilla detection state, updated each detectSneak tick.
-- [ref] = { detecting = bool, lastUpdate = os.clock() }
local detectionState = {}

-- Per-actor decay delay timers: while a timer is alive, decay is suppressed.
local decayTimers = {}

-- Light mechanic: interior light sources and whether the player is currently inside one.
local lightSources = {} -- { ref = tes3reference, radius = number }
local playerInLight = false
local lightCheckTimer = nil

-- Sneak transition tracking: used to detect when the player enters sneak mode.
local wasSneaking = false

--- Restart the per-actor decay delay timer.
---@param ref tes3reference
local function restartDecayTimer(ref)
	if not ref:isValid() then return end

	if decayTimers[ref] then
		decayTimers[ref]:cancel()
	end
	decayTimers[ref] = timer.start({
		type = timer.simulate,
		duration = config.suspicionDecayDelay,
		iterations = 1,
		callback = function()
			decayTimers[ref] = nil
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
		local ref = ls.ref
		if ref and ref:isValid() and not ref.disabled then
			local dist = playerPos:distance(ls.ref.position)
			if dist <= ls.radius then
				playerInLight = true
				log:trace("[light] Player inside light %s (dist=%.0f radius=%.0f)", ls.ref.id, dist, ls.radius)
				break
			end
		end
	end
end

local function recalculateLights(cell)
	playerInLight = false
	if lightCheckTimer then
		lightCheckTimer:cancel()
		lightCheckTimer = nil
	end
	scanCellLights(cell)
	if #lightSources > 0 then
		lightCheckTimer = timer.start({ type = timer.simulate, duration = 0.5, iterations = -1, callback = checkPlayerLight })
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
	recalculateLights(e.cell)
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
	lightSources = {}
	playerInLight = false
	wasSneaking = false
	recalculateLights(tes3.player.cell)

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
---@return number -- rate per second, clamped to [0, detCap]
local function computeDetectionRate(detector, distance)
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
	local bootsWeight = player:getBootsWeight() or 0
	local shoeFactor = 1 + bootsWeight / 50

	local modifiedRate = rawRate * standStillMult * lightFactor * shoeFactor

	-- Add the chameleon factor and clamp
	local rate = math.clamp(modifiedRate, config.detFloor, config.detCap)

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

local function actorFightsPlayer(actorMobile)
	for _, actor in ipairs(actorMobile.hostileActors) do
		if actor.reference == tes3.player then
			return true
		end
	end
	return false
end

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

	local detector = e.detector --[[@as tes3mobileNPC|tes3mobileCreature]]
	local ref = detector.reference

	local state = detectionState[ref] or {}
	state.inCombat = actorFightsPlayer(e.detector)

	if not tes3.mobilePlayer.isSneaking and tes3.mobilePlayer.chameleon <= 0 and tes3.mobilePlayer.invisibility <= 0 then
		return
	end

	local detectorType = e.detector.actorType
	if detectorType ~= tes3.actorType.npc and detectorType ~= tes3.actorType.creature then
		return
	end

	
	local previouslyDetected = e.detector.isPlayerDetected

	-- Compute detection rate and store for the simulate loop
	local distance = ref.position:distance(tes3.player.position)
	local rate = computeDetectionRate(detector, distance)
	

	if tes3.mobilePlayer.inCombat then
		local playerSeen = tes3.testLineOfSight({ reference1 = ref, reference2 = tes3.player })
		if playerSeen then
			rate = config.detCap * config.combatDetectionMultiplier
		end
	end

	state.rate = rate

	-- Check if player is hiding -> Stands still, is behind enemy, and not in a light
	local angle = detector:getViewToActor(tes3.mobilePlayer)
	local angleFactor = getAngleFactor(angle)
	local hidingTerm = (1 - angleFactor) * config.hidingBonus

	-- Apply chameleon for detection check (we have already saved down the state, so this will not be doubly applied in onSimulate later)
	local chameleon = tes3.mobilePlayer.chameleon or 0
	rate = rate * (1 - (chameleon / 100))

	-- Allow the actor suspicion to go stale if suspicion is zero
	local shouldWeLetActorGoStale = math.clamp(rate - hidingTerm, 0, config.detCap)
	if shouldWeLetActorGoStale > 0 then
		state.lastUpdate = onSimulateTime
	end

	detectionState[ref] = state

	log:trace("[detectSneak] %s distance=%.0f rate=%.4f/s", ref.id, distance, rate)

	-- Override vanilla with our accumulator-based result
	local detectedState = (detection.suspicion[ref] or 0) >= 1.0

	e.isDetected = detectedState
	detector.isPlayerDetected = detectedState
	detector.isPlayerHidden = not detectedState

	if detectedState and not previouslyDetected then
		log:debug("Detected by %s! Progress reached 1.0.", ref)
		event.trigger("SA_SO_detected", e)
	end
end
event.register(tes3.event.detectSneak, detectSneakCallback, { priority = 1000 })



--- Simulate runs every frame. This is where time-based accumulation/decay happens,
--- matching the OpenMW approach: progress changes at velocity * dt, independent of
--- AI tick frequency.
---@param e simulateEventData
local function onSimulate(e)

	-- Keep our own timer, to make sure it only adds when we simulate
	onSimulateTime = onSimulateTime + e.delta

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
				local ref = mob.reference
				if ref and mob ~= tes3.mobilePlayer and tes3.testLineOfSight({ reference1 = ref, reference2 = tes3.player}) then
					local angle = mob:getViewToActor(tes3.mobilePlayer)
					local angleFactor = getAngleFactor(angle)
					local sneakSkill = math.min(tes3.mobilePlayer.sneak.current, 100)
					detection.suspicion[ref] = detection.suspicion[ref] or 0
					detection.suspicion[ref] = math.min(1, math.max(detection.suspicion[ref], angleFactor + (0.5 * (1-(sneakSkill/100)))) * config.startStealthSuspicionMultiplier)

					local state = detectionState[ref] or {}
					state.lastUpdate = onSimulateTime
					state.rate = state.rate or config.detFloor
					detectionState[ref] = state

					local playerSeen = tes3.testLineOfSight({ reference1 = ref, reference2 = tes3.player })
					if playerSeen then
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
	for ref in pairs(detection.suspicion) do
		toProcess[ref] = true
	end
	for ref in pairs(detectionState) do
		toProcess[ref] = true
	end

	local standingStill = tes3.mobilePlayer.velocity:length() < 5
	local chameleon = tes3.mobilePlayer.chameleon or 0
	local invisible = tes3.mobilePlayer.invisibility > 0 or chameleon >= 100

	for ref in pairs(toProcess) do
		
		if not ref:isValid() then
			detection.suspicion[ref] = nil
			detectionState[ref] = nil
			if decayTimers[ref] then
				decayTimers[ref]:cancel()
				
			end
			decayTimers[ref] = nil
			goto continue
		end
		
		local current = detection.suspicion[ref] or 0
		local state = detectionState[ref] or {}
		local mob = ref.mobile --[[@as tes3mobileActor]]

		if mob then
			state.inCombat = actorFightsPlayer(mob)
		end
		local hostile = state.inCombat or false

		if hostile and not state.combatStarted then
			state.combatStarted = onSimulateTime
		end

		local enemyInPursuitWindow = false
		if hostile and state.combatStarted then
			enemyInPursuitWindow = (onSimulateTime - state.combatStarted) <= config.combatHidingTimer
		end

		if enemyInPursuitWindow then
			current = 1
			state.lastUpdate = onSimulateTime
			restartDecayTimer(ref)
		elseif hostile then
			local distance = ref.position:distance(tes3.player.position)
			if distance < config.baseRange * 2 then
				local playerSeen = tes3.testLineOfSight({ reference1 = ref, reference2 = tes3.player })
				if playerSeen then
					if mob and mob.inCombat then
						state.combatStarted = onSimulateTime
					end
				end
			end
		end

		local lastUpdate = state and state.lastUpdate or 0
		local isStale = (not state) or (onSimulateTime - lastUpdate) >= staleThreshold
		local active = not isStale

		if log.level >= mwse.logLevel.debug then
			tes3.messageBox(
				"Ref: %s | current=%.3f | active=%s | state.inCombat=%s |  enemyInPursuitWindow=%s | rate=%.4f | timestamp=%.3f | player.InCombat=%s",
				ref.id,
				current,
				tostring(active),
				tostring(state.inCombat),
				tostring(enemyInPursuitWindow),
				state.rate or -1,
				onSimulateTime,
				tostring(tes3.mobilePlayer.inCombat)
			)
		end
		
		if mob and active and not enemyInPursuitWindow then
			
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
				local playerSeen = tes3.testLineOfSight({ reference1 = ref, reference2 = tes3.player })
				if playerSeen then
					local pm = tes3.worldController.mobManager.processManager
					pm:detectSneak(mob, tes3.mobilePlayer, true)
				end
			end


			restartDecayTimer(ref)
			log:trace("Suspicion ↑ for %s: %.3f (+%.4f/frame) rate=%.4f/s", ref.id, current, delta, rate)
		elseif not decayTimers[ref] and not enemyInPursuitWindow then
			current = math.max(0.0, current - dv * dt)
			if current > 0 then
				log:trace("Suspicion ↓ for %s: %.3f (-%.4f/frame)", ref.id, current, dv * dt)
			end
		end

		-- Clean up fully decayed actors.
		if current <= 0 and not active then
			if mob and mob.inCombat and state.combatStarted ~= nil then
				mob:stopCombat(true)
				local wanderRange = mob.cell.isOrBehavesAsExterior and 2000 or 400
				tes3.setAIWander({ reference = ref, range = wanderRange, reset = true, idles = generateIdles() })
			end
			detection.suspicion[ref] = nil
			detectionState[ref] = nil
			if decayTimers[ref] then
				decayTimers[ref]:cancel()
				decayTimers[ref] = nil
			end
		else --If still running, just set the updated value
			detection.suspicion[ref] = current
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
	detection.suspicion[ref] = nil
	detectionState[ref] = nil
	if decayTimers[ref] then
		decayTimers[ref]:cancel()
		decayTimers[ref] = nil
	end
end
event.register(tes3.event.death, onDeath)


--- @param e combatStartedEventData
local function onCombatStarted(e)
	if e.target ~= tes3.mobilePlayer then
		return
	end

	local ref = e.actor.reference
	if not ref then
		return
	end

	detection.suspicion[ref] = 1
	local state = detectionState[ref] or {}
	state.inCombat = true
	state.combatStarted = onSimulateTime
	state.lastUpdate = onSimulateTime
    detectionState[ref] = state
end
event.register(tes3.event.combatStarted, onCombatStarted)


--- Returns the current suspicion level (0.0–1.0) for the given actor ID.
---@param ref tes3reference
---@return number
function detection.getSuspicion(ref)
	if ref:isValid() then
		return detection.suspicion[ref]
	end
	return 0
end

--- Adds suspicion to an actor, capped at 1.0. Restarts the decay delay timer.
---@param ref tes3reference
---@param amount number  0.0–1.0
function detection.addSuspicion(ref, amount)
	if ref:isValid() then
		local current = math.min((detection.suspicion[ref] or 0) + amount, 1.0)
		detection.suspicion[ref] = current
		restartDecayTimer(ref)
	end
end

--- Clears all suspicion and tracking state for an actor immediately.
---@param ref tes3reference
function detection.clearSuspicion(ref)
	detection.suspicion[ref] = nil
	detectionState[ref] = nil
	if decayTimers[ref] then
		decayTimers[ref]:cancel()
		decayTimers[ref] = nil
	end
end

return detection