-- Shares book research station tech bonuses with teammates.
local team_state = require("src/team/lobby_team_state")

local function get_team_id(player)
    return team_state.get_player_team(player)
end

local function get_recipients(reader)
    local x, y, z = reader.Transform:GetWorldPosition()
    local nearby_players = FindPlayersInRange(x, y, z, TUNING.BOOK_RESEARCH_STATION_RADIUS, true)

    if TheWorld:HasTag("cave") then
        return nearby_players
    end

    if TheWorld.state.cycles < 1 and (TheWorld.state.isdusk or TheWorld.state.isnight) then
        return AllPlayers
    end

    if TheWorld.state.cycles >= 1 then
        return AllPlayers
    end

    return nearby_players
end

local function show_research_fx(player)
    local fx_name = player.components.rider ~= nil
        and player.components.rider:IsRiding()
        and "fx_book_research_station_mount"
        or "fx_book_research_station"

    local fx = SpawnPrefab(fx_name)
    if fx ~= nil then
        fx.Transform:SetPosition(player.Transform:GetWorldPosition())
        fx.Transform:SetRotation(player.Transform:GetRotation())
    end
end

local function on_read(station, reader)
    local reader_team = get_team_id(reader)
    if not team_state.is_playing_team(reader_team) then
        return true
    end

    for _, player in pairs(get_recipients(reader)) do
        local player_team = get_team_id(player)
        if player_team == reader_team and player.components.builder ~= nil then
            player.components.builder:GiveTempTechBonus({ SCIENCE = 2, MAGIC = 2, SEAFARING = 2 })
            show_research_fx(player)
        end
    end

    return true
end

AddPrefabPostInit("book_research_station", function(inst)
    if inst.components.book ~= nil then
        inst.components.book:SetOnRead(on_read)
    end
end)
