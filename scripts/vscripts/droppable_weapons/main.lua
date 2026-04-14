
local utils = require('droppable_weapons.utils')

local handKind = utils.isAkimboEnabled() and InputHandBoth or InputHandPrimary

-- GlobalPrecache:Add("model_folder", "models/weapons/droppable/")

DroppableWeapons = {}

local function getDropModelForWeapon(weapon)
    local cls = weapon:GetClassname()

    -- testing only
    return weapon:GetModelName()

    -- if cls == 'hlvr_weapon_energygun' then
    --     -- return 'models/weapons/vr_alyxgun/
    -- end
end

---Drops a weapon from the player as a physical object.
---@param weaponHandle? EntityHandle
---@param hand? CPropVRHand
---@param isEquipped? boolean
---@param velocity? Vector # If not provided, will default to the hand's velocity * 2
---@param torque? Vector # If not provided, will default to the hand's angular velocity
---@return EntityHandle?
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
        model = getDropModelForWeapon(weaponHandle),
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
        print(item, IsValidEntity(item), item and item:GetIntAttr('DroppedWeapon'))
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
            print('Not picking up akimbo weapon with hand', event.hand == Player.PrimaryHand and 'Primary' or 'Secondary')
            return
        end
    else
        if event.hand ~= Player.PrimaryHand then
            print('Not picking up weapon with hand', event.hand == Player.PrimaryHand and 'Primary' or 'Secondary')
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
    -- if event.hand == Player.PrimaryHand then
    --     local weapon = Player:GetWeapon()
    --     if weapon and weapon:GetClassname() ~= 'hlvr_multitool' then
    --         DroppableWeapons:DropWeapon(weapon)
    --     end
    -- end
    DroppableWeapons:DropWeapon(nil, event.hand)
end

Input:ListenToButton('release', handKind, DIGITAL_INPUT_USE_GRIP, nil, onUngrip)

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