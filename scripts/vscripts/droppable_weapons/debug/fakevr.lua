
local M = {}

function M.register(testDropFn)
    Convars:RegisterCommand('drop_weapon_fakevr', function()
        testDropFn()
    end, 'Tests dropping a weapon in fake VR mode.', 0)
end

return M