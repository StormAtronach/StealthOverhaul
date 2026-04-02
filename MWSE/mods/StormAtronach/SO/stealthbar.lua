local config = require("StormAtronach.SO.config")
local detection = require("StormAtronach.SO.detection")

local log = mwse.Logger.new({ moduleName = "stealthbar", level = config.logLevel })

-- G7: You can use this to switch back and forth from the flip controller to the manual swap
-- Set to true to drive animation via NiFlipController + node:update() instead of manual texture swap.
-- Frame-to-time mapping: frame 1 = time 0, frame 21 = time 20/21 (Stop Time = 1, SecsPerFrame = 1/21).
local USE_FLIP_CONTROLLER = true

local MARKER_FRAME_COUNT = 21

-- Crosshair: 21 UI image elements stacked inside MenuMulti; one visible at a time
local crosshairFrames = {} -- [1..21] = tes3uiElement
local crosshairActiveFrame = nil
local crosshairIsRed = false
local crosshairDisplayFrame = nil -- float; smoothed toward target for animated transitions
local crosshairParent = nil

--- Map suspicion level to one of five discrete crosshair frames at fixed thresholds.
---@param suspicion number  0.0–1.0
---@return number  frame index (1 = open, 21 = closed)
local function quantizeFrame(suspicion)
	if suspicion >= 1.0  then return 1  end
	if suspicion >= 0.75 then return 6  end
	if suspicion >= 0.50 then return 11 end
	if suspicion >= 0.25 then return 16 end
	return 21
end

local function getVanillaCrosshairNode()
	local nc = tes3.worldController.nodeCursor
	return nc and nc.children[1]
end

---@param frameIndex number|nil  1–21 to show that frame, nil to hide all
---@param isRed boolean|nil  true to tint red (full detection)
local function setCrosshairFrame(frameIndex, isRed)
	isRed = isRed == true
	if frameIndex == crosshairActiveFrame and isRed == crosshairIsRed then
		return
	end
	-- Hide and reset color of the previously active frame
	if crosshairActiveFrame and crosshairFrames[crosshairActiveFrame] then
		crosshairFrames[crosshairActiveFrame].visible = false
		crosshairFrames[crosshairActiveFrame].color = { 1, 1, 1 }
	end
	local vanillaNode = getVanillaCrosshairNode()
	if frameIndex and crosshairFrames[frameIndex] then
		crosshairFrames[frameIndex].visible = true
		crosshairFrames[frameIndex].color = isRed and { 1, 0, 0 } or { 1, 1, 1 }
		if vanillaNode and not config.keepVanillaCrosshair then
			vanillaNode.appCulled = true
		end
		log:trace("[crosshair] frame %d red=%s", frameIndex, tostring(isRed))
	else
		if vanillaNode then
			vanillaNode.appCulled = false
		end
	end
	crosshairActiveFrame = frameIndex
	crosshairIsRed = isRed
	if crosshairParent then
		crosshairParent:updateLayout()
	end
end

local function createCrosshair()
	if tes3ui.menuMode() then
		return
	end
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

	for i = 1, MARKER_FRAME_COUNT do
		local img = block:createImage({ path = string.format("textures/sa_so_ch/%d.dds", i) })
		img.visible = false
		img.consumeMouseEvents = false
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

local BAR_WIDTH = 50
local BAR_HEIGHT = 8
-- How far above the projected head point to draw the bar (in screen fraction)
local BAR_Y_OFFSET = 0.04

-- Pool of per-actor bar menus: [actorId] = { menu, fillbar }
local barPool = {}

-- === 3-D suspicion marker (billboard sneak eye) ===
local MARKER_MESH = "sa_so/sa_se.nif"
local MARKER_Z = 140

-- [actorId] = { node = niNode, ref = tes3reference, texProp = niTexturingProperty, flipCtrl = niTimeController|nil }
local markerPool = {}
local markerTemplate
local markerTextures -- niSourceTexture[1..21], pre-loaded once

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

local function attachMarker(ref, actorId)
	local entry = markerPool[actorId]
	if entry then
		return entry.node
	end
	if not ref.sceneNode then
		return nil
	end
	local tmpl = getMarkerTemplate()
	if not tmpl then
		return nil
	end

	local node = tmpl:clone()
	node.name = "SA_SO_Marker_" .. actorId
	node.translation = tes3vector3.new(0, 0, MARKER_Z)
	node.appCulled = true

	ref.sceneNode:attachChild(node, true)
	ref.sceneNode:update()
	ref.sceneNode:updateNodeEffects()

	---@diagnostic disable-next-line: param-type-mismatch
	local shape = node:getObjectByName("eye_plane") --[[@as niTriShape]]
	local texProp = shape and shape:getProperty(ni.propertyType.texturing) --[[@as niTexturingProperty]]
	local flipCtrl = shape and shape.controller --[[@as niTimeController]]
	local matProp = shape and shape:getProperty(ni.propertyType.material) --[[@as niMaterialProperty]]
	markerPool[actorId] = { node = node, ref = ref, texProp = texProp, flipCtrl = flipCtrl, matProp = matProp }
	log:debug("Attached sneak eye marker to %s", actorId)
	return node
end

local function detachMarker(actorId)
	local entry = markerPool[actorId]
	if not entry then
		return
	end
	local ref = entry.ref
	if ref and ref.sceneNode then
		ref.sceneNode:detachChild(entry.node)
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
	crosshairActiveFrame = nil
	crosshairIsRed = false
	crosshairDisplayFrame = nil
	log:debug("Bar and marker pools reset on load")
	createCrosshair()
end

event.register(tes3.event.loaded, destroyAllBars)

---@param e simulateEventData
local function onSimulate(e)
	-- Hide all bars and cull all markers first
	for _, bar in pairs(barPool) do
		bar.menu.visible = false
	end
	for _, entry in pairs(markerPool) do
		entry.node.appCulled = true
	end
	local dt = e.delta

	if not config.modEnabled then
		setCrosshairFrame(nil)
		return
	end

	-- Crosshair: quantized sneak eye with optional animated transitions
	if config.crosshairColorEnabled and tes3.mobilePlayer.isSneaking then
		local maxSuspicion = 0
		for _, s in pairs(detection.suspicion) do
			if s > maxSuspicion then
				maxSuspicion = s
			end
		end
		local targetFrame = quantizeFrame(maxSuspicion)
		local frameIndex
		if not config.crosshairAnimated or crosshairDisplayFrame == nil then
			crosshairDisplayFrame = targetFrame
			frameIndex = targetFrame
		else
			local isOpening = targetFrame < crosshairDisplayFrame
			local k = isOpening and config.crosshairOpenSpeed or config.crosshairCloseSpeed
			local alpha = 1 - math.exp(-k * dt)
			crosshairDisplayFrame = crosshairDisplayFrame + (targetFrame - crosshairDisplayFrame) * alpha
			frameIndex = math.clamp(math.round(crosshairDisplayFrame), 1, MARKER_FRAME_COUNT)
		end
		setCrosshairFrame(frameIndex, maxSuspicion >= 1.0)
	else
		crosshairDisplayFrame = nil
		setCrosshairFrame(nil, false)
	end

	if tes3ui.menuMode() then
		return
	end
	local mp = tes3.mobilePlayer
	if not mp then
		return
	end
	if not mp.isSneaking then
		return
	end

	local actors = tes3.findActorsInProximity({ reference = tes3.player, range = config.barRange })

	-- Track which actors are in range this frame so we can clean up stale markers
	local seenActors = {}

	for _, actor in pairs(actors) do
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
		local pct = suspicionValue -- progress is already 0.0–1.0
		log:trace("[marker] %s pct=%.3f", actorId, pct)
		if config.markerEnabled and suspicionValue > 0 then
			local marker = attachMarker(ref, actorId)
			if marker then
				marker.appCulled = false
				local entry = markerPool[actorId]
				local frameIndex = math.clamp(math.floor(MARKER_FRAME_COUNT - pct * (MARKER_FRAME_COUNT - 1) + 0.5), 1,
				                              MARKER_FRAME_COUNT)
				if USE_FLIP_CONTROLLER then
					-- NiFlipController path: map frame index to controller time and let node:update() apply it.
					-- Frame 1 = time 0, frame 21 = time 20/21 (Stop Time = 1, SecsPerFrame = 1/21).
					local ctrlTime = (frameIndex - 1) / MARKER_FRAME_COUNT
					local eye_plane = entry.node:getObjectByName("eye_plane")
					local texProp = eye_plane.texturingProperty
					texProp.controller.phase = 1 - ctrlTime
				else
					local textures = loadMarkerTextures()
					if entry.texProp and textures[frameIndex] then
						entry.texProp.maps[1].texture = textures[frameIndex]
					end
				end
				-- Tint red when fully detected, reset otherwise
				if entry.matProp then
					local isDetected = (detection.suspicion[actorId] or 0) >= 1.0
					local em = entry.matProp.emissive
					em.r = isDetected and 1 or 0
					em.g = 0
					em.b = 0
				end
			end
		elseif markerPool[actorId] then
			-- Suspicion gone or disabled: cull and release the node
			local entry = markerPool[actorId]
			entry.node.appCulled = true
			ref.sceneNode:detachChild(entry.node)
			ref.sceneNode:update()
			markerPool[actorId] = nil
			log:debug("Detached suspicion marker from %s (suspicion cleared)", actorId)
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
		log:trace("[bar widget] %s current=%d max=100 pct=%.3f", actorId, bar.fillbar.widget.current, pct)
		-- Green → yellow → red
		bar.fillbar.widget.fillColor = { math.min(pct * 2, 1), math.min((1 - pct) * 2, 1), 0 }

		bar.menu.visible = true
		bar.menu:updateLayout()

		::continue::
	end

	-- Clean up actors that left proximity this frame
	for actorId in pairs(markerPool) do
		if not seenActors[actorId] then
			detachMarker(actorId)
		end
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
event.register(tes3.event.simulate, onSimulate)
