local config = require("StormAtronach.SO.config")
local experience = require("StormAtronach.SO.experience")

local log = mwse.Logger.new({ moduleName = "detection", level = config.logLevel })

local m1pe_installed, m1pe = pcall(require, "Modernized 1st Person Experience.interop")
if not m1pe_installed then
	m1pe = nil
end


local detection = {}

detection.onSimulateTime = 0

-- Per-actor suspicion progress: 0.0 (unseen) -> 1.0 (fully detected).
-- Read by stealthbar.lua.
detection.suspicion = {}

-- Per-actor detection state, updated on detectSneak ticks and in simulate.
-- [ref] = { rate, lastUpdate, inCombat, combatStarted, lastSeen, engineSynced }
detection.detectionState = {}

-- True while any tracked actor fully detects the player or fights them. Updated once per frame.
detection.expBlocked = false

-- Per-actor decay delay timers: while a timer is alive, decay is suppressed.
local decayTimers = {}

-- Light mechanic: interior light sources and whether the player is currently inside one.
local lightSources = {} -- { ref = tes3reference, radius = number }
local playerInLight = false
local lightCheckTimer = nil

-- Sneak transition tracking: used to detect when the player enters sneak mode.
local wasSneaking = false

-- How often (seconds) a hostile actor re-tests line of sight to the player while the player sneaks.
local HOSTILE_LOS_INTERVAL = 0.25

--- Seconds without a detectSneak tick before an actor counts as out of range.
--- The engine scans every (scanInterval + 1) seconds, so allow one and a half scan periods
--- plus slack: a single late tick must not start the decay.
---@return number
function detection.getStaleThreshold()
	return (config.aiUpdateTime + 1) * 1.5 + 0.5
end

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

--- Drop every piece of tracking state for an actor.
---@param ref tes3reference
local function forget(ref)
	detection.suspicion[ref] = nil
	detection.detectionState[ref] = nil
	if decayTimers[ref] then
		decayTimers[ref]:cancel()
		decayTimers[ref] = nil
	end
end

--- Write the engine's per-actor detection flags so vanilla and other mods agree with us.
---@param mob tes3mobileActor
---@param detected boolean
local function syncEngineFlags(mob, detected)
	mob.isPlayerDetected = detected
	mob.isPlayerHidden = not detected
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
		if not ref.disabled and light.radius and light.radius > 0 and not light.isNegative then
			table.insert(lightSources, { ref = ref, radius = light.radius })
		end
	end
	log:debug("[light] Scanned %d light sources in %s", #lightSources, cell.name or "?")
end

--- Check every 0.5s whether the player is within any cached light's radius.
local function checkPlayerLight()
	playerInLight = false
	if not config.lightMechanicEnabled then
		return
	end
	local playerPos = tes3.player.position
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
	if not config.lightMechanicEnabled then return end
	scanCellLights(cell)
	if #lightSources > 0 then
		lightCheckTimer = timer.start({ type = timer.simulate, duration = 0.5, iterations = -1, callback = checkPlayerLight })
	end
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
	detection.detectionState = {}
	detection.expBlocked = false
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
	-- getViewToActor: 0 = directly in front, +/-180 = directly behind
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

	-- Clamp to the configured floor and cap. Chameleon is applied by the callers.
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
	local bonus = config.stealSuspicionBonus / 100
	local current = math.min((detection.suspicion[ref] or 0) + bonus, 1.0)
	detection.suspicion[ref] = current
	restartDecayTimer(ref)
	e.block = true  -- suppress vanilla crime consequences
	log:debug("[crimeWitnessed] suppressed vanilla for %s: suspicion +%.2f -> %.2f", ref.id, bonus, current)
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

---@param actorMobile tes3mobileActor
---@return boolean
local function actorFightsPlayer(actorMobile)
	for _, actor in ipairs(actorMobile.hostileActors) do
		if actor.reference == tes3.player then
			return true
		end
	end
	return false
end

--- True if the actor should be treated as aware of the player: full suspicion, or already
--- fighting them. This is the mod's own answer and the only gate sneak strikes should use;
--- the engine's isPlayerDetected flag is cleared by any failed line-of-sight check and goes
--- stale beyond the engine's 2000-unit scan range.
---@param mobile tes3mobileActor|nil
---@return boolean
function detection.isDetectedBy(mobile)
	if not mobile then return false end
	local ref = mobile.reference
	if ref and (detection.suspicion[ref] or 0) >= 1 then
		return true
	end
	if not actorFightsPlayer(mobile) then
		return false
	end
	-- The engine starts combat from a hit *before* it rolls that hit and decides the crit, so
	-- an actor whose fight began this very frame was not aware when the blow landed.
	local state = ref and detection.detectionState[ref]
	return not (state and state.combatStartedAt == detection.onSimulateTime)
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

	local detectorType = e.detector.actorType
	if detectorType ~= tes3.actorType.npc and detectorType ~= tes3.actorType.creature then
		return
	end

	local detector = e.detector --[[@as tes3mobileNPC|tes3mobileCreature]]
	local ref = detector.reference

	local state = detection.detectionState[ref]

	-- Not sneaking and not magically concealed: vanilla's verdict stands. Hostile actors are
	-- kept at full suspicion by the combat pin in onSimulate, so no stamp is needed here.
	if not tes3.mobilePlayer.isSneaking and tes3.mobilePlayer.chameleon <= 0 and tes3.mobilePlayer.invisibility <= 0 then
		if state then
			state.inCombat = actorFightsPlayer(detector)
		end
		return
	end

	state = state or {}
	state.inCombat = actorFightsPlayer(detector)

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

	-- Hiding term: larger when the player is behind the actor.
	local angle = detector:getViewToActor(tes3.mobilePlayer)
	local angleFactor = getAngleFactor(angle)
	local hidingTerm = (1 - angleFactor) * config.hidingBonus

	-- Chameleon applies to the stale check only. state.rate was stored without it; onSimulate applies it there.
	local chameleon = tes3.mobilePlayer.chameleon or 0
	rate = rate * (1 - (chameleon / 100))

	-- Stamp the actor as active only if it could still gain suspicion.
	local shouldWeLetActorGoStale = math.clamp(rate - hidingTerm, 0, config.detCap)
	if shouldWeLetActorGoStale > 0 then
		state.lastUpdate = detection.onSimulateTime
	end

	detection.detectionState[ref] = state

	log:trace("[detectSneak] %s distance=%.0f rate=%.4f/s", ref.id, distance, rate)

	-- Replace vanilla's verdict with the suspicion model's.
	local previouslyDetected = detector.isPlayerDetected
	local detectedState = (detection.suspicion[ref] or 0) >= 1.0

	e.isDetected = detectedState
	syncEngineFlags(detector, detectedState)

	if detectedState and not previouslyDetected then
		log:debug("Detected by %s! Progress reached 1.0.", ref)
		event.trigger("SA_SO_detected", e)
	end
end
event.register(tes3.event.detectSneak, detectSneakCallback, { priority = 1000 })



local detectionExperienceTimer = 0

--- Simulate runs every frame. This is where time-based accumulation/decay happens,
--- matching the OpenMW approach: progress changes at velocity * dt, independent of
--- AI tick frequency.
---@param e simulateEventData
local function onSimulate(e)

	-- Mod clock: advances only while the game simulates.
	detection.onSimulateTime = detection.onSimulateTime + e.delta
	local now = detection.onSimulateTime

	if not config.modEnabled then
		return
	end

	-- On sneak start, seed suspicion on every actor that can see the player from the view angle and Sneak skill,
	-- so crouching in plain view does not reset detection.
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

					local state = detection.detectionState[ref] or {}
					state.lastUpdate = now
					state.rate = state.rate or config.detFloor
					state.engineSynced = false
					detection.detectionState[ref] = state

					-- Let the engine re-run its check so its flags match the seeded suspicion.
					local pm = tes3.worldController.mobManager.processManager
					pm:detectSneak(mob, tes3.mobilePlayer, true)
				end
			end
		end
	end
	wasSneaking = isSneaking

	-- Nothing to process if no actor is being tracked
	if not next(detection.suspicion) and not next(detection.detectionState) then
		detection.expBlocked = false
		return
	end

	local dt = e.delta
	-- Decay per second: full suspicion clears in decayTime seconds.
	local dv = 1.0 / config.decayTime
	local staleThreshold = detection.getStaleThreshold()

	-- Union of tracked actors.
	local toProcess = {}
	for ref in pairs(detection.suspicion) do
		toProcess[ref] = true
	end
	for ref in pairs(detection.detectionState) do
		toProcess[ref] = true
	end

	local standingStill = tes3.mobilePlayer.velocity:length() < 5
	local chameleon = tes3.mobilePlayer.chameleon or 0
	local invisible = tes3.mobilePlayer.invisibility > 0 or chameleon >= 100

	local gainExp = false  -- some actor is in a state that trains the player
	local blockExp = false -- some actor sees the player or fights them

	for ref in pairs(toProcess) do

		if not ref:isValid() then
			forget(ref)
			goto continue
		end

		local current = detection.suspicion[ref] or 0
		local state = detection.detectionState[ref] or {}
		local mob = ref.mobile --[[@as tes3mobileActor]]

		if mob then
			state.inCombat = actorFightsPlayer(mob)
		end
		local hostile = state.inCombat or false

		-- Combat pin: an actor fighting the player stays at full suspicion while it can see them,
		-- meaning the player is not sneaking or line of sight holds. After combatHidingTimer seconds
		-- out of sight, suspicion may decay and the actor eventually gives up (see cleanup below).
		local pinned = false
		if hostile then
			if not state.combatStarted then
				state.combatStarted = now
			end

			local seesPlayer = not isSneaking
			if not seesPlayer then
				if now >= (state.nextLosCheck or 0) then
					state.nextLosCheck = now + HOSTILE_LOS_INTERVAL
					state.losSeen = tes3.testLineOfSight({ reference1 = ref, reference2 = tes3.player })
				end
				seesPlayer = state.losSeen or false
			end

			if seesPlayer then
				state.lastSeen = now
			end
			local lastSeen = state.lastSeen or state.combatStarted
			pinned = (now - lastSeen) <= config.combatHidingTimer
		end

		if pinned then
			current = 1
			state.lastUpdate = now
			restartDecayTimer(ref)
		end

		-- Actors never stamped count as stale.
		local lastUpdate = state.lastUpdate
		local isStale = (lastUpdate == nil) or (now - lastUpdate) >= staleThreshold
		local active = not isStale

		if active and not hostile and current < 1 and isSneaking then
			gainExp = true
		end

		if hostile or current >= 1 then
			blockExp = true
		end

		if mob and active and not pinned then

			local angle = mob:getViewToActor(tes3.mobilePlayer)
			local angleFactor = getAngleFactor(angle)
			local rate = state.rate or config.detFloor

			-- Apply chameleon
			rate = math.clamp(rate * (1 - (chameleon / 100)), config.detFloor, config.detCap)

			-- Apply invisibility
			if invisible then
				rate = config.detFloor
			end

			if standingStill and (not playerInLight or invisible) then
				local hidingTerm = (1 - angleFactor) * config.hidingBonus
				rate = math.clamp(rate - hidingTerm, 0, config.detCap)
			end

			local delta = rate * dt / config.fillTime
			current = math.min(1.0, current + delta)

			restartDecayTimer(ref)
			log:trace("Suspicion up for %s: %.3f (+%.4f/frame) rate=%.4f/s", ref.id, current, delta, rate)
		elseif not decayTimers[ref] and not pinned then
			current = math.max(0.0, current - dv * dt)
			if current > 0 then
				log:trace("Suspicion down for %s: %.3f (-%.4f/frame)", ref.id, current, dv * dt)
			end
		end

		-- Engine sync while at full suspicion: re-run the engine's own detection routine so it
		-- reacts without waiting for its next AI tick. Runs on the transition, then every
		-- engineRecheckInterval seconds while the actor has line of sight (0 = every frame).
		if mob and current >= 1 then
			local firstTime = not state.engineSynced
			if firstTime or now >= (state.nextEngineCheck or 0) then
				state.nextEngineCheck = now + config.engineRecheckInterval
				local playerSeen = tes3.testLineOfSight({ reference1 = ref, reference2 = tes3.player })
				if playerSeen then
					if firstTime and not mob.isPlayerDetected and m1pe and config.shakeOnDiscovered then
						m1pe.doCameraShake("SO_Discovered", config.shakeSize, 0.0, 1.0, config.shakeSpeed, 0.8, 1, false, 0.0, true)
					end
					local pm = tes3.worldController.mobManager.processManager
					pm:detectSneak(mob, tes3.mobilePlayer, true)
				elseif firstTime then
					syncEngineFlags(mob, true)
				end
				state.engineSynced = true
			end
		else
			state.engineSynced = false
		end

		-- Clean up fully decayed actors.
		if current <= 0 and not active then
			if mob and mob.inCombat and state.combatStarted ~= nil then
				-- The actor lost the player: end the fight. The engine restores the actor's
				-- pre-combat AI routine itself, so no package is written here.
				log:debug("%s lost track of the player, stopping combat", ref.id)
				mob:stopCombat(true)
			end
			forget(ref)
		else -- Store the updated value.
			detection.suspicion[ref] = current
			detection.detectionState[ref] = state
		end
		::continue::
	end

	detection.expBlocked = blockExp

	if gainExp and not blockExp then
		detectionExperienceTimer = detectionExperienceTimer + dt
		if detectionExperienceTimer >= 1 then
			detectionExperienceTimer = 0
			experience.levelSneak(experience.Source.avoidDetection, 0)
		end
	end
end
event.register(tes3.event.simulate, onSimulate)

local function onDeath(e)
	local ref = e.reference
	if not ref then
		 return
	end
	forget(ref)
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

	-- Do not raise suspicion here. On a hit, the engine starts the victim's combat before it asks
	-- (through the detectSneak override) whether the victim was aware, to decide the crit. Raising
	-- suspicion now would suppress every ranged sneak crit. The combat pin in onSimulate raises it
	-- next frame and syncs the engine flags; combatStartedAt gives isDetectedBy the same-frame grace.
	local now = detection.onSimulateTime
	local state = detection.detectionState[ref] or {}
	state.inCombat = true
	state.combatStarted = now
	state.combatStartedAt = now
	state.lastSeen = now
	state.lastUpdate = now
	state.engineSynced = false
	detection.detectionState[ref] = state
	detection.suspicion[ref] = detection.suspicion[ref] or 0
end
event.register(tes3.event.combatStarted, onCombatStarted)


--- Returns the current suspicion level (0.0-1.0) for the given actor reference.
---@param ref tes3reference
---@return number
function detection.getSuspicion(ref)
	if ref and ref:isValid() then
		return detection.suspicion[ref] or 0
	end
	return 0
end

--- Adds suspicion to an actor, capped at 1.0. Restarts the decay delay timer.
---@param ref tes3reference
---@param amount number  0.0-1.0
function detection.addSuspicion(ref, amount)
	if ref and ref:isValid() then
		local current = math.min((detection.suspicion[ref] or 0) + amount, 1.0)
		detection.suspicion[ref] = current
		restartDecayTimer(ref)
	end
end

--- Clears all suspicion and tracking state for an actor immediately.
---@param ref tes3reference
function detection.clearSuspicion(ref)
	forget(ref)
end

return detection
