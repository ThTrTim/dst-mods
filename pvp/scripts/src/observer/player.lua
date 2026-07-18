-- Observer-specific per-player initialization.
-- This is a registration script and must be loaded with modimport.
local status = require("src/observer/status")
local observer_privileges = require("src/observer/privileges")
local player_state = require("src/team/player_state")

local function can_use_referee_panel(player)
    local fn = observer_privileges.can_use_referee_panel or observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end

AddPlayerPostInit(function(inst)
    inst.duiwuinfo = inst.duiwuinfo or { {}, {} }

    if not TheWorld.ismastersim then
        return
    end

    inst:ListenForEvent("onremove", function()
        if status.is_subscribed(inst) then
            status.set_subscribed(inst, false)
        end
    end)

    local function refresh_observer_privileges()
        if can_use_referee_panel(inst) then
            status.set_subscribed(inst, true)
            if inst.components.playerlightningtarget ~= nil then
                inst.components.playerlightningtarget:SetHitChance(0)
            end
        end
    end

    inst:ListenForEvent(player_state.EVENT_READY, refresh_observer_privileges)
    inst:DoTaskInTime(0, refresh_observer_privileges)
    inst:DoTaskInTime(0.5, refresh_observer_privileges)
    inst:DoTaskInTime(2, refresh_observer_privileges)
end)
