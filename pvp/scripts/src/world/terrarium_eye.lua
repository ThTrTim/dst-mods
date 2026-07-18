-- Retargets terrarium Eye of Terror spawns toward a random non-OB player.
local observer_privileges = require("src/observer/privileges")
local function is_excluded_from_pve_targeting(player)
    local fn = observer_privileges.is_excluded_from_pve_targeting or observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end

local MAX_UPVALUE_DEPTH = 5
local MAX_UPVALUES = 20
local SPAWN_RADIUS = 10

local function FunctionSourceMatches(fn, source_name, predicate, ...)
    if fn ~= nil and type(fn) ~= "function" then
        return false
    end

    local info = debug.getinfo(fn)
    if source_name ~= nil and type(source_name) == "string" then
        local expected_source = "/" .. source_name .. ".lua"
        if info.source == nil or not info.source:match(expected_source) then
            return false
        end
    end

    if predicate ~= nil and type(predicate) == "function" and not predicate(info, ...) then
        return false
    end

    return true
end

local function FindEventCallback(inst, event_name, source_name, predicate)
    if type(inst) ~= "table" then
        return
    end

    if inst.event_listening ~= nil and inst.event_listening[event_name] ~= nil then
        for target, listeners in pairs(inst.event_listening[event_name]) do
            if listeners ~= nil and type(listeners) == "table" then
                for _, fn in pairs(listeners) do
                    if FunctionSourceMatches(fn, source_name, predicate, target, inst) then
                        return fn
                    end
                end
            end
        end
    end

    if inst.event_listeners ~= nil and inst.event_listeners[event_name] ~= nil then
        for target, listeners in pairs(inst.event_listeners[event_name]) do
            if listeners ~= nil and type(listeners) == "table" then
                for _, fn in pairs(listeners) do
                    if FunctionSourceMatches(fn, source_name, predicate, inst, target) then
                        return fn
                    end
                end
            end
        end
    end
end

local function FindUpvalueRecursive(fn, target_name, max_depth, max_upvalues, depth, source_name)
    if type(fn) ~= "function" then
        return
    end

    max_depth = max_depth or MAX_UPVALUE_DEPTH
    max_upvalues = max_upvalues or MAX_UPVALUES
    depth = depth or 0

    for index = 1, max_upvalues do
        local name, value = debug.getupvalue(fn, index)
        if name ~= nil and name == target_name then
            if source_name ~= nil and type(source_name) == "string" then
                local info = debug.getinfo(fn)
                if info.source ~= nil and info.source:match(source_name) then
                    return value
                end
            else
                return value
            end
        end

        if depth < max_depth and value ~= nil and type(value) == "function" then
            local found = FindUpvalueRecursive(value, target_name, max_depth, max_upvalues, depth + 1, source_name)
            if found ~= nil then
                return found
            end
        end
    end
end

local function ReplaceUpvalueRecursive(fn, target_name, replacement, max_depth, max_upvalues, depth, source_name)
    if type(fn) ~= "function" then
        return
    end

    max_depth = max_depth or MAX_UPVALUE_DEPTH
    max_upvalues = max_upvalues or MAX_UPVALUES
    depth = depth or 0

    for index = 1, max_upvalues do
        local name, value = debug.getupvalue(fn, index)
        if name ~= nil and name == target_name then
            if source_name ~= nil and type(source_name) == "string" then
                local info = debug.getinfo(fn)
                if info.source ~= nil and info.source:match(source_name) then
                    return debug.setupvalue(fn, index, replacement)
                end
            else
                return debug.setupvalue(fn, index, replacement)
            end
        end

        if depth < max_depth and value ~= nil and type(value) == "function" then
            local replaced = ReplaceUpvalueRecursive(value, target_name, replacement, max_depth, max_upvalues, depth + 1, source_name)
            if replaced ~= nil then
                return replaced
            end
        end
    end
end

local function IsCrimsonTerrarium(inst)
    return inst._iscrimson:value()
end

local function SpawnEyePrefab(inst)
    return SpawnPrefab(IsCrimsonTerrarium(inst) and "twinmanager" or "eyeofterror")
end

local function BindEyeCleanupEvents(terrarium, eye)
    terrarium:ListenForEvent("onremove", terrarium.on_end_eyeofterror_fn, eye)
    terrarium:ListenForEvent("turnoff_terrarium", terrarium.on_end_eyeofterror_fn, eye)
    terrarium:ListenForEvent("finished_leaving", terrarium.on_eye_left_fn, eye)
end

local function GetNonObserverPlayers()
    local players = {}
    for _, player in ipairs(AllPlayers) do
        if not is_excluded_from_pve_targeting(player) then
            table.insert(players, player)
        end
    end
    return players
end

local function SpawnEyeNearRandomPlayer(terrarium)
    local players = GetNonObserverPlayers()
    if players == nil or #players <= 0 then
        return
    end

    local target = players[math.random(#players)]
    local target_msg = IsCrimsonTerrarium(terrarium) and STRINGS.TWINS_TARGET or STRINGS.EYEOFTERROR_TARGET
    TheNet:Announce(subfmt(target_msg, { player_name = target.name }))

    local theta = math.random() * 2 * PI
    local target_pos = target:GetPosition()
    local offset = FindWalkableOffset(target_pos, theta, SPAWN_RADIUS, nil, false, true, nil, true, true)
        or Vector3(SPAWN_RADIUS * math.cos(theta), 0, SPAWN_RADIUS * math.sin(theta))
    local spawn_pos = target_pos + offset

    if terrarium.eyeofterror ~= nil and terrarium.eyeofterror:IsInLimbo() then
        terrarium.eyeofterror:ReturnToScene()
        terrarium.eyeofterror.Transform:SetPosition(spawn_pos:Get())
        if terrarium.eyeofterror.sg ~= nil then
            terrarium.eyeofterror.sg:GoToState("flyback", target)
        else
            terrarium.eyeofterror:PushEvent("flyback", target)
        end
    else
        terrarium.eyeofterror = SpawnEyePrefab(terrarium)
        terrarium.eyeofterror.Transform:SetPosition(spawn_pos:Get())
        if terrarium.eyeofterror.sg ~= nil then
            terrarium.eyeofterror.sg:GoToState("arrive", target)
        else
            terrarium.eyeofterror:PushEvent("arrive", target)
        end
    end

    terrarium.eyeofterror:PushEvent("set_spawn_target", target)
    BindEyeCleanupEvents(terrarium, terrarium.eyeofterror)
end

AddPrefabPostInit("terrarium", function(inst)
    local timerdone_callback = FindEventCallback(inst, "timerdone", "prefabs/terrarium")
    if timerdone_callback == nil then
        return
    end

    if FindUpvalueRecursive(timerdone_callback, "SpawnEyeOfTerror") ~= nil then
        ReplaceUpvalueRecursive(timerdone_callback, "SpawnEyeOfTerror", SpawnEyeNearRandomPlayer)
    end
end)
