
local utils = require('droppable_weapons.utils')

local M = {}

---@type table
local state = {
    handKind = nil,
    listenerOk = nil,
    listenerErr = nil,
    ungripCalls = 0,
    lastUngrip = nil,
    lastResult = nil,
    rawPress = { [0] = 0, [1] = 0 },
    rawRelease = { [0] = 0, [1] = 0 },
}

local logButtons = false
local logListenersAdded = false

local function say(...)
    Msg('[droppable_weapons] ' .. table.concat({...}, ' ') .. '\n')
end

local function describeEntity(ent)
    if ent == nil then return 'nil' end
    if not IsValidEntity(ent) then return 'invalid' end
    return ent:GetClassname() .. '#' .. ent:entindex()
end

---Records the result of registering the main ungrip listener.
---@param ok boolean
---@param err any
---@param handKind integer?
function M.setListenerResult(ok, err, handKind)
    state.listenerOk = ok
    state.listenerErr = (not ok) and tostring(err) or nil
    state.handKind = handKind

    if not ok then
        warn('Failed to register the grip release listener: ' .. tostring(err))
    end
end

---Wraps the real ungrip handler so every call is tracked.
---@param handler fun(event: InputReleaseCallback): any
---@return fun(event: InputReleaseCallback)
function M.trackUngrip(handler)
    return function(event)
        state.ungripCalls = state.ungripCalls + 1
        state.lastUngrip = {
            time = Time(),
            hand = event.hand and event.hand:GetHandID() or -1,
            held = describeEntity(event.hand and event.hand.ItemHeld),
            heldTime = event.held_time,
        }

        local ok, result = pcall(handler, event)
        if ok then
            state.lastResult = result == nil and 'handled' or describeEntity(result)
        else
            state.lastResult = 'ERROR: ' .. tostring(result)
            warn('Error in grip release handler: ' .. tostring(result))
        end
    end
end

---Counts raw grip presses/releases on each physical hand, regardless of how the mod listens.
local function registerRawGripCounters()
    for hand = 0, 1 do
        pcall(function()
            Input:ListenToButton('press', hand, DIGITAL_INPUT_USE_GRIP, nil, function()
                state.rawPress[hand] = state.rawPress[hand] + 1
            end)
            Input:ListenToButton('release', hand, DIGITAL_INPUT_USE_GRIP, nil, function()
                state.rawRelease[hand] = state.rawRelease[hand] + 1
            end)
        end)
    end
end

local function registerButtonLogger()
    if logListenersAdded then return end
    logListenersAdded = true

    for button = 0, 27 do
        for hand = 0, 1 do
            pcall(function()
                Input:ListenToButton('press', hand, button, nil, function()
                    if logButtons then
                        say('press', Input:GetHandName(hand), '->', tostring(button), Input:GetButtonDescription(button))
                    end
                end)
                Input:ListenToButton('release', hand, button, nil, function()
                    if logButtons then
                        say('release', Input:GetHandName(hand), '->', tostring(button), Input:GetButtonDescription(button))
                    end
                end)
            end)
        end
    end
end

---Diagnostic function for `alyxlib_diagnose droppable_weapons`.
---@return boolean ok
---@return string|string[]? messages
local function diagnose()
    local issues = {}

    say('AlyxLib Input table:', tostring(type(Input)))
    say('Hand kind used by listener:', tostring(state.handKind), '(-1 = both, 2 = primary)')
    say('Grip release listener registered:', tostring(state.listenerOk), state.listenerErr or '')

    say('Akimbo enabled:', tostring(utils.isAkimboEnabled()))
    local holsters = utils.isBodyHolstersEnabled()
    say('Body Holsters enabled:', tostring(holsters), '| BodyHolsters table:', tostring(type(BodyHolsters)))

    local ok, err = pcall(function()
        say('Controller type:', tostring(Player:GetVRControllerType()), Input:GetControllerTypeDescription(Player:GetVRControllerType()))
        say('Primary hand:', Input:GetHandName(Player.PrimaryHand), '| literal type', tostring(Player.PrimaryHand:GetLiteralHandType()))
        say('Held in primary hand:', describeEntity(Player.PrimaryHand.ItemHeld))
        say('Held in secondary hand:', describeEntity(Player.SecondaryHand.ItemHeld))
        say('Player weapon:', describeEntity(Player:GetWeapon()))
    end)
    if not ok then say('Could not read player state:', tostring(err)) end

    say('Grip presses seen   (left/right):', tostring(state.rawPress[0]), '/', tostring(state.rawPress[1]))
    say('Grip releases seen  (left/right):', tostring(state.rawRelease[0]), '/', tostring(state.rawRelease[1]))
    say('Mod ungrip handler calls:', tostring(state.ungripCalls))

    if state.lastUngrip then
        local u = state.lastUngrip
        say('Last ungrip:', string.format('%.1fs ago, hand %s, held %s, grip held %.2fs', Time() - u.time, tostring(u.hand), u.held, u.heldTime or 0))
        say('Last ungrip result:', tostring(state.lastResult))
    else
        say('Last ungrip: none yet')
    end

    if not Player.HMDAvatar then
        return false, { 'Droppable Weapons requires VR or +vr_enable_fake_vr to be enabled' }
    end

    if state.listenerOk == false then
        table.insert(issues, 'The grip release listener failed to register: ' .. tostring(state.listenerErr))
    elseif state.rawRelease[0] + state.rawRelease[1] == 0 then
        table.insert(issues, 'No grip releases have been detected yet. Pick up a weapon, let go of the grip, then run this again')
        table.insert(issues, 'Use "droppable_weapons_log_buttons 1" to see which actions your controller fires')
    elseif state.ungripCalls == 0 then
        table.insert(issues, 'Grip releases are detected but the mod handler never ran, check the hand kind above')
    end

    if state.lastResult and state.lastResult:find('^ERROR') then
        table.insert(issues, 'The last grip release failed: ' .. state.lastResult)
    end

    if holsters then
        say('Note: Body Holsters is enabled, drops are skipped while the hand is inside a holster slot')
    end

    if #issues > 0 then
        return false, issues
    end

    return true, 'Grip release was detected and handled ' .. state.ungripCalls .. ' time(s)'
end

EasyConvars:RegisterCommand('droppable_weapons_log_buttons', function(enabled)
    logButtons = enabled ~= '0'
    if logButtons then registerButtonLogger() end
    say('Button logging', logButtons and 'enabled, press buttons on your controllers' or 'disabled')
end, 'Logs every controller button press/release. Pass 0 to stop.', 0)

registerRawGripCounters()

if RegisterAlyxLibAddon and RegisterAlyxLibDiagnostic then
    local addonID = RegisterAlyxLibAddon("Droppable Weapons", "v1.0.0", "3707778626", "droppable_weapons", "v2.0.0")
    RegisterAlyxLibDiagnostic(addonID, diagnose)
else
    warn('AlyxLib is too old to register Droppable Weapons, alyxlib_diagnose will not be available')
end

return M
