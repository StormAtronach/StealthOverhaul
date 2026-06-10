local experience = {}
local allowLeveling = false

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
---@field pickPocket 2
---@field sneakStrike 3

experience.Source = readOnly({
    avoidDetection = 0,
    stealItem = 1,
    pickPocket = 2,
    sneakStrike = 3
})

local function onExerciseSkill(e)
    if allowLeveling then
        allowLeveling = false
        return
    end
    e.block = true
end
event.register(tes3.event.exerciseSkill, onExerciseSkill, { skill = tes3.skill["sneak"], priority = -10000 })

---@param source ExperienceSource
function experience.levelSneak(source)
    local exp = 1
    if source == experience.Source.avoidDetection then
        exp = 1
    elseif source == experience.Source.stealItem then
        exp = 1
    elseif source == experience.Source.pickPocket then
        exp = 1
    elseif source == experience.Source.sneakStrike then
        exp = 1
    end
    allowLeveling = true
    tes3.mobilePlayer:exerciseSkill(tes3.skill["sneak"], exp * 1)
end

return experience