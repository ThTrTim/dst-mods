-- Unified team state.
-- The lobby netvar is only the client-side preselect mirror. Spawned players
-- use the per-entity _bird_team_var as their game-time team mirror.
local M = {}

local TEAM_OBSERVER = 0
local TEAM_RED = 1
local TEAM_BLUE = 2
local TEAM_WAITING = 3

M.TEAM_OBSERVER = TEAM_OBSERVER
M.TEAM_RED = TEAM_RED
M.TEAM_BLUE = TEAM_BLUE
M.TEAM_WAITING = TEAM_WAITING

local preselect_teams = {}
local preselect_locks = {}
local preselect_global_locked = false
local preselect_ready = false
local revision = 0

function M.is_valid(team_id)
    return team_id == TEAM_OBSERVER
        or team_id == TEAM_RED
        or team_id == TEAM_BLUE
        or team_id == TEAM_WAITING
end

function M.is_playing_team(team_id)
    return team_id == TEAM_RED or team_id == TEAM_BLUE
end

function M.is_waiting_team(team_id)
    return team_id == TEAM_WAITING
end

function M.normalize(team_id)
    team_id = tonumber(team_id)
    if team_id == nil then
        return nil
    end

    team_id = math.floor(team_id)
    return M.is_valid(team_id) and team_id or nil
end

function M.apply_preselect_serialized(payload)
    local next_teams = {}
    local next_locks = {}
    local next_global_locked = false

    if type(payload) == "string" and payload ~= "" then
        for entry in string.gmatch(payload, "[^;]+") do
            if entry == "__lock=1" then
                next_global_locked = true
            else
                local userid, team_text, locked_text = string.match(entry, "^([^=]+)=([0123])(!?)$")
                local team_id = M.normalize(team_text)
                if userid ~= nil and team_id ~= nil then
                    next_teams[userid] = team_id
                    next_locks[userid] = locked_text == "!"
                end
            end
        end
    end

    preselect_teams = next_teams
    preselect_locks = next_locks
    preselect_global_locked = next_global_locked
    preselect_ready = true
    revision = revision + 1
end

function M.apply_serialized(payload)
    M.apply_preselect_serialized(payload)
end

function M.set_local(userid, team_id)
    team_id = M.normalize(team_id)
    if userid == nil or team_id == nil then
        return false
    end

    if preselect_teams[userid] ~= team_id then
        preselect_teams[userid] = team_id
        revision = revision + 1
    end
    return true
end

function M.set_lock_local(userid, locked)
    if userid == nil then
        return false
    end

    local value = locked == true
    if preselect_locks[userid] ~= value then
        preselect_locks[userid] = value
        revision = revision + 1
    end
    return true
end

function M.set_global_lock_local(locked)
    local value = locked == true
    if preselect_global_locked ~= value then
        preselect_global_locked = value
        revision = revision + 1
    end
    return true
end

function M.get(userid)
    if userid == nil then
        return TEAM_WAITING
    end
    return preselect_teams[userid] or TEAM_WAITING
end

function M.is_locked(userid)
    return userid ~= nil and preselect_locks[userid] == true
end

function M.is_global_locked()
    return preselect_global_locked == true
end

function M.get_revision()
    return revision
end

function M.is_remote_ready()
    return preselect_ready
end

local function get_server_teams()
    local net = TheWorld ~= nil and TheWorld.net or nil
    return net ~= nil and net._bird_lobby_teams or nil
end

function M.get_server_team(userid)
    local teams = get_server_teams()
    local net = TheWorld ~= nil and TheWorld.net or nil
    local ready = net ~= nil and net._bird_lobby_teams_ready == true
    if teams == nil or userid == nil then
        return nil, ready
    end

    return M.normalize(teams[userid]), ready
end

function M.get_world_team(userid)
    if userid == nil then
        return nil, false
    end

    local server_team, server_ready = M.get_server_team(userid)
    if server_ready then
        return server_team, true
    end

    return nil, false
end

local function get_player_teamvar(player)
    local netvar = player ~= nil and player._bird_team_var or nil
    if netvar == nil then
        return nil, false
    end

    local value = tonumber(netvar:value())
    if value == nil or value == 0 then
        return nil, false
    end

    local team_id = M.normalize(value - 1)
    return team_id, team_id ~= nil
end

function M.get_component_team(player)
    local component = player ~= nil
        and player.components ~= nil
        and player.components.player_duiwu_qe
        or nil
    return component ~= nil and M.normalize(component.duiwu) or nil
end

local function get_attached_player_team(player)
    local state = player ~= nil and player._bird_team_state or nil
    if state == nil then
        return nil, false
    end

    if state.status == "ready" then
        return M.normalize(state.team_id), false
    end

    if state.status == "pending" then
        return nil, true
    end

    return nil, false
end

function M.get_player_team(player, default_team)
    local attached_team, attached_pending = get_attached_player_team(player)
    if attached_team ~= nil then
        return attached_team, false
    end
    if attached_pending then
        return default_team, true
    end

    local netvar_team, netvar_ready = get_player_teamvar(player)
    if netvar_ready then
        return netvar_team, false
    end

    if player ~= nil and player.userid ~= nil then
        local world_team, world_ready = M.get_world_team(player.userid)
        if world_team ~= nil then
            return world_team, false
        end

        if world_ready then
            if default_team ~= nil then
                return default_team, false
            end
            return nil, true
        end

        return default_team, true
    end

    local component_team = M.get_component_team(player)
    if component_team ~= nil then
        return component_team, false
    end

    return default_team, false
end

function M.is_observer_team(team_id)
    return team_id == TEAM_OBSERVER
end

function M.is_player_observer(player)
    local team_id, pending = M.get_player_team(player)
    return not pending and team_id == TEAM_OBSERVER
end

return M
