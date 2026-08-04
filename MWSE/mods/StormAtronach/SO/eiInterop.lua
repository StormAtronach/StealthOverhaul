local eiInterop = {}
local config = require("StormAtronach.SO.config")

-- For interop with Essential Indicator
local SO_INTEROP_ID = "StealthOverhaul"
eiInterop.eiInstalled, eiInterop.ei = pcall(require, "Essential Indicators.interop")
if not eiInterop.eiInstalled then
	eiInterop.ei = nil
else
	print("[Stealth Overhaul] Essential Indicators interop activated")
end

local function enableCrosshair()
	eiInterop.ei.registerDisabledIndicator(eiInterop.ei.indicatorEnum.SneakIndicator, true, true, SO_INTEROP_ID)
	eiInterop.ei.registerReplacementTexture(eiInterop.ei.textureEnum.DefaultTexture,"textures/sa_so_ch_128/crosshair.dds", SO_INTEROP_ID ,1000)

	local soUiScale = config.crosshairScale
	local scaleDifference = 4 -- To match the size of our 128px crosshair, we need to multiply Essential Indicators 32px crosshair by 4
	local eiScale = 100 * scaleDifference * soUiScale
	eiInterop.ei.registerScaleOverride(eiInterop.ei.scaleTypeEnum.DefaultIndicatorScale, eiScale, SO_INTEROP_ID, 1000)
end

local function disableCrosshair()
	eiInterop.ei.registerDisabledIndicator(eiInterop.ei.indicatorEnum.SneakIndicator, false, false, SO_INTEROP_ID)
	eiInterop.ei.deregisterReplacementTexture(eiInterop.ei.textureEnum.DefaultTexture, SO_INTEROP_ID)
	if eiInterop.ei.getOverrideScale(eiInterop.ei.scaleTypeEnum.DefaultIndicatorScale) then
		eiInterop.ei.deregisterScaleOverride(eiInterop.ei.scaleTypeEnum.DefaultIndicatorScale, SO_INTEROP_ID)
	end
end

function eiInterop.toggleEssentialIndicatorCrosshair()
	if not eiInterop.ei then return end
	if config.crosshairColorEnabled and config.eiInteropEnabled and config.modEnabled then
		if not config.eiCrosshairOnlyWhenSneaking then
			enableCrosshair()
			return
		end

		local mp = tes3.mobilePlayer
		if mp and mp.isSneaking then
			enableCrosshair()
			return
		end
	end
	disableCrosshair()
end

function eiInterop.rescaleEiIndicator()
	if eiInterop.ei then
		if config.eiInteropEnabled and config.crosshairColorEnabled then
			eiInterop.ei.deregisterScaleOverride(eiInterop.ei.scaleTypeEnum.DefaultIndicatorScale, SO_INTEROP_ID)
			local soUiScale = config.crosshairScale
			local scaleDifference = 4 -- Based on 128px sprite, whereas mw and essential indicator crosshair sprite is 32px
			local eiScale = 100 * scaleDifference * soUiScale
			eiInterop.ei.registerScaleOverride(eiInterop.ei.scaleTypeEnum.DefaultIndicatorScale, eiScale, SO_INTEROP_ID, 1000)
		end
	end
end


eiInterop.toggleEssentialIndicatorCrosshair()

return eiInterop

