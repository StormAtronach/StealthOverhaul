--- Debug helpers: draw a coloured line in the world between two points.
--- Loaded by util only when config.debugLines is on.
local debugLines = {}

---@param origin tes3vector3
---@param destination tes3vector3
---@param widget_name string
---@param color niPackedColor
local function drawLine(origin, destination, widget_name, color)
    local root = tes3.worldController.vfxManager.worldVFXRoot
    local line = root:getObjectByName(widget_name)

    if line == nil then
        local mesh = tes3.loadMesh("mwse\\widgets.nif")
        if not mesh then return end
        local axisLines = mesh:getObjectByName("axisLines")
        local z = axisLines and axisLines:getObjectByName("z")
        if not z then return end
        line = z:clone()
        line.name = widget_name
        root:attachChild(line, true)
    end
    ---@cast line niTriShape
    line.data.vertices[1] = origin
    line.data.vertices[2] = destination
    line.data.colors[1] = color
    line.data.colors[2] = color
    line.data:markAsChanged()
    line.data:updateModelBound()
    line:update()
    line:updateEffects()
    line:updateProperties()
end

function debugLines.createLineRed(origin, destination, widget_name)
    drawLine(origin, destination, widget_name or "raytest_debug_widget_red", niPackedColor.new(255, 0, 0))
end

function debugLines.createLineGreen(origin, destination, widget_name)
    drawLine(origin, destination, widget_name or "raytest_debug_widget_green", niPackedColor.new(0, 255, 0))
end

return debugLines
