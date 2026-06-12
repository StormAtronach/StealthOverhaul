local experience = {}
local allowLeveling = false
local config = require("StormAtronach.SO.config")

local hasPickpocket = tes3.isLuaModActive("Pickpocket")

-- Make enum table and make sure it's not editable
local function readOnly (t)
    return setmetatable(t, {
        __newindex = function()
            error("No modification possible. List is readonly", 2)
        end,
        __metatable = false
    })
end

---@class ExperienceSource
---@field avoidDetection 0
---@field stealItem 1
---@field pickPocket 1
---@field sneakStrike 2
---@field interop 3

---@type ExperienceSource
experience.Source = readOnly({
    avoidDetection = 0,
    stealItem = 1,
    pickPocket = 2,
    sneakStrike = 3,
    interop = 4
})

---@param e exerciseSkillEventData
local function onExerciseSkill(e)
    
    if allowLeveling then
        allowLeveling = false
        tes3.messageBox(string.format("Gained %0.3f sneak XP", e.progress))
        return
    end
    e.block = true
end
event.register(tes3.event.exerciseSkill, onExerciseSkill, { filter = tes3.skill["sneak"], priority = -10000 })

---@param source integer Using the enum experience.Source
---@param amount number use only if needed during interop. Set to 0 if not using the interop option.
function experience.levelSneak(source, amount)
    local exp = 0
    if source == experience.Source.avoidDetection then
        exp = 0.03 * config.detectionExpMultiplier
    elseif source == experience.Source.stealItem then
        exp = 1 * config.stealItemExpMultiplier
    elseif source == experience.Source.pickPocket then
        exp = 2 * config.pickPocketExpMultiplier
    elseif source == experience.Source.sneakStrike then
        exp = 5 * config.sneakStrikeExpMultiplier
    end

    if amount > 0 and source == experience.Source.interop then
        exp = amount * config.interopExpMultiplier
    end

    allowLeveling = true
    tes3.mobilePlayer:exerciseSkill(tes3.skill["sneak"], exp)
end

--- @param e pickpocketEventData
local function pickpocketCallback(e)
    if not hasPickpocket then
        experience.levelSneak(experience.Source.pickPocket, 0)
    end
end
event.register(tes3.event.pickpocket, pickpocketCallback)

return experience