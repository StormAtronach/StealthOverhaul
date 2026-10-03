local config = require("StormAtronach.SO.config")
local log = mwse.Logger.new({
    moduleName = "sneakstrike",
    level = config.logLevel
})
local detection = require("StormAtronach.SO.detection")
local experience = require("StormAtronach.SO.experience")

-- MobileActorFlags_IsCrittable: the engine sets this on a victim that did not detect the
-- attacker, right before it rolls the hit and applies its own sneak multiplier.
local FLAG_IS_CRITTABLE = 0x8000000

--- Linearly interpolate the sneak-skill damage multiplier.
local skillBreakpoints = {0, 25, 50, 75, 100}
local skillBreakpointKeys = {
    "skill0", "skill25", "skill50", "skill75", "skill100"
}

local function getSkillMultiplier(sneakSkill)
    local pts = config.sneakSkillMult
    sneakSkill = math.clamp(sneakSkill, 0, 100)
    if config.sneakSkillMultSteps then
        -- Use the multiplier of the highest breakpoint at or below the skill level
        local result = pts[skillBreakpointKeys[1]]
        for i = 1, #skillBreakpoints do
            if sneakSkill >= skillBreakpoints[i] then
                result = pts[skillBreakpointKeys[i]]
            end
        end
        return result
    end
    for i = 1, #skillBreakpoints - 1 do
        local a, b = skillBreakpoints[i], skillBreakpoints[i + 1]
        if sneakSkill <= b then
            local t = (sneakSkill - a) / (b - a)
            return pts[skillBreakpointKeys[i]] + t *
                       (pts[skillBreakpointKeys[i + 1]] -
                           pts[skillBreakpointKeys[i]])
        end
    end
    return pts[skillBreakpointKeys[#skillBreakpointKeys]]
end

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
    [tes3.weaponType.marksmanThrown] = "marksmanThrown"
}

--- Ranged weapons are resolved on projectile impact, not on the swing (see onDamage).
local rangedWeaponKeys = {
    marksmanBow = true,
    marksmanCrossbow = true,
    marksmanThrown = true
}

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
    marksmanThrown = "marksman"
}

-- Message queued on the strike, shown in damaged (after other mods have applied their modifiers).
-- Melee strikes are matched by target; ranged strikes also by the projectile that queued them,
-- so an unrelated hit during the arrow's flight cannot consume the message.
---@type { message: string, target: tes3reference, projectile: tes3mobileProjectile|nil }|nil
local pendingSneak = nil

--- The configured per-weapon multiplier, before skill scaling. Exactly 1.0 means "non-lethal".
---@param weaponTypeKey string
---@return number
local function getWeaponMultiplier(weaponTypeKey)
    return (config.sneakStrikeMult and config.sneakStrikeMult[weaponTypeKey]) or 1.0
end

--- Final damage multiplier: per-weapon value times the sneak-skill factor, never below 1.0 so
--- a sneak attack is never weaker than an ordinary hit (low skill means no bonus, not a penalty).
---@param weaponTypeKey string
---@return number
local function getStrikeMultiplier(weaponTypeKey)
    local multiplier = getWeaponMultiplier(weaponTypeKey)
    if config.sneakSkillMultEnabled then
        local sneakSkill = tes3.mobilePlayer.sneak and
                               tes3.mobilePlayer.sneak.current or 0
        multiplier = multiplier * getSkillMultiplier(sneakSkill)
    end
    return math.max(multiplier, 1.0)
end

--- Mark the victim as aware of the player, in both the mod's model and the engine flags.
---@param targetMobile tes3mobileActor
---@param targetReference tes3reference
local function markDiscovered(targetMobile, targetReference)
    detection.addSuspicion(targetReference, 1)
    targetMobile.isPlayerDetected = true
    targetMobile.isPlayerHidden = false
end

---@param multiplier number
---@param targetReference tes3reference
---@param projectile tes3mobileProjectile|nil
local function queueSneakMessage(multiplier, targetReference, projectile)
    if config.showSneakStrikeMessage then
        pendingSneak = {
            message = string.format("Sneak attack! x%.2f damage", multiplier),
            target = targetReference,
            projectile = projectile,
        }
    end
end

--- Set hit chance to 100 on a sneak strike.
---@param e calcHitChanceEventData
local function sneakAttack(e)
    if not config.modEnabled or not config.sneakStrikeEnabled then return end
    if e.attacker == tes3.player and e.targetMobile then
        if tes3.mobilePlayer.isSneaking and not detection.isDetectedBy(e.targetMobile) then
            e.hitChance = 100
        end
    end
end
event.register("calcHitChance", sneakAttack, {priority = 1000})

--- Melee sneak strikes. attackHit fires before the engine resolves the strike, so the
--- multiplier written to physicalDamage here is what the engine applies.
---@param e attackHitEventData
local function attackHitCallback(e)
    if not config.modEnabled or not config.sneakStrikeEnabled then return end
    if e.reference ~= tes3.player then return end
    if not tes3.mobilePlayer.isSneaking then return end
    if (not e.targetMobile) or (not e.targetReference) then return end
    if not (e.targetMobile.actorType == tes3.actorType.creature or
        e.targetMobile.actorType == tes3.actorType.npc) then return end

    -- Determine weapon type key
    local weaponTypeKey
    local weapon = e.mobile.readiedWeapon
    if not weapon then
        weaponTypeKey = "handToHand"
    elseif weapon.object then
        weaponTypeKey = weaponTypeKeys[weapon.object.type]
    end
    if not weaponTypeKey then return end

    -- A bow release still runs the engine's melee hit detection, so targetMobile is set
    -- whenever an actor stands within reach. Projectile damage never reads physicalDamage;
    -- ranged strikes are handled on impact in onDamage.
    if rangedWeaponKeys[weaponTypeKey] then return end

    if detection.isDetectedBy(e.targetMobile) then return end

    markDiscovered(e.targetMobile, e.targetReference)

    -- Knockout is decided by the configured weapon value, not the skill-scaled result.
    local isNonLethal = getWeaponMultiplier(weaponTypeKey) == 1.0
    local multiplier = isNonLethal and 1.0 or getStrikeMultiplier(weaponTypeKey)

    -- Vanilla crit is suppressed (target marked detected above), so apply our multiplier directly.
    local baseDamage = e.mobile.actionData.physicalDamage
    e.mobile.actionData.physicalDamage = baseDamage * multiplier

    -- Replay the crit sound the engine skips while IsCrittable is unset.
    tes3.playSound({ sound = "Critical Damage", reference = e.targetReference })

    log:debug(
        "Sneak attack [%s]: baseDamage=%.1f mult=x%.2f newDamage=%.1f nonLethal=%s",
        weaponTypeKey, baseDamage, multiplier,
        e.mobile.actionData.physicalDamage, tostring(isNonLethal))

    if isNonLethal and e.targetMobile.actorType == tes3.actorType.npc then
        -- Helmet check: player's relevant skill tier vs target's helmet weight class
        local helmet = tes3.getEquippedItem({
            actor = e.targetMobile,
            slot = tes3.armorSlot.helmet,
            objectType = tes3.objectType.armor
        })
        local helmetScore = 0
        if helmet and helmet.object and helmet.object.weightClass then
            helmetScore = 1 + helmet.object.weightClass -- 1=light 2=medium 3=heavy
        end
        local skillStatName = weaponSkillStats[weaponTypeKey] or "handToHand"
        local skillLevel = e.mobile[skillStatName] and
                               e.mobile[skillStatName].current or 0
        local playerScore = math.floor(skillLevel / 25)

        log:debug(
            "Non-lethal check: skill=%s(%d) playerScore=%d helmetScore=%d",
            skillStatName, skillLevel, playerScore, helmetScore)

        if helmetScore < playerScore then
            e.targetMobile:applyFatigueDamage(3000)
            local victimSH = tes3.makeSafeObjectHandle(e.targetReference)
            timer.delayOneFrame(function()
                if victimSH:valid() then
                    local victimMobile = victimSH:getObject().mobile --[[@as tes3mobileActor]]
                    victimMobile:stopCombat(true)
                else
                    log:debug(
                        "Reference invalidated in non-lethal delayOneFrame")
                end
            end)
        end
    else
        queueSneakMessage(multiplier, e.targetReference)
    end
end
event.register(tes3.event.attackHit, attackHitCallback)

--- Ranged sneak strikes. The engine decides a projectile crit on impact by asking the victim
--- whether it detects the player (which routes through our detectSneak override), then
--- multiplies by fCombatKODamageMult. When that happened the IsCrittable flag is still set
--- here, so we swap vanilla's multiplier for the configured one.
---@param e damageEventData
local function onDamage(e)
    if not config.modEnabled or not config.sneakStrikeEnabled then return end
    if not e.projectile or e.attacker ~= tes3.mobilePlayer then return end
    if not e.mobile or not e.reference then return end
    if not tes3.mobilePlayer.isSneaking then return end
    -- `bit` is LuaJIT's bit library, available in MWSE but absent from the type definitions.
    ---@diagnostic disable-next-line: undefined-global
    if bit.band(e.mobile.flags, FLAG_IS_CRITTABLE) == 0 then return end

    local projectile = e.projectile --[[@as tes3mobileProjectile]]
    local weapon = projectile.firingWeapon
    local weaponTypeKey = weapon and weaponTypeKeys[weapon.type]
    if not weaponTypeKey or not rangedWeaponKeys[weaponTypeKey] then return end

    local koMult = tes3.findGMST(tes3.gmst.fCombatKODamageMult)
    local vanillaMult = (koMult and tonumber(koMult.value)) or 1.5
    local multiplier = getStrikeMultiplier(weaponTypeKey)

    local baseDamage = e.damage / vanillaMult
    e.damage = baseDamage * multiplier

    markDiscovered(e.mobile, e.reference)
    queueSneakMessage(multiplier, e.reference, projectile)

    log:debug(
        "Ranged sneak attack [%s]: baseDamage=%.1f vanilla=x%.2f mult=x%.2f newDamage=%.1f",
        weaponTypeKey, baseDamage, vanillaMult, multiplier, e.damage)
end
event.register(tes3.event.damage, onDamage)

--- Show the queued message once the damage is final, after other mods' damage handlers.
---@param e damagedEventData
local function damagedCallback(e)
    if not pendingSneak then return end
    local pending = pendingSneak
    -- A ranged strike waits for its own projectile to land; anything else is not ours.
    if pending.projectile and e.projectile ~= pending.projectile then return end
    pendingSneak = nil
    if e.attacker == tes3.mobilePlayer and e.reference == pending.target and e.damage >=
        1 then
        tes3.messageBox(pending.message)
        log:debug("%s damage was %s", e.reference.id, e.damage)
        experience.levelSneak(experience.Source.sneakStrike, 0)
    end
end
event.register(tes3.event.damaged, damagedCallback, {priority = -10000})
