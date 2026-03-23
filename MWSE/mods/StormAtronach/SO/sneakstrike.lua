local config = require("StormAtronach.SO.config")
local log = mwse.Logger.new({ moduleName = "sneakstrike", level = config.logLevel })

--- Map tes3.weaponType values to the string keys used in config tables.
local weaponTypeKeys = {
	[tes3.weaponType.shortBladeOneHand] = "shortBladeOneHand",
	[tes3.weaponType.longBladeOneHand] = "longBladeOneHand",
	[tes3.weaponType.longBladeTwoClose] = "longBladeTwoClose",
	[tes3.weaponType.bluntOneHand] = "bluntOneHand",
	[tes3.weaponType.bluntTwoClose] = "bluntTwoClose",
	[tes3.weaponType.bluntTwoWide] = "bluntTwoWide",
	[tes3.weaponType.spearTwoWide] = "spearTwoWide",
	[tes3.weaponType.axeOneHand] = "axeOneHand",
	[tes3.weaponType.axeTwoHand] = "axeTwoHand",
	[tes3.weaponType.marksmanBow] = "marksmanBow",
	[tes3.weaponType.marksmanCrossbow] = "marksmanCrossbow",
	[tes3.weaponType.marksmanThrown] = "marksmanThrown",
}

--- Ranged weapons receive a 1.5x vanilla sneak multiplier; melee receives 4x.
local rangedWeaponKeys = { marksmanBow = true, marksmanCrossbow = true, marksmanThrown = true }

--- Map weapon type keys to the mobile skill stat name used in the helmet check.
local weaponSkillStats = {
	handToHand = "handToHand",
	shortBladeOneHand = "shortBlade",
	longBladeOneHand = "longBlade",
	longBladeTwoClose = "longBlade",
	bluntOneHand = "bluntWeapon",
	bluntTwoClose = "bluntWeapon",
	bluntTwoWide = "bluntWeapon",
	spearTwoWide = "spear",
	axeOneHand = "axe",
	axeTwoHand = "axe",
	marksmanBow = "marksman",
	marksmanCrossbow = "marksman",
	marksmanThrown = "marksman",
}

--- Set hit chance to 100 on a sneak strike.
---@param e calcHitChanceEventData
local function sneakAttack(e)
	if not config.modEnabled or not config.sneakStrikeEnabled then
		return
	end
	if e.attacker == tes3.player and e.targetMobile then
		if tes3.mobilePlayer.isSneaking and not e.targetMobile.isPlayerDetected then
			e.hitChance = 100
		end
	end
end
event.register("calcHitChance", sneakAttack, { priority = 1000 })

---@param e attackHitEventData
local function attackHitCallback(e)
	if not config.modEnabled or not config.sneakStrikeEnabled then
		return
	end
	if e.reference ~= tes3.player then
		return
	end
	if not tes3.mobilePlayer.isSneaking then
		return
	end
	if not e.targetMobile then
		return
	end
	if e.targetMobile.isPlayerDetected then
		return
	end
	if e.targetMobile.actorType ~= tes3.actorType.npc then
		return
	end

	-- Determine weapon type key
	local weaponTypeKey
	local weapon = e.mobile.readiedWeapon
	if not weapon then
		weaponTypeKey = "handToHand"
	elseif weapon.object then
		weaponTypeKey = weaponTypeKeys[weapon.object.type]
	end
	if not weaponTypeKey then
		return
	end

	local multiplier = (config.sneakStrikeMult and config.sneakStrikeMult[weaponTypeKey]) or 1.0
	local isNonLethal = multiplier == 1.0

	local vanillaMult = rangedWeaponKeys[weaponTypeKey] and 1.5 or 4.0
	local baseDamage = e.mobile.actionData.physicalDamage / vanillaMult
	e.mobile.actionData.physicalDamage = baseDamage * multiplier

	log:debug("Sneak attack [%s]: baseDamage=%.1f mult=x%.2f newDamage=%.1f nonLethal=%s", weaponTypeKey, baseDamage,
	          multiplier, e.mobile.actionData.physicalDamage, tostring(isNonLethal))

	if isNonLethal then
		-- Helmet check: player's relevant skill tier vs target's helmet weight class
		local helmet = tes3.getEquippedItem({
			actor = e.targetMobile,
			slot = tes3.armorSlot.helmet,
			objectType = tes3.objectType.armor,
		})
		local helmetScore = 0
		if helmet and helmet.object and helmet.object.weightClass then
			helmetScore = 1 + helmet.object.weightClass -- 1=light 2=medium 3=heavy
		end
		local skillStatName = weaponSkillStats[weaponTypeKey] or "handToHand"
		local skillLevel = e.mobile[skillStatName] and e.mobile[skillStatName].current or 0
		local playerScore = math.floor(skillLevel / 25)

		log:debug("Non-lethal check: skill=%s(%d) playerScore=%d helmetScore=%d", skillStatName, skillLevel, playerScore,
		          helmetScore)

		if helmetScore < playerScore then
			e.targetMobile:applyFatigueDamage(3000)
			local victimSH = tes3.makeSafeObjectHandle(e.targetReference)
			timer.delayOneFrame(function()
				if victimSH:valid() then
					local victimMobile = victimSH:getObject().mobile --[[@as tes3mobileActor]]
					victimMobile:stopCombat(true)
				else
					log:debug("Reference invalidated in non-lethal delayOneFrame")
				end
			end)
		end
	else
		if config.showSneakStrikeMessage then
			tes3.messageBox(string.format("Sneak attack! x%.1f damage", multiplier))
		end
	end
end
event.register(tes3.event.attackHit, attackHitCallback)
