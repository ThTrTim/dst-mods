local debug_log = require("src/core/debug")
local player_state = require("src/team/player_state")
local team_state = require("src/team/lobby_team_state")

local VALID_TEAMS = {
    [0] = true, -- observer
    [1] = true, -- red
    [2] = true, -- blue
}

local function RemoveGroundFx(self)
    if self.ground_fx ~= nil then
        if self.ground_fx:IsValid() then
            self.ground_fx:Remove()
        end
        self.ground_fx = nil
    end
end

local function EnsureGroundFx(self, team_id)
    local expected_prefab = team_id ~= 0 and ("bird_duiwufx" .. team_id) or nil

    if self.ground_fx ~= nil
        and (expected_prefab == nil or self.ground_fx.prefab ~= expected_prefab) then
        RemoveGroundFx(self)
    end

    if expected_prefab ~= nil and self.ground_fx == nil then
        debug_log.log("team-fx", "spawn", expected_prefab, tostring(self.inst.userid), tostring(self.inst.prefab))
        self.ground_fx = SpawnPrefab(expected_prefab)
        if self.ground_fx ~= nil then
            self.ground_fx.entity:SetParent(self.inst.entity)
            debug_log.log("team-fx", "spawned", expected_prefab, tostring(self.ground_fx.GUID))
        else
            debug_log.log("team-fx", "spawn failed", expected_prefab)
        end
    end
end

local function OnTeamChanged(self, team_id)
    self._bird_last_team = team_id
end

local function GetSavedTeam(self)
    local team_id = nil
    team_id = player_state.get(self.inst)
    if team_id == nil then
        local netvar_team, netvar_ready = player_state.get_netvar(self.inst)
        if netvar_ready then
            team_id = netvar_team
        end
    end
    return team_state.normalize(team_id) or team_state.normalize(self.duiwu)
end

local TeamComponent = Class(function(self, inst)
    self.inst = inst
    self.duiwu = nil
end,
nil,
{
    duiwu = OnTeamChanged,
})

function TeamComponent:OnSave()
    local team_id = GetSavedTeam(self)
    return {
        -- `duiwu` is kept for old red/blue/observer component compatibility.
        duiwu = VALID_TEAMS[team_id] and team_id or nil,
        -- `bird_team` is the actual migration mirror and can carry waiting.
        bird_team = team_id,
    }
end

function TeamComponent:OnLoad(data)
    local team_id = nil
    if data ~= nil then
        team_id = data.bird_team ~= nil and data.bird_team or data.duiwu
    end

    team_id = team_state.normalize(team_id)
    if team_id ~= nil then
        self._bird_has_loaded_team = true
        self._bird_loaded_team = team_id
        if VALID_TEAMS[team_id] and self.duiwu ~= team_id then
            self.duiwu = team_id
        elseif not VALID_TEAMS[team_id] then
            self.duiwu = nil
            RemoveGroundFx(self)
        end
        player_state.set_ready(self.inst, team_id, "component-load")
    end
end

function TeamComponent:Choose(team_id)
    team_id = tonumber(team_id)
    if not VALID_TEAMS[team_id] then
        return false
    end

    self.duiwu = team_id
    return true
end

function TeamComponent:ClearTeam()
    self.duiwu = nil
    self._bird_has_loaded_team = false
    self._bird_loaded_team = nil
    RemoveGroundFx(self)
    return true
end

function TeamComponent:ApplyGroundFx(team_id)
    team_id = tonumber(team_id)
    if VALID_TEAMS[team_id] then
        EnsureGroundFx(self, team_id)
    end
end

function TeamComponent:OnRemoveFromEntity()
    RemoveGroundFx(self)
end

return TeamComponent
