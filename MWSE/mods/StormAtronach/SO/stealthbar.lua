local config = require("StormAtronach.SO.config")
local detection = require("StormAtronach.SO.detection")

local log = mwse.Logger.new({ moduleName = "stealthbar", level = config.logLevel })

local MARKER_FRAME_COUNT = 21

-- Crosshair: 21 UI image elements stacked inside MenuMulti; one visible at a time
local crosshairFrames = {} -- [1..21] = tes3uiElement
local crosshairActiveFrame = nil
local crosshairDisplayFrame = nil -- float; smoothed toward target for animated transitions
local crosshairParent = nil
local vanillaCulledByUs = false
local crosshairCurrentFade =  0 -- Float; used to track current crosshair alpha


local function lerp(start, goal, alpha)
    return start + (goal - start)*alpha
end

--- Map suspicion level to one of five discrete crosshair frames at fixed thresholds.
---@param suspicion number  0.0–1.0
---@return number  frame index (1 = open, 21 = closed)
local function quantizeFrame(suspicion)
	if suspicion >= 1.0 then
		return 1
	end
	if suspicion >= 0.75 then
		return 6
	end
	if suspicion >= 0.50 then
		return 11
	end
	if suspicion >= 0.25 then
		return 16
	end
	return 21
end

local function getVanillaCrosshairNode()
	local nc = tes3.worldController.nodeCursor
	return nc and nc.children[1]
end

---@param frameIndex number|nil  1–21 to show that frame, nil to hide all
local function setCrosshairFrame(frameIndex)
	if frameIndex == crosshairActiveFrame then
		return
	end
	-- Hide the previously active frame
	if crosshairActiveFrame and crosshairFrames[crosshairActiveFrame] then
		crosshairFrames[crosshairActiveFrame].visible = false
	end
	local vanillaNode = getVanillaCrosshairNode()
	if frameIndex and crosshairFrames[frameIndex] then
		crosshairFrames[frameIndex].visible = true
		if vanillaNode and not config.keepVanillaCrosshair and not vanillaNode.appCulled then
			vanillaNode.appCulled = true
			vanillaCulledByUs = true
		end
		log:trace("[crosshair] frame %d", frameIndex)
	else
		if vanillaNode and vanillaCulledByUs then
			vanillaNode.appCulled = false
			vanillaCulledByUs = false
		end
	end
	crosshairActiveFrame = frameIndex
	if crosshairParent then
		crosshairParent:updateLayout()
	end
end

local function setFlipFrame(textureProperty, frameIndex)
	local ctrlTime = (frameIndex - 1) / MARKER_FRAME_COUNT
	textureProperty.controller.phase = 1 - ctrlTime
end

local function createCrosshair()
	if crosshairParent == nil then
		log:debug("[crosshair] no parent found, aborting crosshair creation")
		return
	end

	local existing = crosshairParent:findChild("SA_SO_crosshair_block")
	if existing then
		existing:destroy()
	end
	crosshairFrames = {}
	crosshairActiveFrame = nil

	local block = crosshairParent:createBlock{ id = "SA_SO_crosshair_block" }
	block.layoutOriginFractionX = 0.5
	block.layoutOriginFractionY = 0.5
	block.autoWidth = true
	block.autoHeight = true
	block.consumeMouseEvents = false

	local size = config.crosshairSize
	for i = 1, MARKER_FRAME_COUNT do
		local img = block:createImage({ path = string.format("textures/sa_so_ch_%d/%d.dds", size, i) })
		img.visible = false
		img.consumeMouseEvents = false
		img.scaleMode = true
		img.width = size * config.crosshairScale
		img.height = size * config.crosshairScale
		crosshairFrames[i] = img
	end

	crosshairParent:updateLayout()
	log:debug("[crosshair] UI overlay created with %d frames", MARKER_FRAME_COUNT)
end

local function onMenuMultiActivated(e)
	if not e.newlyCreated then
		return
	end
	crosshairParent = e.element
	createCrosshair()
end
event.register("uiActivated", onMenuMultiActivated, { filter = "MenuMulti" })
event.register("SA_SO_crosshairRecreate", createCrosshair)

local BAR_WIDTH = 50
local BAR_HEIGHT = 8
-- How far above the projected head point to draw the bar (in screen fraction)
local BAR_Y_OFFSET = 0.04

-- Pool of per-actor bar menus: [actorId] = { menu, fillbar }
local barPool = {}

-- === 3-D suspicion marker (billboard sneak eye) ===
local MARKER_MESH = "sa_so/sa_se.nif"
local MARKER_Z = 145

-- [actorId] = { node = niNode, ref = tes3reference, texProp = niTexturingProperty, flipCtrl = niTimeController|nil }
local markerPool = {}
local markerTemplate
local markerTextures -- niSourceTexture[1..21], pre-loaded once

local markerDisplayFrame = {} -- Table of floats, used per marker same way as crosshairDisplayFrame
local markerCurrentAlpha = {} -- table of floats, used per marker same way as crosshairCurrentFade


local function loadMarkerTextures()
	if markerTextures then
		return markerTextures
	end
	markerTextures = {}
	for i = 1, MARKER_FRAME_COUNT do
		markerTextures[i] = niSourceTexture.createFromPath(string.format("textures/sa_so/%d.dds", i))
	end
	log:debug("[marker] Pre-loaded %d textures", MARKER_FRAME_COUNT)
	return markerTextures
end

local function getMarkerTemplate()
	if not markerTemplate then
		markerTemplate = tes3.loadMesh(MARKER_MESH)
		loadMarkerTextures()
	end
	return markerTemplate
end


---@param ref tes3reference  The reference to attach marker to
---@param actorId string  The actor's reference Id to store data properly
local function attachMarker(ref, actorId)
	local markerData = markerPool[actorId]
	if markerData then
		return markerData.node
	end
	if not ref.sceneNode then
		return nil
	end
	local tmpl = getMarkerTemplate()
	if not tmpl then
		return nil
	end

	local node = tmpl:clone()
	local shape = node:getObjectByName("eye_plane")
	if shape then
    	local mat = shape.materialProperty
    	if mat then
        	shape.materialProperty = mat:clone()
		end
	end

	local markerHeight = MARKER_Z
	local actor = ref.attachments.actor
	local isCreature = actor.actorType == tes3.actorType.creature
	if isCreature then
		markerHeight = actor.boundSize.z + 20
	end

	node.name = "SA_SO_Marker_" .. actorId
	node.translation = tes3vector3.new(0, 0, markerHeight)
	node.appCulled = true

	local weight = ref.object.weight or 1
	local height = ref.object.height or 1

	local scaleWeight = 1 / weight
	local scaleHeight = 1 / height
	local scale = tes3vector3.new(scaleWeight, scaleWeight, scaleHeight)

	local r = node.rotation
	node.rotation = tes3matrix33.new(r.x * scale, r.y * scale, r.z * scale)

	ref.sceneNode:attachChild(node, true)
	ref.sceneNode:update()
	ref.sceneNode:updateEffects()

	---@diagnostic disable-next-line: param-type-mismatch
	local shape = node:getObjectByName("eye_plane") --[[@as niTriShape]]
	local texProp = shape and shape.texturingProperty --[[@as niTexturingProperty]]
	local flipCtrl = shape and shape.controller --[[@as niTimeController]]
	markerPool[actorId] = { node = node, ref = ref, texProp = texProp, flipCtrl = flipCtrl}
	log:debug("Attached sneak eye marker to %s", actorId)

	return node
end

local function detachMarker(actorId)
	local markerData = markerPool[actorId]
	if not markerData then
		return
	end
	local ref = markerData.ref
	if ref and ref.sceneNode then
		ref.sceneNode:detachChild(markerData.node)
		ref.sceneNode:update()
	end
	markerPool[actorId] = nil
	log:debug("Detached suspicion marker from %s", actorId)
end

-- Smooth display state: [actorId] = { display: number }
local displayState = {}

-- Exponential smoothing coefficients (per-second; higher = faster approach).
-- k=2 rising: ~86% of target reached per second - smooth build-up.
-- k=4 falling: ~98% of target reached per second - snappy drop.
local SMOOTH_RISE = 2
local SMOOTH_FALL = 4

--- Exponential smooth toward the authoritative suspicion value.
--- Never overshoots; uses frame delta so it's framerate-independent.
---@param actorId string
---@param dt number  frame delta in seconds (e.delta from simulate event)
local function getDisplayValue(actorId, dt)
	local actual = detection.suspicion[actorId] or 0
	local state = displayState[actorId]

	if not state then
		if actual <= 0 then
			return 0
		end
		displayState[actorId] = { display = actual }
		return actual
	end

	local k = actual >= state.display and SMOOTH_RISE or SMOOTH_FALL
	local alpha = 1 - math.exp(-k * dt)
	local display = state.display + (actual - state.display) * alpha

	-- Threshold was 0.5 (old 0–100 scale); corrected to 0.005 for 0–1 scale
	if display < 0.005 and actual <= 0 then
		displayState[actorId] = nil
		return 0
	end

	state.display = display
	log:trace("[bar] %s actual=%.3f display=%.3f", actorId, actual, display)
	return display
end

--- Project a world position to normalized screen coords (0–1, top-left origin).
--- Returns {x, y}, or nil if outside the view frustum.
---@return {x: number, y: number}|nil
local function worldToScreen(worldPos)
	local cameraData = tes3.worldController.worldCamera.cameraData
	if not cameraData then
		return nil
	end
	local camera = cameraData.camera
	if not camera then
		return nil
	end
	-- Returns tes3vector2 in screen space (origin at center, Y up). nil = outside frustum.
	local sp = camera:worldPointToScreenPoint(worldPos)
	if not sp then
		return nil
	end
	local width, height = tes3.getViewportSize()
	return {
		x = sp.x / width + 0.5,
		y = 0.5 - sp.y / height, -- flip: niCamera Y up → screen Y down
	}
end

--- Return an existing HelpLayerMenu bar for actorId, or create a new one.
local function getOrCreateBar(actorId)
	if barPool[actorId] then
		return barPool[actorId]
	end

	local menuId = tes3ui.registerID("SA_SO_SuspicionBar:" .. actorId)

	-- Destroy any leftover from a previous session
	local existing = tes3ui.findHelpLayerMenu(menuId)
	if existing then
		existing:destroy()
	end

	-- One HelpLayerMenu per actor - positioned each frame via absolutePosAlignX/Y.
	-- The menu is slightly larger than the fill so there's a dark background border.
	local menuW = BAR_WIDTH + 4
	local menuH = BAR_HEIGHT + 4

	local barMenu = tes3ui.createHelpLayerMenu({ id = menuId, fixedFrame = true })
	barMenu:destroyChildren()
	barMenu.disabled = true -- don't intercept input
	barMenu.color = { 0.05, 0.05, 0.05 }
	barMenu.alpha = 0.85
	barMenu.autoWidth = false
	barMenu.autoHeight = false
	barMenu.width = menuW
	barMenu.height = menuH
	barMenu.visible = false

	local fillbar = barMenu:createFillBar({})
	fillbar.autoWidth = false
	fillbar.autoHeight = false
	fillbar.width = BAR_WIDTH
	fillbar.height = BAR_HEIGHT
	-- Center the fill within the (slightly larger) menu container
	fillbar.absolutePosAlignX = 0.5
	fillbar.absolutePosAlignY = 0.5
	fillbar.widget.showText = false
	fillbar.widget.max = 100
	fillbar.widget.current = 0

	barMenu:updateLayout()

	barPool[actorId] = { menu = barMenu, fillbar = fillbar }
	return barPool[actorId]
end

local function destroyAllBars()
	-- The engine destroys all UI elements during loading, so we must not call
	-- destroy() here - doing so crashes on an already-freed pointer.
	-- Just drop our references; the engine handles cleanup.
	barPool = {}
	displayState = {}
	markerPool = {}
	crosshairFrames = {}
	markerDisplayFrame = {}
	markerCurrentAlpha = {}
	crosshairActiveFrame = nil
	crosshairDisplayFrame = nil
	log:debug("Bar and marker pools reset on load")
	createCrosshair()
end
event.register(tes3.event.loaded, destroyAllBars)


local function smoothFrame(displayFrame, targetFrame, speed, dt)
	local alpha = 1 - math.exp(-speed * dt)
	displayFrame = displayFrame + (targetFrame - displayFrame) * alpha

	if math.abs(displayFrame - targetFrame) < 0.5 then
    	displayFrame = targetFrame
	end

	return displayFrame
end

local function fadeMarker(actorId, targetAlpha, speed, dt)
	local markerData = markerPool[actorId]
	if not markerData then
		return
	end
	
	local currentAlpha = markerCurrentAlpha[actorId] or 0
	currentAlpha = lerp(currentAlpha, targetAlpha, 1 - math.exp(-dt * speed))
	currentAlpha = math.clamp(currentAlpha, 0, 1)
	markerCurrentAlpha[actorId] = currentAlpha

	local eye_plane = markerData.node:getObjectByName("eye_plane")
	if eye_plane and eye_plane.materialProperty then
		eye_plane.materialProperty.alpha = currentAlpha
		eye_plane:updateProperties()
	end
end

local function maybeDetachMarker(actorId, targetAlpha, markersToDetach)
    local markerData = markerPool[actorId]
    if not markerData then return end
    if markerCurrentAlpha[actorId] <= 0.01 and (not targetAlpha or targetAlpha == 0) then
        markerData.node.appCulled = true
        
        markerDisplayFrame[actorId] = nil
        markerCurrentAlpha[actorId] = nil

		table.insert(markersToDetach, actorId)
        return true
    else
        markerData.node.appCulled = false
    end
end

---@param e simulateEventData
local function onSimulate(e)
	-- Hide all bars first
	for _, bar in pairs(barPool) do
		bar.menu.visible = false
	end
	
	if not config.modEnabled then
		setCrosshairFrame(nil)
		for actorId in pairs(markerPool) do
			local markerData = markerPool[actorId]
			if markerData then
				markerData.node.appCulled = true
				detachMarker(actorId)
				markerDisplayFrame[actorId] = nil
				markerCurrentAlpha[actorId] = nil
			end
		end
		for actorId, bar in pairs(barPool) do
			if bar then
				bar.menu:destroy()
				barPool[actorId] = nil
				log:debug("Destroyed suspicion bar for %s (left proximity)", actorId)
			end
		end
		for actorId in pairs(displayState) do
			displayState[actorId] = nil
		end
		return
	end

	local dt = e.delta

	-- Crosshair: quantized sneak eye with optional animated transitions
	crosshairDisplayFrame = crosshairDisplayFrame or MARKER_FRAME_COUNT
	local crosshairFrameIndex

	if config.crosshairColorEnabled and tes3.mobilePlayer.isSneaking then
		local maxSuspicion = 0
		for _, s in pairs(detection.suspicion) do
			if s > maxSuspicion then
				maxSuspicion = s
			end
		end
		local targetFrame = quantizeFrame(maxSuspicion)
		if config.crosshairAnimated then
			local isOpening = targetFrame < crosshairDisplayFrame
			local speed = isOpening and config.crosshairOpenSpeed or config.crosshairCloseSpeed
			crosshairDisplayFrame = smoothFrame(crosshairDisplayFrame, targetFrame, speed, dt)
			crosshairFrameIndex = math.clamp(math.round(crosshairDisplayFrame), 1, MARKER_FRAME_COUNT)
		else
			crosshairDisplayFrame = targetFrame
			crosshairFrameIndex = targetFrame
		end
	else
		crosshairDisplayFrame = smoothFrame(crosshairDisplayFrame, MARKER_FRAME_COUNT, config.crosshairCloseSpeed, dt)
		crosshairFrameIndex = math.clamp(math.round(crosshairDisplayFrame), 1, MARKER_FRAME_COUNT) 
	end

	if crosshairFrameIndex then
		setCrosshairFrame(crosshairFrameIndex)
	end
	
	-- Crosshair: Fade in and out logic
	local crosshairTargetFade = config.crosshairColorEnabled and tes3.mobilePlayer.isSneaking and 1 or 0
	if crosshairParent then
		crosshairCurrentFade = lerp(crosshairCurrentFade, crosshairTargetFade, 1 - math.exp(-dt * 10))
		if crosshairActiveFrame and crosshairFrames[crosshairActiveFrame] then
			crosshairFrames[crosshairActiveFrame].alpha = crosshairCurrentFade
		end
	end

	-- TO DO: Evaluate if this is relevant or not
	if tes3ui.menuMode() then
		return
	end

	local mobilePlayer = tes3.mobilePlayer
	if not mobilePlayer then
		return
	end

	local actorsInRange = tes3.findActorsInProximity({ reference = tes3.player, range = config.barRange })
	-- Track which actors are in range this frame so we can clean up stale markers
	local seenActors = {}
	local markersToDetach = {}


	for _, actor in pairs(actorsInRange) do
		---@cast actor tes3mobileNPC
		if actor == tes3.mobilePlayer then
			goto continue
		end

		local ref = actor.reference
		if not ref then
			goto continue
		end

		local actorId = ref.id
		local suspicionValue = getDisplayValue(actorId, dt)
		seenActors[actorId] = true

		-- === 3-D marker ===
		log:trace("[marker] %s suspicionValue=%.3f", actorId, suspicionValue)

		local markerData = markerPool[actorId]
		-- Make sure things have markers
		if config.markerEnabled then
			if not markerData then
				if suspicionValue > 0 then
					local marker = attachMarker(ref, actorId)
					if marker then
						markerData = markerPool[actorId]
					end
				end
			end
			-- Make sure we have a proper markerData to work with (start a new if statement to act on a newly created marker too)
			if markerData then
				markerData.node.appCulled = false
				markerDisplayFrame[actorId] = markerDisplayFrame[actorId] or MARKER_FRAME_COUNT
				local markerFrameIndex
				local targetFrame = MARKER_FRAME_COUNT

				if tes3.mobilePlayer.isSneaking then
					local actualSuspicion = detection.suspicion[actorId] or 0
					
					if  actualSuspicion >= 1.0 then
						targetFrame = 1
					else
						targetFrame = quantizeFrame(suspicionValue)
					end

					if config.crosshairAnimated then
						local isOpening = targetFrame < markerDisplayFrame[actorId]
						local speed = isOpening and config.crosshairOpenSpeed or config.crosshairCloseSpeed
						markerDisplayFrame[actorId] = smoothFrame(markerDisplayFrame[actorId], targetFrame, speed, dt)
						markerFrameIndex = math.clamp(math.round(markerDisplayFrame[actorId]), 1, MARKER_FRAME_COUNT)
					else
						markerDisplayFrame[actorId] = targetFrame
						markerFrameIndex = targetFrame
					end

				else
					markerDisplayFrame[actorId] = smoothFrame(markerDisplayFrame[actorId], MARKER_FRAME_COUNT, config.crosshairCloseSpeed, dt)
					markerFrameIndex = math.clamp(math.round(markerDisplayFrame[actorId]), 1, MARKER_FRAME_COUNT) 
				end

				if markerFrameIndex then
					setFlipFrame(markerData.texProp, markerFrameIndex)
				end

				local shouldShow = mobilePlayer.isSneaking and (targetFrame <= 16)
				local targetAlpha = shouldShow and 1 or 0
				targetAlpha = targetAlpha * ((MARKER_FRAME_COUNT - markerDisplayFrame[actorId]) * 0.06)
				fadeMarker(actorId, targetAlpha, 10, dt)
				maybeDetachMarker(actorId, targetAlpha, markersToDetach)
				
			end
		else
			if markerData then
				markerData.node.appCulled = true
				detachMarker(actorId)
				markerDisplayFrame[actorId] = nil
				markerCurrentAlpha[actorId] = nil
			end
		end

		-- === 2-D HUD bar ===
		if not config.fillbarEnabled or suspicionValue <= 0 then
			goto continue
		end

		-- Project ~head height above the actor's feet
		local headPos = tes3vector3.new(ref.position.x, ref.position.y, ref.position.z + 120)
		local sp = worldToScreen(headPos)
		-- Skip bar if behind camera or off-screen
		if not sp or sp.x < 0 or sp.x > 1 or sp.y < 0 or sp.y > 1 then
			goto continue
		end

		local bar = getOrCreateBar(actorId)
		if not bar then
			goto continue
		end

		-- Center bar horizontally over head; nudge upward
		bar.menu.absolutePosAlignX = sp.x
		bar.menu.absolutePosAlignY = math.max(0, sp.y - BAR_Y_OFFSET)

		bar.fillbar.widget.current = math.floor(suspicionValue * 100)
		log:trace("[bar widget] %s current=%d max=100 suspicionValue=%.3f", actorId, bar.fillbar.widget.current, suspicionValue)
		-- Green → yellow → red
		bar.fillbar.widget.fillColor = { math.min(suspicionValue * 2, 1), math.min((1 - suspicionValue) * 2, 1), 0 }

		bar.menu.visible = true
		bar.menu:updateLayout()

		::continue::
	end

	-- Clean up actors that left proximity this frame
	for actorId in pairs(markerPool) do
		if not seenActors[actorId] then
			fadeMarker(actorId, 0, 10, dt)
			maybeDetachMarker(actorId, 0, markersToDetach)
		end
	end

	for _, actorId in ipairs(markersToDetach) do
    	detachMarker(actorId)
	end

	for actorId, bar in pairs(barPool) do
		if not seenActors[actorId] then
			bar.menu:destroy()
			barPool[actorId] = nil
			log:debug("Destroyed suspicion bar for %s (left proximity)", actorId)
		end
	end
	for actorId in pairs(displayState) do
		if not seenActors[actorId] then
			displayState[actorId] = nil
		end
	end
end
event.register(tes3.event.simulate, onSimulate, { priority = -1 })