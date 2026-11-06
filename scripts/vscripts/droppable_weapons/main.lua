
local utils = require('droppable_weapons.utils')

require('droppable_weapons.convars')
local diagnose = require('droppable_weapons.diagnose')

local handKind = utils.isAkimboEnabled() and InputHandBoth or InputHandPrimary

GlobalPrecache:Add("model_folder", "models/weapons/droppable/")

DroppableWeapons = {}

---@type table<string, string|fun(weapon: EntityHandle): string?>
local proxyModels = {
    ['hlvr_weapon_energygun'] = 'models/weapons/droppable/vr_alyxgun.vmdl',
    ['hlvr_weapon_rapidfire'] = 'models/weapons/droppable/vr_ipistol.vmdl',
    ['hlvr_weapon_shotgun'] = function(weapon)
        for _, child in ipairs(weapon:GetTopChildren()) do
            if child:GetClassname() == 'prop_animinteractable' and child:GetCycle() > 0.9 then
                return 'models/weapons/droppable/vr_shotgun_open.vmdl'
            end
        end

        return 'models/weapons/droppable/vr_shotgun.vmdl'
    end,
}

---
---Sets a custom model for the dropped physics proxy of a specific weapon class.
---Can be a string (model path) or a function that takes the weapon entity and returns a model path.
---
---Make the model is precached.
---
---@param weaponClass string
---@param modelOrFn string|fun(weapon: EntityHandle): string?
function DroppableWeapons:SetProxyModelForWeapon(weaponClass, modelOrFn)
    proxyModels[weaponClass] = modelOrFn
end

---
---Gets the model that will be used for a dropped weapon's physics proxy.
---
---@param weapon EntityHandle
---@return string
function DroppableWeapons:GetDropModelForWeapon(weapon)
    local cls = weapon:GetClassname()

    local model

    if Convars:GetBool('droppable_weapons_always_use_weapon_model') then
        return weapon:GetModelName()
    end

    local modelOrFn = proxyModels[cls]
    if type(modelOrFn) == 'function' then
        model = modelOrFn(weapon)
    else
        model = modelOrFn
    end

    return model or weapon:GetModelName()
end

---
---Drops a weapon from the player as a physical object.
---
---@param weaponHandle? EntityHandle # The weapon to drop. If not provided, will attempt to drop the currently held weapon.
---@param hand? CPropVRHand # The hand to drop from. If not provided, will attempt to drop from the hand holding the weapon, or primary hand if both are holding it or if no weapon is held.
---@param isEquipped? boolean # Whether the weapon is currently equipped. If not provided, will attempt to determine based on the hand holding it.
---@param velocity? Vector # If not provided, will default to the hand's velocity * 2
---@param torque? Vector # If not provided, will default to the hand's angular velocity
---@return EntityHandle? # The dropped weapon proxy entity, or nil if the drop failed
function DroppableWeapons:DropWeapon(weaponHandle, hand, isEquipped, velocity, torque)
    if weaponHandle == nil then
        if hand ~= nil then
            weaponHandle = hand.ItemHeld
            isEquipped = true
        else
            weaponHandle = Player:GetWeapon()
            hand = Player.PrimaryHand
            isEquipped = true
        end
    end

    if weaponHandle == nil or not IsValidEntity(weaponHandle) then return end
    if not utils.isWeaponClass(weaponHandle:GetClassname()) then return end

    local name = DoUniqueString('dropped_weapon_' .. weaponHandle:GetClassname())

    local dropProxy = SpawnEntityFromTableSynchronous('prop_physics', {
        model = self:GetDropModelForWeapon(weaponHandle),
        origin = weaponHandle:GetOrigin(),
        angles = weaponHandle:GetAngles(),
        targetname = name,
    })

    ---@NOTE: Must only lower alpha so grav pull still works
    ---       Disabled rendering stops targeting
    dropProxy:SetRenderAlpha(0)

    if Convars:GetInt('developer') > 1 then
        SendToConsole('ent_vcollide_wireframe ' .. name)
    end

    hand = hand or Player.PrimaryHand
    hand:RemoveHandAttachmentByHandle(weaponHandle)

    dropProxy:SetIntAttr('DroppedWeapon', 1)

    weaponHandle:SetParent(dropProxy, nil)
    utils.enableAllRenderingForWeapon(weaponHandle)

    if isEquipped or velocity or torque then
        local dropVelocity = velocity or hand:GetVelocity()
        local dropTorque = torque or GetPhysAngularVelocity(hand)

        dropProxy:SetAbsVelocity(dropVelocity)
        SetPhysAngularVelocity(dropProxy, dropTorque)
    end

    return dropProxy
end

---@param event PlayerEventItemPickup
ListenToPlayerEvent('item_pickup', function(event)
    local item = event.item
    if not (item and IsValidEntity(item) and item:GetIntAttr('DroppedWeapon') == 1) then
        return
    end

    local weapon = item:FirstMoveChild()
    if not IsValidEntity(weapon) then
        return warn('Failed to find weapon child of dropped weapon proxy on pickup')
    end

    -- change to AkimboWeapon after AlyxLib fix is uploaded
    -- only pistols are supported anyway
    local isAkimboWeapon = isinstance(weapon, 'AkimboPistol')

    if isAkimboWeapon then
        if event.hand ~= Player.SecondaryHand then
            devprint2('Not picking up akimbo weapon with hand', event.hand == Player.PrimaryHand and 'Primary' or 'Secondary')
            return
        end
    else
        if event.hand ~= Player.PrimaryHand then
            devprint2('Not picking up weapon with hand', event.hand == Player.PrimaryHand and 'Primary' or 'Secondary')
            return
        end
    end

    devprint2('Picking up dropped weapon', item:GetClassname(), 'with hand', event.hand == Player.PrimaryHand and 'Primary' or 'Secondary')

    item:SetIntAttr('DroppedWeapon', 0)
    weapon:SetParent(nil, nil)

    if isAkimboWeapon then
        ---@diagnostic disable-next-line: undefined-field
        weapon:Equip()
    else
        event.hand:AddHandAttachment(weapon)
    end

    item:Kill()
end)

---Called when the player opens their hand to drop a weapon.
---@param event InputReleaseCallback
local function onUngrip(event)
    ---@diagnostic disable-next-line: undefined-global
    if utils.isBodyHolstersEnabled() and type(BodyHolsters) == "table" then
        ---@diagnostic disable-next-line: undefined-global
        if not BodyHolsters:IsHandInAvailableSlot(event.hand) then
            return DroppableWeapons:DropWeapon(nil, event.hand)
        end
    else
        return DroppableWeapons:DropWeapon(nil, event.hand)
    end
end

local listenOk, listenErr = pcall(function()
    Input:ListenToButton('release', handKind, DIGITAL_INPUT_USE_GRIP, nil, diagnose.trackUngrip(onUngrip))
end)
diagnose.setListenerResult(listenOk, listenErr, handKind)

if IsFakeVREnabled() then
    local fakevr = require("droppable_weapons.debug.fakevr")
    fakevr.register(function()
        -- onUngrip({ button = DIGITAL_INPUT_USE_GRIP, held_time = 0, kind = 'release', release_time = 0, hand = Player.PrimaryHand })
        DroppableWeapons:DropWeapon()
    end)

    ListenToPlayerEvent('vr_player_ready', function()
        SendToConsole('impulse 101')
        SendToConsole('r_drawviewmodel 0')
        SendToConsole('bind G drop_weapon_fakevr')
    end)
end