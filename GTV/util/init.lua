local config = require("StormAtronach.GTV.config")
local log = mwse.Logger.new({
	name = "Grand Theft Vvardenfell",
	level = config.logLevel,
})


local util = {}

local factionList = {}

-- This function updates the faction list, which is used to determine if an item belongs to a faction or an NPC.
function util.updateFactionList()
local factions = tes3.dataHandler.nonDynamicData.factions
factionList = {}
for _, faction in pairs(factions) do
    factionList[faction.id] = true
end
return factionList
end



-- We reset the player data to blank
function util.resetData()
    tes3.player.data.SA_GTV = {}
    local data = tes3.player.data.SA_GTV
    data.npcs                   = {}
        data.npcs.items             = {}
        data.npcs.value             = 0
        data.npcs.lastTime          = 0
    data.factions               = {}
        data.factions.items         = {}
        data.factions.value         = 0
        data.factions.lastTime      = 0
    data.currentCrime           = {}
        data.currentCrime.value     = 0
        data.currentCrime.size      = 0
        data.currentCrime.npcs      = {}
        data.currentCrime.factions  = {}
        data.currentCrime.cells     = {}
    
    return data
end

-- Return the data container for the mod or initialize it
function util.getData()
    if tes3.player.data.SA_GTV then
        return tes3.player.data.SA_GTV
    else
        local data = util.resetData()
        return data
    end
end

-- Reset the current crime
function util.resetCurrentCrime()
    local data = util.getData()
    data.currentCrime           = {}
        data.currentCrime.value     = 0
        data.currentCrime.size      = 0
        data.currentCrime.npcs      = {}
        data.currentCrime.factions  = {}
        data.currentCrime.cells     = {}
end


-- Get the max size of an object, defined as the longest dimension
function util.getMaxSize(item)
    if not item.boundingBox then log:debug("Get Max Size: Item does not have a bounding box") return 0 end
    local bBox = item.boundingBox
    local maxSize = math.round(math.max(bBox.max.x - bBox.min.x, bBox.max.y - bBox.min.y, bBox.max.z - bBox.min.z),2)
    return maxSize or 0
end

---@class updateDataParams
---@field ownerID string
---@field itemID string
---@field size number|nil
---@field count number|nil
---@field value number|nil

-- Update thieving victims long term memory
---@param p updateDataParams
function util.updateData(p)
    local ownerID = p.ownerID -- The ownner id
    if not ownerID then log:debug("No owner id given") return false end
    local itemID = p.itemID
    if not itemID then log:debug("No owner id given") return false end
    local size = p.size or 0
    local count = p.count or 0
    local value = p.value or 0
    local data = util.getData()
    local TS = tes3.getSimulationTimestamp()

    -- Data handling nightmare ahead
	if factionList[ownerID] then --Here is to hoping that factionList has not changed since the game was loaded.
		-- If there is already a table created, great. If not, add an empty one
                data.factions[ownerID] = data.factions[ownerID] or {}
		-- Now, for the items themselves. If an item not already listed, then create a new subtable
		if not  data.factions[ownerID].items[itemID] then
				data.factions[ownerID].items[itemID] = {value = value, size = size, count = count, timestamp = TS}
		else -- and if it already exists, increase the count
				data.factions[ownerID].items[itemID].count = (data.factions[ownerID].items[itemID].count or 0) + count
                data.factions[ownerID].items[itemID].timestamp = TS
		end
		-- Now we increase the value registry
				data.factions[ownerID].value = (data.factions[ownerID].value or 0) + value*count
	else -- Same thing for the NPCs
				data.npcs[ownerID] = data.npcs[ownerID] or { items = {}, value = 0 }
		if not  data.npcs[ownerID].items[itemID] then
				data.npcs[ownerID].items[itemID] = {value = value, size = size, count = count, timestamp = TS}
		else
				data.npcs[ownerID].items[itemID].count = (data.npcs[ownerID].items[itemID].count or 0) + count
                data.npcs[ownerID].items[itemID].timestamp = TS
		end
				data.npcs[ownerID].value = (data.npcs[ownerID].value or 0) + value*count
	end
end

-- Let's check the inventory for stolen items
function util.checkInventoryForStolenItems()
    -- Set up the auxiliary data structure
    local   auxData = {}
            auxData.npcs        = {}
            auxData.factions    = {}
            auxData.size        = 0
            auxData.value       = 0

    -- Scan the player's inventory for stolen items. Still have to figure out how to go through the ashfall containers.
    for _,  stack in pairs(tes3.player.object.inventory) do

        local item  = stack.object
        if  tes3.getItemIsStolen({item = item}) then
            local size      = util.getMaxSize(item) or 0
            --local baseObject= tes3.getObject(item.id)
            local value     = tes3.getValue({item = item}) or 0
            local count     = stack.count or 1
            auxData.size    = auxData.size  + size*count
            auxData.value   = auxData.value + value*count


            for _, owner in pairs(item.stolenList) do
                local id = owner.id:lower()
                if factionList[id] then
                    auxData.factions[id] = auxData.factions[id] or { items = {}, value = 0 }
                    if not  auxData.factions[id].items[item.id] then
                            auxData.factions[id].items[item.id] = {value = value, size = size, count = count}
                    else
                            auxData.factions[id].items[item.id].count = (auxData.factions[id].items[item.id].count or 0) + count
                    end
                    auxData.factions[id].value  = (auxData.factions[id].value or 0) + value*count
                else
                    auxData.npcs[id] = auxData.npcs[id] or { items = {}, value = 0 }
                    if not  auxData.npcs[id].items[item.id] then
                            auxData.npcs[id].items[item.id] = {value = value, size = size, count = count}
                    else
                            auxData.npcs[id].items[item.id].count = (auxData.npcs[id].items[item.id].count or 0) + count
                    end
                    auxData.npcs[id].value      = (auxData.npcs[id].value     or 0) + value*count
                end
            end
        end
    end
    return auxData
end

function util.updateCurrentCrime()
    local auxData = util.checkInventoryForStolenItems()
    local data = util.getData()
    data.currentCrime.value     = auxData.value
    data.currentCrime.size      = auxData.size
    data.currentCrime.npcs      = {}
    data.currentCrime.npcs      = table.deepcopy(auxData.npcs)
    data.currentCrime.factions  = {}
    data.currentCrime.factions  = table.deepcopy(auxData.factions)
end
     

function util.gotCaught(npcID)
    util.updateCurrentCrime() -- Ensure current crime is updated
    local data = util.getData()
    local npcRef = tes3.getReference(npcID)

    -- Obsesively nil checking everything to avoid crashes:
    if not npcRef or not npcRef.object or not npcRef.object.name then
        log:debug("Invalid NPC reference for %s", npcID)
        return
    end

    local npcItems = data and data.currentCrime and data.currentCrime.npcs and data.currentCrime.npcs[npcRef.object.name:lower()] or nil
    if not npcItems then
        log:debug("No data for NPC %s", npcID)
        return
    end

    tes3.messageBox({message = "HEY! That's not yours, N'wah!",
    buttons = {"Give items back", "The best witness is a dead witness!!"},
        showInDialog = false,
        callback = function (e)
            if e.button == 0 then
                -- Player chose to give items back
                for itemID, v in pairs(npcItems.items) do
                    tes3.removeItem({
                        reference = tes3.player,
                        item = itemID,
                        count = v.count or 1,
                    })
                    tes3.addItem({
                        reference = npcRef,
                        item = itemID,
                        count = v.count or 1,
                    })
                end
                tes3.updateInventoryGUI({reference = tes3.player}) -- Update the inventory GUI to reflect changes
                util.updateCurrentCrime() -- Update the current crime after giving items back
                tes3.messageBox("You returned the stolen items to %s.", npcID)
            else
                -- Player chose to fight
                tes3.messageBox("You chose to fight %s!", npcID)
                tes3.triggerCrime({
                    type = tes3.crimeType.theft,
                    value = npcItems.value or 0,
                    victim = npcRef,
                    forceDetection = true,
                })
            end
        end,})
end


return util

