-- OB camera shell: keep the player connection/camera anchor, remove gameplay presence.
local M = {}
local debug_log = require("src/core/debug")

local OBSERVER_TAG = "bird_observer_camera"
local OBSERVER_SPEED_KEY = "bird_observer_speed"
local OBSERVER_SPEED_MULTIPLIER = 4
local REVEAL_STEP = 30
local REVEAL_AREAS_PER_TICK = 80
local REVEAL_PERIOD = 0.05
local OBSERVER_BLOCKED_STATES = {
    yawn = true,
    knockout = true,
    bedroll = true,
    tent = true,
    wakeup = true,
}
local OBSERVER_SLEEP_EVENTS = {
    "yawn",
    "knockedout",
    "gotosleep",
}

local function safe_call(component, method, ...)
    if component ~= nil and component[method] ~= nil then
        return component[method](component, ...)
    end
end
local function player_label(inst)
    if inst == nil then
        return "nil"
    end
    return tostring(inst.userid) .. "/" .. tostring(inst.prefab)
end

local function hide_visuals(inst)
    if inst == nil then
        return
    end

    inst._bird_observer_visual_hidden = true

    if inst.Hide ~= nil then
        inst:Hide()
    end
    if inst.entity ~= nil and inst.entity.Hide ~= nil then
        inst.entity:Hide()
    end
    if inst.AnimState ~= nil then
        inst.AnimState:SetMultColour(0, 0, 0, 0)
    end
    if inst.DynamicShadow ~= nil then
        inst.DynamicShadow:SetSize(0, 0)
    end
    if inst.MiniMapEntity ~= nil and inst.MiniMapEntity.SetEnabled ~= nil then
        inst.MiniMapEntity:SetEnabled(false)
    end
end

local function restore_visuals(inst)
    if inst == nil or not inst._bird_observer_visual_hidden then
        return
    end

    inst._bird_observer_visual_hidden = nil

    if inst.Show ~= nil then
        inst:Show()
    end
    if inst.entity ~= nil and inst.entity.Show ~= nil then
        inst.entity:Show()
    end
    if inst.AnimState ~= nil then
        inst.AnimState:SetMultColour(1, 1, 1, 1)
    end
end

local function clear_legacy_observer_ghost_state(inst)
    inst:RemoveTag("playerghost")
    inst:RemoveTag("ghost")
    inst:RemoveTag("corpse")

    if inst.player_classified ~= nil then
        if inst.player_classified.isghostmode ~= nil then
            inst.player_classified.isghostmode:set(false)
        end
        if inst.player_classified.ghostmode ~= nil then
            inst.player_classified.ghostmode:set(false)
        end
    end

    if inst._bird_observer_light ~= nil then
        safe_call(inst._bird_observer_light, "Enable", false)
        safe_call(inst._bird_observer_light, "SetRadius", 0)
        safe_call(inst._bird_observer_light, "SetIntensity", 0)
    end
end

local STRIPPED_OBSERVER_COMPONENTS = {
    -- World reactions and passive effects.
    "drownable",
    "grogginess",
    "sleeper",
    "playerlightningtarget",
    "sanityaura",
    "bloomer",

    -- Keep ordinary interaction components installed. Character prefabs and
    -- post-handshake hooks often assume they exist; observer actions are
    -- blocked by the action/HUD layer instead.
}

local function ensure_observer_core_components(inst)
    if inst.components == nil or inst.AddComponent == nil then
        return
    end
    if inst.components.inventory == nil then
        inst:AddComponent("inventory")
    end
    if inst.components.playeractionpicker == nil then
        inst:AddComponent("playeractionpicker")
    end
    if inst.components.builder == nil then
        inst:AddComponent("builder")
    end
    if inst.components.combat == nil then
        inst:AddComponent("combat")
    end
    if inst.components.talker == nil then
        inst:AddComponent("talker")
    end
    if inst.components.burnable == nil then
        inst:AddComponent("burnable")
    end
    if inst.components.freezable == nil then
        inst:AddComponent("freezable")
    end
end

local function strip_observer_components(inst)
    if inst.components == nil or inst.RemoveComponent == nil then
        return
    end

    if inst._bird_observer_components_stripped then
        return
    end

    for _, name in ipairs(STRIPPED_OBSERVER_COMPONENTS) do
        if inst.components[name] ~= nil then
            inst:RemoveComponent(name)
        end
    end
    inst._bird_observer_components_stripped = true
end

local function silence_observer_talker(inst)
    local talker = inst.components ~= nil and inst.components.talker or nil
    if talker == nil or talker._bird_observer_silenced then
        return
    end

    local Say = talker.Say
    function talker:Say(...)
        if inst.bird_observer_camera == true or (inst.HasTag ~= nil and inst:HasTag(OBSERVER_TAG)) then
            return
        end
        return Say(self, ...)
    end

    talker._bird_observer_silenced = true
end

local function is_observer_entity(inst)
    return inst ~= nil
        and (inst.bird_observer_camera == true
            or (inst.HasTag ~= nil and inst:HasTag(OBSERVER_TAG)))
end

local function clear_sleep_components(inst)
    local components = inst ~= nil and inst.components or nil
    if components == nil then
        return
    end

    local sleeper = components.sleeper
    if sleeper ~= nil then
        sleeper.isasleep = false
        sleeper.sleepiness = 0
        sleeper.hibernate = false
        safe_call(sleeper, "StopTesting")
    end

    local grogginess = components.grogginess
    if grogginess ~= nil then
        grogginess.grog_amount = 0
        grogginess.knockedout = false
        grogginess.knockouttime = 0
        grogginess.knockoutduration = 0
        grogginess.wearofftime = 0
        inst:RemoveTag("groggy")
        if inst.StopUpdatingComponent ~= nil then
            inst:StopUpdatingComponent(grogginess)
        end
    end
end

local function force_observer_idle(inst)
    if inst == nil or inst.sg == nil then
        return
    end

    local state = inst.sg.currentstate ~= nil and inst.sg.currentstate.name or nil
    if OBSERVER_BLOCKED_STATES[state] then
        inst.sg:GoToState("idle")
    end
end

local function install_observer_sleep_guard(inst)
    if inst == nil or inst._bird_observer_sleep_guard_installed then
        return
    end

    inst._bird_observer_sleep_guard_installed = true

    if inst.sg ~= nil and inst.sg.GoToState ~= nil then
        local GoToState = inst.sg.GoToState
        function inst.sg:GoToState(statename, ...)
            if is_observer_entity(inst) and OBSERVER_BLOCKED_STATES[statename] then
                clear_sleep_components(inst)
                if self.currentstate == nil or self.currentstate.name ~= "idle" then
                    return GoToState(self, "idle")
                end
                return false
            end
            return GoToState(self, statename, ...)
        end
    end

    local function on_sleep_event(player)
        if is_observer_entity(player) then
            clear_sleep_components(player)
            player:DoTaskInTime(0, force_observer_idle)
        end
    end

    for _, event in ipairs(OBSERVER_SLEEP_EVENTS) do
        inst:ListenForEvent(event, on_sleep_event)
    end
end

local function neutralize_observer_survival_state(inst)
    if inst.components == nil or inst._bird_observer_survival_neutralized then
        return
    end

    if inst.components.health ~= nil then
        inst.components.health:SetPercent(1)
        inst.components.health:SetInvincible(true)
    end
    if inst.components.hunger ~= nil then
        inst.components.hunger:SetPercent(1)
        safe_call(inst.components.hunger, "Pause")
    end
    if inst.components.sanity ~= nil then
        inst.components.sanity:SetPercent(1)
        inst.components.sanity.dapperness = 0
    end
    if inst.components.moisture ~= nil then
        safe_call(inst.components.moisture, "SetPercent", 0)
        if inst.components.moisture.SetRateScale ~= nil then
            inst.components.moisture:SetRateScale(0)
        end
    end
    if inst.components.temperature ~= nil then
        safe_call(inst.components.temperature, "SetTemp", 25)
    end
    if inst.components.combat ~= nil then
        inst.components.combat:SetTarget(nil)
    end
    if inst.components.burnable ~= nil then
        safe_call(inst.components.burnable, "Extinguish")
    end
    if inst.components.freezable ~= nil then
        safe_call(inst.components.freezable, "Unfreeze")
        safe_call(inst.components.freezable, "Reset")
    end
    clear_sleep_components(inst)

    inst._bird_observer_survival_neutralized = true
end

local function get_world_reveal_key()
    if TheWorld == nil then
        return "unknown"
    end

    if TheWorld.HasTag ~= nil and TheWorld:HasTag("cave") then
        return "cave"
    end

    return tostring(TheWorld.worldprefab or TheWorld.prefab or "forest")
end

local function stop_reveal_task(inst, reveal_key)
    local tasks = inst ~= nil and inst._bird_full_map_reveal_tasks or nil
    local task = tasks ~= nil and tasks[reveal_key] or nil
    if task ~= nil then
        task:Cancel()
        tasks[reveal_key] = nil
    end
end

local function finish_reveal_task(inst, reveal_key)
    debug_log.log("observer-camera", "reveal finished", player_label(inst), tostring(reveal_key))
    local revealed = inst._bird_full_map_revealed_by_world
    if revealed == nil then
        revealed = {}
        inst._bird_full_map_revealed_by_world = revealed
    end
    revealed[reveal_key] = true
    stop_reveal_task(inst, reveal_key)
end
local function stop_all_reveal_tasks(inst)
    local tasks = inst ~= nil and inst._bird_full_map_reveal_tasks or nil
    if tasks == nil then
        return
    end

    for key, task in pairs(tasks) do
        if task ~= nil then
            task:Cancel()
        end
        tasks[key] = nil
    end
end

local function apply_observer_speed(inst)
    local locomotor = inst.components ~= nil and inst.components.locomotor or nil
    if locomotor ~= nil and locomotor.SetExternalSpeedMultiplier ~= nil then
        locomotor:SetExternalSpeedMultiplier(inst, OBSERVER_SPEED_KEY, OBSERVER_SPEED_MULTIPLIER)
    end
end

local function clear_observer_speed(inst)
    local locomotor = inst.components ~= nil and inst.components.locomotor or nil
    if locomotor ~= nil and locomotor.RemoveExternalSpeedMultiplier ~= nil then
        locomotor:RemoveExternalSpeedMultiplier(inst, OBSERVER_SPEED_KEY)
    end
end

local function reveal_full_map(inst, force)
    if inst == nil or TheWorld == nil or TheWorld.Map == nil then
        debug_log.log("observer-camera", "reveal skipped", player_label(inst), "world/map missing")
        return
    end
    if not M.is_observer(inst) then
        debug_log.log("observer-camera", "reveal skipped", player_label(inst), "not observer")
        return
    end

    local reveal_key = get_world_reveal_key()
    local revealed = inst._bird_full_map_revealed_by_world
    if revealed == nil then
        revealed = {}
        inst._bird_full_map_revealed_by_world = revealed
    end
    if revealed[reveal_key] and not force then
        return
    end

    local explorer = inst.player_classified ~= nil and inst.player_classified.MapExplorer or nil
    if explorer == nil then
        debug_log.log("observer-camera", "reveal skipped", player_label(inst), tostring(reveal_key), "explorer missing")
        return
    end

    local tasks = inst._bird_full_map_reveal_tasks
    if tasks == nil then
        tasks = {}
        inst._bird_full_map_reveal_tasks = tasks
    end
    if tasks[reveal_key] ~= nil then
        if not force then
            return
        end
        stop_reveal_task(inst, reveal_key)
    end

    revealed[reveal_key] = nil
    debug_log.log("observer-camera", "reveal start", player_label(inst), tostring(reveal_key), "force", tostring(force))
    local width, height = TheWorld.Map:GetSize()
    local state = {
        x = -width * 4,
        z = -height * 4,
        min_z = -height * 4,
        max_x = width * 4,
        max_z = height * 4,
    }

    tasks[reveal_key] = inst:DoPeriodicTask(REVEAL_PERIOD, function(player)
        if player == nil or not player:IsValid() then
            stop_reveal_task(inst, reveal_key)
            return
        end

        local current_explorer = player.player_classified ~= nil and player.player_classified.MapExplorer or nil
        if current_explorer == nil then
            return
        end

        local count = 0
        while count < REVEAL_AREAS_PER_TICK do
            current_explorer:RevealArea(state.x, 0, state.z)
            count = count + 1

            state.z = state.z + REVEAL_STEP
            if state.z > state.max_z then
                state.z = state.min_z
                state.x = state.x + REVEAL_STEP
                if state.x > state.max_x then
                    finish_reveal_task(player, reveal_key)
                    return
                end
            end
        end
    end)
end

local function keep_noninteractive(inst, stop_motion)
    if inst == nil or not inst:IsValid() then
        return
    end

    inst.bird_observer_camera = true

    inst:AddTag(OBSERVER_TAG)
    inst:AddTag("notarget")
    inst:AddTag("noclick")
    inst:AddTag("NOCLICK")
    inst:AddTag("noauradamage")
    inst:AddTag("ignorewalkableplatforms")
    inst:RemoveTag("INLIMBO")
    inst:AddTag("notraptrigger")
    clear_legacy_observer_ghost_state(inst)
    ensure_observer_core_components(inst)
    strip_observer_components(inst)
    neutralize_observer_survival_state(inst)
    silence_observer_talker(inst)
    install_observer_sleep_guard(inst)

    if inst.components.locomotor ~= nil then
        if stop_motion then
            inst.components.locomotor:Stop()
        end
        apply_observer_speed(inst)
        inst.components.locomotor:SetSlowMultiplier(1)
        inst.components.locomotor.pathcaps = {
            player = true,
            ignorecreep = true,
            allowocean = true,
        }
        inst.components.locomotor.fasteronroad = false
        inst.components.locomotor:SetTriggersCreep(false)
        safe_call(inst.components.locomotor, "SetAllowPlatformHopping", false)
    end

    if inst.Physics ~= nil then
        RemovePhysicsColliders(inst)
    end
    hide_visuals(inst)

    if stop_motion and inst.sg ~= nil and not inst.sg:HasStateTag("idle") then
        inst.sg:GoToState("idle")
    end
end

function M.is_observer(inst)
    return is_observer_entity(inst)
end

function M.apply_visual_state(inst, is_observer)
    if is_observer then
        hide_visuals(inst)
    else
        M.disable(inst)
    end
end

function M.disable(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    debug_log.log("observer-camera", "disable", player_label(inst), "was", tostring(M.is_observer(inst)))
    inst.bird_observer_camera = false
    if inst.RemoveTag ~= nil then
        inst:RemoveTag(OBSERVER_TAG)
        inst:RemoveTag("notarget")
        inst:RemoveTag("noclick")
        inst:RemoveTag("NOCLICK")
        inst:RemoveTag("noauradamage")
        inst:RemoveTag("ignorewalkableplatforms")
        inst:RemoveTag("notraptrigger")
    end

    stop_all_reveal_tasks(inst)
    clear_observer_speed(inst)
    restore_visuals(inst)
end

function M.enable(inst)
    if inst == nil or not inst:IsValid() then
        return
    end

    debug_log.log("observer-camera", "enable", player_label(inst))
    keep_noninteractive(inst, true)
    inst:DoTaskInTime(0, reveal_full_map)
    inst:DoTaskInTime(1, reveal_full_map)
    inst:DoTaskInTime(3, reveal_full_map)

    local function delayed_refresh(player)
        if M.is_observer(player) then
            keep_noninteractive(player, false)
        end
    end
    inst:DoTaskInTime(0, delayed_refresh)
    inst:DoTaskInTime(0.5, delayed_refresh)
    inst:DoTaskInTime(2, delayed_refresh)
end

function M.reveal_full_map(inst)
    debug_log.log("observer-camera", "reveal rpc", player_label(inst))
    reveal_full_map(inst, true)
end

function M.teleport(inst, x, z)
    if not M.is_observer(inst) then
        return false
    end

    x = tonumber(x)
    z = tonumber(z)
    if x == nil or z == nil then
        return false
    end

    if inst.components.locomotor ~= nil then
        inst.components.locomotor:Stop()
    end
    if inst.Physics ~= nil then
        inst.Physics:Teleport(x, 0, z)
    else
        inst.Transform:SetPosition(x, 0, z)
    end
    keep_noninteractive(inst, true)
    return true
end

return M
