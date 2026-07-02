local detection = require("StormAtronach.SO.detection")
local experience = require("StormAtronach.SO.experience")
local config = require("StormAtronach.SO.config")
local accessedReferences = {}

--- @param target tes3reference
local function targetAllowedToGiveXP(target)
    local obj = target.object
    if target.lockNode and target.lockNode.level > 0 then
        return false
    end
    if obj.objectType == tes3.objectType.container then
        if config.containersGiveXP then
            return true
        end
        return false
    end
    if not target.context
    and obj.objectType ~= tes3.objectType.npc
    and obj.objectType ~= tes3.objectType.creature
    and obj.objectType ~= tes3.objectType.activator then
        return true
    end
    return false
end

local function playerAllowedXP()
    local staleThreshold = config.aiUpdateTime * 2 + 0.5 + config.bonusStealWindow
    for ref, state in pairs(detection.detectionState) do
        ---@type tes3reference
        local r = ref

        local isStale = (state.lastUpdate == nil) or (detection.onSimulateTime - state.lastUpdate) >= staleThreshold

        if not isStale and r:isValid() and r.cell == tes3.player.cell then
            return true
        end
    end
    return false
end

--- @param e activateEventData
local function activateCallback(e)
    if e.activator ~= tes3.player then return end
    if not tes3.mobilePlayer.isSneaking or tes3.mobilePlayer.isPlayerDetected then return end
    if tes3.hasOwnershipAccess { target = e.target } then return end

    if targetAllowedToGiveXP(e.target) and playerAllowedXP() then
        local data = e.target.tempData.StealthOverhaul
        if not data or not data.accessed then
            e.target.tempData.StealthOverhaul = {}
            e.target.tempData.StealthOverhaul.accessed = true
            table.insert(accessedReferences, e.target)
            experience.levelSneak(experience.Source.stealItem, 0)
        end
    end
end
event.register(tes3.event.activate, activateCallback)

--- @param e cellChangedEventData
local function cellChangedCallback(e)
    for _, ref in ipairs(accessedReferences) do
        if ref:isValid() then
            ref.tempData.StealthOverhaul = {}
        end
    end
    accessedReferences = {}
end
event.register(tes3.event.cellChanged, cellChangedCallback)