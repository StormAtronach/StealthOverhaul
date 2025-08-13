local config = require("StormAtronach.GTV.config")
local interop = require("StormAtronach.GTV.interop")

local log = mwse.Logger.new({
	name = "Grand Theft Vvardenfell",
	level = config.logLevel,
})

local detectedActors = {}

--- @param e simulateEventData
local function simulateCallback(e)
    -- If there is nothing in the table, bye bye event
    if not next(detectedActors) then return end

    -- Check if the cooldowns are done
    local auxKeys = {}
    for actor, osTS in pairs(detectedActors) do
        if (os.clock() - osTS) > config.detectionCooldwon then
            table.insert(auxKeys, actor)
        end
    end
    -- And now, delete the ones that are done
    for _,v in ipairs(auxKeys) do
        detectedActors[v] = nil
    end

end
event.register(tes3.event.simulate, simulateCallback)




--- @param e detectSneakEventData
local function detectSneakCallback(e)
    -- If not detecting the player, no problem
	if e.target ~= tes3.mobilePlayer then return end
    -- Combat is a bad time for stealth
    if tes3.mobilePlayer.inCombat then return end
    -- If you have been already detected, no need to run the logic again
    if detectedActors[e.detector.object.id] then return end


	local sawYou = tes3.testLineOfSight({reference1 = e.detector.reference, reference2 = e.target.reference})
    if sawYou then
        local detectorEye = e.detector.position:copy()
        detectorEye.z = detectorEye.z + e.detector.height
        local playerEye = tes3.getPlayerEyePosition()
        local angle = config.detectionAngle or 80 -- degrees
        
        -- Calculate the angle between the detector's view vector and the player's position
        local viewAngle = math.abs(e.detector:getViewToPoint(playerEye))
        
        -- If the angle is less than the threshold, the player is detected
        if viewAngle < angle then
       -- createLineRed( detectorEye, playerEye,"sneakDetectionRed")
        tes3.messageBox("You were detected by: %s", e.detector.reference.id)
        util.gotCaught(e.detector.reference.id)
        else
       -- createLineGreen( detectorEye, playerEye, "sneakDetectionGreen")
        tes3.messageBox("You were NOT detected by: %s", e.detector.reference.id)
        end
    end
end
event.register(tes3.event.detectSneak, detectSneakCallback)