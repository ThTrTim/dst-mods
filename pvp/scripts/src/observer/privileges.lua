-- Central policy for OB/referee privileges.
-- Gameplay observation powers belong to OB mode, not to server-admin identity.
local observer_camera = require("src/observer/camera_mode")
local team_state = require("src/team/lobby_team_state")

local M = {}

function M.is_observer(player)
    if player == nil then
        return false
    end

    local team_id, pending = team_state.get_player_team(player)
    if pending or team_state.is_playing_team(team_id) then
        return false
    end
    if team_id == team_state.TEAM_OBSERVER then
        return true
    end

    return observer_camera.is_observer(player)
end

function M.can_use_referee_rpc(player)
    return M.is_observer(player)
end

function M.can_use_referee_panel(player)
    return M.is_observer(player)
end

function M.can_view_team_chat(player)
    return M.is_observer(player)
end

function M.can_receive_healthbar(player)
    return M.is_observer(player)
end

function M.has_legacy_world_immunity(player)
    return M.is_observer(player)
end

function M.is_excluded_from_pve_targeting(player)
    return M.is_observer(player)
end

return M