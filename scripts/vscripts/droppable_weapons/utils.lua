
local M = {}

---
---Checks if the Akimbo Weapons mod is enabled.
---
---@return boolean
function M.isAkimboEnabled()
    return IsAddonEnabled('3692545530') or IsAddonEnabled('akimbo')
end

---
---Enables rendering for an entity and all children
---except for entities that are normally invisible
---
---@param ent EntityHandle
function M.enableAllRenderingForWeapon(ent)
    if not IsValidEntity(ent) then return end

    ent:SetRenderingEnabled(true)
    for child in ent:IterateChildren() do
        -- This is normally invisible, will create shadows
        if child:GetName() ~= "shotgun_tube_physics"
        and child:GetClassname() ~= "hlvr_weaponmodule_itemproxy"
        and child:GetName() ~= "rapidfire_mag_casing_physics"
        then
            child:SetRenderingEnabled(true)
        end
    end
end

---
---Disables rendering for an entity and all children.
---
---@param ent EntityHandle
function M.disableAllRenderingForWeapon(ent)
    if not IsValidEntity(ent) then return end

    ent:SetRenderingEnabled(false)
    for child in ent:IterateChildren() do
        child:SetRenderingEnabled(false)
    end
end

---
---Checks if a classname is a weapon entity class.
---
---@param classname string
---@return boolean
function M.isWeaponClass(classname)
    return classname:find('hlvr_weapon') == 1
end

return M