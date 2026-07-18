-- Seasonal boss timing changes from the original PVP mod.
local team_state = require("src/team/lobby_team_state")

local function PickBeargerTarget()
    local teamed_players = {}
    local all_players = {}

    for _, player in ipairs(AllPlayers) do
        local team_id = team_state.get_player_team(player)
        if not IsEntityDeadOrGhost(player, true)
            and team_state.is_playing_team(team_id) then
            table.insert(teamed_players, player)
        end

        table.insert(all_players, player)
    end

    if next(teamed_players) ~= nil then
        return #teamed_players == 1 and teamed_players[1] or teamed_players[math.random(#teamed_players)]
    end

    if next(all_players) ~= nil then
        return #all_players == 1 and all_players[1] or all_players[math.random(#all_players)]
    end
end

local function FindBeargerSpawnPoint(pos)
    if not TheWorld.Map:IsAboveGroundAtPoint(pos:Get()) then
        pos = FindNearbyLand(pos, 1) or pos
    end

    local offset = FindWalkableOffset(pos, math.random() * 2 * PI, 40, 12, true)
    if offset ~= nil then
        offset.x = offset.x + pos.x
        offset.z = offset.z + pos.z
        return offset
    end
end

AddPrefabPostInit("moose_nesting_ground", function(inst)
    if inst.components.timer == nil then
        return
    end

    local StartTimer = inst.components.timer.StartTimer
    inst.components.timer.StartTimer = function(self, name, time)
        if name == "CallMoose" then
            time = math.random(5)
        end

        return StartTimer(self, name, time)
    end
end)

local function OnPhaseChanged(world, phase)
    if TheWorld.state.season == "winter"
        and TheWorld.state.winterlength - TheWorld.state.remainingdaysinseason == 2
        and phase == "night" then
        if TheWorld.components.deerclopsspawner ~= nil then
            TheWorld.components.deerclopsspawner:SummonMonster()
        end
    elseif TheWorld.state.season == "spring"
        and TheWorld.state.springlength - TheWorld.state.remainingdaysinseason == 2
        and phase == "day" then
        if TheWorld.components.moosespawner ~= nil then
            TheWorld.components.moosespawner:InitializeNests()
        end
    elseif TheWorld.state.season == "autumn"
        and TheWorld.state.autumnlength - TheWorld.state.remainingdaysinseason == 2
        and phase == "dusk" then
        local target = PickBeargerTarget()
        if target ~= nil then
            SpawnPrefab("beargerwarning_lvl4").Transform:SetPosition(target.Transform:GetWorldPosition())

            local spawn_point = FindBeargerSpawnPoint(target:GetPosition())
            if spawn_point ~= nil then
                local bearger = SpawnPrefab("bearger")
                bearger.Physics:Teleport(spawn_point:Get())
            end
        end
    end
end

AddPrefabPostInit("world", function(inst)
    if not TheWorld.ismastersim then
        return
    end

    inst:DoTaskInTime(0, function()
        if not inst:HasTag("cave") then
            inst:WatchWorldState("phase", OnPhaseChanged)
        end
    end)
end)