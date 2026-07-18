-- Shared team-marker module.
-- This file is required by other modules and intentionally does not register hooks.
local team_state = require("src/team/lobby_team_state")

local M = {}
local teammate_markers_enabled = false
local observer_markers_enabled = true

local TEAM_MARKER_PREFABS = {
    [team_state.TEAM_RED] = "bird_duiwufx1",
    [team_state.TEAM_BLUE] = "bird_duiwufx2",
}

local function players()
    return AllPlayers or {}
end

local function icon_key(recipient)
    return recipient ~= nil and recipient.userid ~= nil and ("minimap_icon" .. recipient.userid) or nil
end

local function remove_icon(source, recipient)
    local key = icon_key(recipient)
    if source == nil or key == nil then
        return
    end

    local icon = source[key]
    if icon ~= nil and icon:IsValid() then
        icon:Remove()
    end
    source[key] = nil
end

local function remove_icon_key(source, key)
    if source == nil or key == nil then
        return
    end

    local icon = source[key]
    if icon ~= nil and icon:IsValid() then
        icon:Remove()
    end
    source[key] = nil
end

local function clear_icons()
    for _, source in ipairs(players()) do
        for _, recipient in ipairs(players()) do
            remove_icon(source, recipient)
        end
    end
end

local function refresh_native_minimap_entities()
    for _, player in ipairs(players()) do
        local minimap = player.MiniMapEntity
        if minimap ~= nil and minimap.SetEnabled ~= nil then
            local team_id, pending = team_state.get_player_team(player)
            minimap:SetEnabled(not pending and team_id ~= team_state.TEAM_OBSERVER)
        end
    end
end

local function should_show_icon(source, recipient)
    if source == nil
        or recipient == nil
        or source.userid == nil
        or recipient.userid == nil
        or source._bird_map_marker_ready ~= true
        or recipient._bird_map_marker_ready ~= true then
        return false
    end

    local source_team, source_pending = team_state.get_player_team(source)
    local recipient_team, recipient_pending = team_state.get_player_team(recipient)
    if source_pending
        or recipient_pending
        or source_team == nil
        or source_team == team_state.TEAM_OBSERVER then
        return false
    end

    if source == recipient then
        return false
    end

    if recipient_team == team_state.TEAM_OBSERVER then
        return observer_markers_enabled
    end

    if not teammate_markers_enabled then
        return false
    end

    return source_team == recipient_team
        and TEAM_MARKER_PREFABS[source_team] ~= nil
end

local function attach_icon(source, recipient)
    local key = icon_key(recipient)
    if source == nil or key == nil then
        return
    end

    local existing_icon = source[key]
    if existing_icon ~= nil then
        if existing_icon:IsValid() then
            local x, _, z = source.Transform:GetWorldPosition()
            existing_icon.Transform:SetPosition(x, 0, z)
            return
        end
        source[key] = nil
    end

    local icon = SpawnPrefab("globalmapicon")
    if icon == nil then
        return
    end

    source[key] = icon
    icon:TrackEntity(source, nil, source.prefab ~= nil and (source.prefab .. ".png") or nil)
    if icon.MiniMapEntity ~= nil then
        icon.MiniMapEntity:SetPriority(10)
    end
    if icon.Network ~= nil then
        icon.Network:SetClassifiedTarget(recipient)
    end
    icon:ListenForEvent("onremove", function()
        remove_icon(source, recipient)
    end, source)
end

function M.set_enabled(value)
    teammate_markers_enabled = value == true
    if not teammate_markers_enabled and not observer_markers_enabled then
        clear_icons()
    end
end

function M.refresh_teammate_icons()
    refresh_native_minimap_entities()

    if not teammate_markers_enabled and not observer_markers_enabled then
        clear_icons()
        return
    end

    for _, source in ipairs(players()) do
        for _, recipient in ipairs(players()) do
            if should_show_icon(source, recipient) then
                attach_icon(source, recipient)
            else
                remove_icon(source, recipient)
            end
        end
    end
end

function M.remove_icons_for_userid(userid)
    if userid == nil then
        return
    end

    local key = "minimap_icon" .. tostring(userid)
    for _, source in ipairs(players()) do
        remove_icon_key(source, key)
    end
end

local function get_local_team_id()
    return team_state.get_player_team(ThePlayer)
end

function M.reveal_markers_for_local_team()
    if not teammate_markers_enabled or not TheNet:GetIsClient() or ThePlayer == nil then
        return
    end

    local marker_prefab = TEAM_MARKER_PREFABS[get_local_team_id()]
    if marker_prefab == nil then
        return
    end

    for _, ent in pairs(Ents) do
        if ent.prefab == marker_prefab and ent.AnimState ~= nil then
            ent.AnimState:SetLightOverride(1)
        end
    end
end

return M
