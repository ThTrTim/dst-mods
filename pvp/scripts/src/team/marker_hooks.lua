-- Team-marker registration hooks.
-- The shared marker implementation remains a normal require module.
local markers = require("src/team/markers")
local player_state = require("src/team/player_state")
local teammate_markers_enabled = true

markers.set_enabled(teammate_markers_enabled)

if teammate_markers_enabled then
    AddPrefabPostInit("bird_duiwufx1", markers.reveal_markers_for_local_team)
    AddPrefabPostInit("bird_duiwufx2", markers.reveal_markers_for_local_team)
end

AddPlayerPostInit(function(inst)
    if not TheWorld.ismastersim then
        return
    end

    local userid = inst.userid
    local function refresh()
        markers.refresh_teammate_icons()
    end

    inst:ListenForEvent(player_state.EVENT_PENDING, refresh)
    inst:ListenForEvent(player_state.EVENT_READY, refresh)
    inst:ListenForEvent(player_state.EVENT_FAILED, refresh)
    inst:ListenForEvent("onremove", function()
        if TheWorld ~= nil and TheWorld.ismastersim then
            markers.remove_icons_for_userid(inst.userid or userid)
            TheWorld:DoTaskInTime(0, refresh)
        end
    end)

    inst:DoTaskInTime(0, refresh)
    inst:DoTaskInTime(1, refresh)
end)
