-- Team-marker registration hooks.
-- The shared marker implementation remains a normal require module.
local markers = require("src/team/markers")
local player_state = require("src/team/player_state")
local teammate_markers_enabled = true

markers.set_enabled(teammate_markers_enabled)

-- globalmapicon snapshots its target position immediately, so wait until the
-- player spawner has moved a migrating player away from the default origin.
local function mark_player_position_ready(player)
    if player == nil or not player:IsValid() then
        return
    end

    player._bird_map_marker_ready = true
    markers.refresh_teammate_icons()
end

AddComponentPostInit("playerspawner", function(spawner)
    if spawner._bird_map_marker_spawn_hook_installed or spawner.SpawnAtLocation == nil then
        return
    end

    spawner._bird_map_marker_spawn_hook_installed = true
    local SpawnAtLocation = spawner.SpawnAtLocation
    function spawner:SpawnAtLocation(world, player, ...)
        local result = SpawnAtLocation(self, world, player, ...)
        mark_player_position_ready(player)
        return result
    end
end)

if teammate_markers_enabled then
    AddPrefabPostInit("bird_duiwufx1", markers.reveal_markers_for_local_team)
    AddPrefabPostInit("bird_duiwufx2", markers.reveal_markers_for_local_team)
end

AddPlayerPostInit(function(inst)
    if not TheWorld.ismastersim then
        return
    end

    local userid = inst.userid
    inst._bird_map_marker_ready = false
    local function refresh()
        markers.refresh_teammate_icons()
    end

    inst:ListenForEvent(player_state.EVENT_PENDING, refresh)
    inst:ListenForEvent(player_state.EVENT_READY, refresh)
    inst:ListenForEvent(player_state.EVENT_FAILED, refresh)
    inst:ListenForEvent("playeractivated", function(player)
        mark_player_position_ready(player)
    end)
    inst:ListenForEvent("onremove", function()
        if TheWorld ~= nil and TheWorld.ismastersim then
            markers.remove_icons_for_userid(inst.userid or userid)
            TheWorld:DoTaskInTime(0, refresh)
        end
    end)

    inst:DoTaskInTime(0, refresh)
    inst:DoTaskInTime(1, refresh)
end)
