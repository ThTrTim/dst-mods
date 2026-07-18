-- Shared RPC router for OB/referee actions and OB camera actions.
-- Team assignment is handled by lobby user commands before spawning.
local checkstring = GLOBAL.checkstring
local checknumber = GLOBAL.checknumber
local observer_actions = require("src/observer/actions")
local observer_privileges = require("src/observer/privileges")
local admin_privileges = require("src/admin/privileges")
local function is_observer(player)
    local fn = observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end

local function is_admin(player)
    local fn = admin_privileges.is_player_admin
    return fn ~= nil and fn(player) == true
end

local function can_use_referee_rpc(player)
    local fn = observer_privileges.can_use_referee_rpc or observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end

local OBSERVER_ACTIONS = {
    chuansong = true,
    ditu = true,
}

local ADMIN_ACTIONS = {
    give_team_item = true,
    wanjia = true,
    youxi = true,
    zhaoji = true,
}

AddModRPCHandler("bird_mode_rpc", "bird_mode_rpc", function(player, action, arg1, arg2, arg3)
    if not checkstring(action) or not checknumber(arg1) then
        return
    end

    if ADMIN_ACTIONS[action] == true then
        if not is_admin(player) then
            return
        end
    elseif OBSERVER_ACTIONS[action] == true then
        if not is_observer(player) then
            return
        end
    elseif not can_use_referee_rpc(player) then
        return
    end

    local observer_action = observer_actions[action]
    if observer_action ~= nil then
        observer_action(player, arg1, arg2, arg3)
    end
end)
