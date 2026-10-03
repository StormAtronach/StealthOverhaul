--- EXPERIMENTAL. NPC investigation: send an actor to a position, let it look around for a few
--- seconds, then walk it back to where it started. Loaded only when config.experimentalInvestigation
--- is on, and exposed as interop.investigation. Nothing in the mod triggers it yet.
---
--- Refactored from Celediel's More Attentive Guards sneak module. All credit for the original work
--- goes to Celediel.
local config = require("StormAtronach.SO.config")

local log = mwse.Logger.new({ moduleName = "investigation", level = config.logLevel })

local investigation = {}

-- One investigation per NPC at a time, as in Celediel's original.

--- Random idle weights; idle 5 (rubbing hands, showing wares) is kept at 0.
local function generateIdles()
    local idles = {}
    for i = 1, 4 do idles[i] = math.random(0, 60) end
    idles[5] = 0
    for i = 6, 8 do idles[i] = math.random(0, 60) end
    return idles
end

--- True if the NPC cannot act on an investigation right now.
---@param npcRef tes3reference
---@return boolean
local function cannotContinue(npcRef)
    local mob = npcRef.mobile
    if not mob then
        log:debug("NPC %s does not have a mobile", npcRef.id)
        return true
    end
    if mob.isKnockedDown or mob.isHitStunned or mob.isParalyzed or mob.isDead or mob.inCombat then
        log:debug("NPC %s can't continue", npcRef.id)
        return true
    end
    return false
end

--- Make the NPC wander around its current spot.
---@param npcRef tes3reference
function investigation.startWander(npcRef)
    if not (npcRef and npcRef.mobile) then
        log:debug("No ref or mobile in startWander")
        return
    end

    local wanderRange = config.wanderRangeInterior
    if npcRef.mobile.cell.isOrBehavesAsExterior then
        wanderRange = config.wanderRangeExterior
    end

    tes3.setAIWander({ reference = npcRef, range = wanderRange, reset = true, idles = generateIdles() })
end

--- Timer payloads hold safe handles, which cannot be serialised, so these timers do not persist
--- across saves. An investigation interrupted by a save simply ends where the NPC stands.
---@param e mwseTimerCallbackData
local function returnToOriginalPosition(e)
    local data = e.timer.data
    if not data then
        log:debug("Payload for returnToOriginalPosition is missing")
        return
    end

    local npcRefSH = data.npcRef
    if not npcRefSH:valid() then
        log:debug("Reference does not exist in returnToOriginalPosition")
        return
    end
    local npcRef = npcRefSH:getObject()
    tes3.setAITravel({ reference = npcRef, destination = data.originalPosition, reset = true })
end

--- Poll once per second until the NPC reaches its destination (or gives up), then wander for a
--- few seconds and head back.
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

    local npcRef = npcRefSH:getObject() --[[@as tes3reference]]
    local mob = npcRef.mobile
    if not mob or not mob.aiPlanner then
        log:debug("AI planner for %s is not active anymore", npcRef.id)
        return
    end

    -- Still travelling, or already arrived and wandering?
    local package = mob.aiPlanner.currentPackageIndex
    local travelling = package == tes3.aiPackage.travel
    local wandering = package == tes3.aiPackage.wander
    if not (travelling or wandering) then
        log:debug("NPC %s is neither travelling nor wandering anymore", npcRef.id)
        e.timer:cancel()
        return
    end

    if cannotContinue(npcRef) then
        log:debug("NPC %s can't continue travel", npcRef.id)
        e.timer:cancel()
        investigation.startWander(npcRef)
        return
    end

    local destination = data.destination or mob.position:copy()
    local remainingDistance = mob.position:distance(destination)

    if remainingDistance <= 5 or wandering then
        e.timer:cancel()
        investigation.startWander(npcRef)

        local investigationTime = math.random(3, 8)
        log:debug("NPC %s arrived; heading back in %d s", npcRef.id, investigationTime)

        timer.start({
            type = timer.simulate,
            duration = investigationTime,
            iterations = 1,
            callback = returnToOriginalPosition,
            data = { npcRef = tes3.makeSafeObjectHandle(npcRef), originalPosition = data.originalPosition },
        })
    end
end

--- Send the NPC to look at a position.
---@param npcRef tes3reference
---@param destination tes3vector3
---@return { originalPosition: tes3vector3, distance: number, duration: number }|nil
function investigation.startTravel(npcRef, destination)
    if not npcRef or not destination then
        log:debug("startTravel: missing npcRef=%s, missing destination=%s", tostring(not npcRef), tostring(not destination))
        return nil
    end
    if cannotContinue(npcRef) then
        log:debug("NPC %s is doing other stuff", npcRef.id)
        return nil
    end

    -- Keep swimming creatures in the water.
    if npcRef.object.swims then
        local waterLevel = tes3.player.cell.waterLevel or -20000
        if destination.z > waterLevel then
            log:debug("Not sending swimmer %s onto land", npcRef.id)
            return nil
        end
    end

    local aux = {}
    aux.originalPosition = npcRef.position:copy()
    aux.distance = npcRef.position:distance(destination)
    aux.duration = math.max(1, math.round(math.clamp(aux.distance / 50, config.minTravelTime, config.maxTravelTime), 0))

    local npcRefSH = tes3.makeSafeObjectHandle(npcRef)
    timer.delayOneFrame(function()
        if not npcRefSH:valid() then
            log:debug("NPC ref handle got invalidated before travel started")
            return
        end
        local ref = npcRefSH:getObject() --[[@as tes3reference]]
        tes3.setAITravel({ reference = ref, destination = destination })
    end)
    log:debug("Starting travel for NPC %s, duration %d s", npcRef.id, aux.duration)

    timer.start({
        type = timer.simulate,
        duration = 1,
        iterations = aux.duration,
        callback = checkDestination,
        data = { npcRef = npcRefSH, destination = destination, originalPosition = aux.originalPosition },
    })
    return aux
end

return investigation
