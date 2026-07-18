-- Shared player-effect guards.
-- Consolidates first-day protection and observer-camera immunity so each hook is installed once.
local OBSERVER_TAG = "bird_observer_camera"
local team_state = require("src/team/lobby_team_state")

local function is_observer_camera(inst)
    if inst == nil then
        return false
    end

    local team_id, pending = team_state.get_player_team(inst)
    if pending or team_id == nil or team_state.is_playing_team(team_id) then
        return false
    end

    return team_id == team_state.TEAM_OBSERVER
end

local function is_first_day_player(inst)
    return inst ~= nil
        and inst:HasTag("player")
        and TheWorld ~= nil
        and TheWorld.state.cycles < 1
end

local function is_player_follower(attacker)
    return attacker ~= nil
        and attacker.components ~= nil
        and attacker.components.follower ~= nil
        and attacker.components.follower.leader ~= nil
        and attacker.components.follower.leader:HasTag("player")
end

local function install_health_guard()
    AddComponentPostInit("health", function(self)
        local SetInvincible = self.SetInvincible
        function self:SetInvincible(invincible, ...)
            if is_observer_camera(self.inst) then
                invincible = true
            end
            return SetInvincible(self, invincible, ...)
        end
    end)
end

local function install_control_effect_guards()
    AddComponentPostInit("freezable", function(self)
        local AddColdness = self.AddColdness
        function self:AddColdness(...)
            if is_observer_camera(self.inst) or is_first_day_player(self.inst) then
                return
            end
            return AddColdness(self, ...)
        end
    end)

    AddComponentPostInit("grogginess", function(self)
        local AddGrogginess = self.AddGrogginess
        function self:AddGrogginess(...)
            if is_observer_camera(self.inst) or is_first_day_player(self.inst) then
                return
            end
            return AddGrogginess(self, ...)
        end
    end)

    AddComponentPostInit("pinnable", function(self)
        local Stick = self.Stick
        function self:Stick(...)
            if is_observer_camera(self.inst) then
                return
            end
            return Stick(self, ...)
        end
    end)
end

local function install_stategraph_guard()
    AddStategraphPostInit("wilson", function(stategraph)
        local attacked = stategraph.events.attacked
        if attacked == nil or attacked.fn == nil then
            return
        end

        local OnAttacked = attacked.fn
        stategraph.events.attacked = EventHandler("attacked", function(inst, data, ...)
            if is_observer_camera(inst)
                and not inst.sg:HasStateTag("frozen")
                and not inst.sg:HasStateTag("sleeping") then
                return
            end
            return OnAttacked(inst, data, ...)
        end)
    end)
end

local function install_player_guards()
    AddPlayerPostInit(function(inst)
        if not TheWorld.ismastersim then
            return
        end

        if inst.components.combat ~= nil then
            local GetAttacked = inst.components.combat.GetAttacked
            inst.components.combat.GetAttacked = function(self, attacker, damage, weapon, stimuli, ...)
                if is_observer_camera(self.inst) then
                    return false
                end

                if TheWorld.state.cycles < 1 then
                    if attacker ~= nil and attacker:HasTag("player") and weapon ~= nil then
                        return true
                    elseif is_player_follower(attacker) then
                        return true
                    end
                end

                return GetAttacked(self, attacker, damage, weapon, stimuli, ...)
            end
        end

        if inst.components.burnable ~= nil then
            local Ignite = inst.components.burnable.Ignite
            inst.components.burnable.Ignite = function(self, immediate, source, doer, ...)
                if TheWorld.state.cycles < 1 then
                    return
                end
                return Ignite(self, immediate, source, doer, ...)
            end
        end
    end)
end

install_health_guard()
install_control_effect_guards()
install_stategraph_guard()
install_player_guards()