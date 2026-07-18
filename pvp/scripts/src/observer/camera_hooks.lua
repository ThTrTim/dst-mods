-- Registration hooks for OB camera shell.
-- This file is loaded with modimport so AddComponentPostInit/AddPlayerPostInit are available.
local observer_camera = require("src/observer/camera_mode")
local team_state = require("src/team/lobby_team_state")
local player_state = require("src/team/player_state")

local OBSERVER_NIGHTVISION_SOURCE = {}
local OBSERVER_NIGHTVISION_PRIORITY = 100
local OBSERVER_NIGHTVISION_COLOURCUBES = {
    day = "images/colour_cubes/identity_colourcube.tex",
    dusk = "images/colour_cubes/identity_colourcube.tex",
    night = "images/colour_cubes/identity_colourcube.tex",
    full_moon = "images/colour_cubes/identity_colourcube.tex",
}
local OBSERVER_CAMERA_MIN_DISTANCE = 15
local OBSERVER_CAMERA_MAX_DISTANCE = 999
local OBSERVER_CAMERA_DEFAULT_DISTANCE = 120
local OBSERVER_CAMERA_MIN_PITCH = 25
local OBSERVER_CAMERA_MAX_PITCH = 70
local observer_large_view_enabled = false
local observer_nightvision_enabled = false

local function sync_visual_state(inst)
    local team_id, pending = team_state.get_player_team(inst)
    if pending or team_id == nil then
        return
    end
    observer_camera.apply_visual_state(inst, team_id == team_state.TEAM_OBSERVER)
end

local function is_observer_owner(owner)
    if owner == nil then
        return false
    end

    if owner.bird_observer_camera == true
        or owner:HasTag("bird_observer_camera") then
        return true
    end

    local team_id, pending = team_state.get_player_team(owner)
    if pending or team_id == nil or team_state.is_playing_team(team_id) then
        return false
    end

    return team_id == team_state.TEAM_OBSERVER
end

local function apply_observer_nightvision(owner)
    local playervision = owner ~= nil and owner.components ~= nil and owner.components.playervision or nil
    if playervision == nil or playervision.PushForcedNightVision == nil then
        return
    end

    if owner._bird_observer_nightvision_enabled then
        return
    end

    playervision:PushForcedNightVision(
        OBSERVER_NIGHTVISION_SOURCE,
        OBSERVER_NIGHTVISION_PRIORITY,
        OBSERVER_NIGHTVISION_COLOURCUBES,
        true
    )
    owner._bird_observer_nightvision_enabled = true
end

local function clear_observer_nightvision(owner)
    local playervision = owner ~= nil and owner.components ~= nil and owner.components.playervision or nil
    if playervision == nil or playervision.PopForcedNightVision == nil then
        return
    end

    if not owner._bird_observer_nightvision_enabled then
        return
    end

    playervision:PopForcedNightVision(OBSERVER_NIGHTVISION_SOURCE)
    owner._bird_observer_nightvision_enabled = nil
end

local function apply_observer_camera()
    local camera = TheCamera
    if camera == nil then
        return
    end

    if camera._bird_observer_camera_saved == nil then
        camera._bird_observer_camera_saved = {
            mindist = camera.mindist,
            maxdist = camera.maxdist,
            extramaxdist = camera.extramaxdist,
            distancetarget = camera.distancetarget,
            fov = camera.fov,
            mindistpitch = camera.mindistpitch,
            maxdistpitch = camera.maxdistpitch,
        }

        if camera.SetDistance ~= nil then
            camera:SetDistance(math.max(camera.distancetarget or 0, OBSERVER_CAMERA_DEFAULT_DISTANCE))
        end
    end

    if camera.SetMinDistance ~= nil then
        camera:SetMinDistance(OBSERVER_CAMERA_MIN_DISTANCE)
    else
        camera.mindist = OBSERVER_CAMERA_MIN_DISTANCE
    end

    if camera.SetMaxDistance ~= nil then
        camera:SetMaxDistance(OBSERVER_CAMERA_MAX_DISTANCE)
    else
        camera.maxdist = OBSERVER_CAMERA_MAX_DISTANCE
    end

    if camera.SetExtraMaxDistance ~= nil then
        camera:SetExtraMaxDistance(0)
    else
        camera.extramaxdist = 0
    end

    if camera.SetPitchRange ~= nil then
        camera:SetPitchRange(OBSERVER_CAMERA_MIN_PITCH, OBSERVER_CAMERA_MAX_PITCH)
    else
        camera.mindistpitch = OBSERVER_CAMERA_MIN_PITCH
        camera.maxdistpitch = OBSERVER_CAMERA_MAX_PITCH
    end
end

local function restore_observer_camera()
    local camera = TheCamera
    local saved = camera ~= nil and camera._bird_observer_camera_saved or nil
    if saved == nil then
        return
    end

    if saved.mindist ~= nil then
        if camera.SetMinDistance ~= nil then
            camera:SetMinDistance(saved.mindist)
        else
            camera.mindist = saved.mindist
        end
    end

    if saved.maxdist ~= nil then
        if camera.SetMaxDistance ~= nil then
            camera:SetMaxDistance(saved.maxdist)
        else
            camera.maxdist = saved.maxdist
        end
    end

    if saved.extramaxdist ~= nil then
        if camera.SetExtraMaxDistance ~= nil then
            camera:SetExtraMaxDistance(saved.extramaxdist)
        else
            camera.extramaxdist = saved.extramaxdist
        end
    end

    if saved.mindistpitch ~= nil and saved.maxdistpitch ~= nil then
        if camera.SetPitchRange ~= nil then
            camera:SetPitchRange(saved.mindistpitch, saved.maxdistpitch)
        else
            camera.mindistpitch = saved.mindistpitch
            camera.maxdistpitch = saved.maxdistpitch
        end
    end

    if saved.fov ~= nil then
        if camera.SetFOV ~= nil then
            camera:SetFOV(saved.fov)
        else
            camera.fov = saved.fov
        end
    end

    if saved.distancetarget ~= nil then
        if camera.SetDistance ~= nil then
            camera:SetDistance(saved.distancetarget)
        else
            camera.distancetarget = saved.distancetarget
        end
    end

    camera._bird_observer_camera_saved = nil
end

local function sync_observer_client_enhancements(owner)
    owner = owner or ThePlayer
    if is_observer_owner(owner) then
        if observer_nightvision_enabled then
            apply_observer_nightvision(owner)
        else
            clear_observer_nightvision(owner)
        end
        if observer_large_view_enabled then
            apply_observer_camera()
        else
            restore_observer_camera()
        end
    else
        observer_large_view_enabled = false
        clear_observer_nightvision(owner)
        restore_observer_camera()
    end
end

local function set_observer_large_view_enabled(enabled)
    observer_large_view_enabled = enabled == true
    sync_observer_client_enhancements(ThePlayer)
    return observer_large_view_enabled and is_observer_owner(ThePlayer)
end

function GLOBAL.BirdObserverSetLargeView(enabled)
    return set_observer_large_view_enabled(enabled)
end

function GLOBAL.BirdObserverToggleLargeView()
    return set_observer_large_view_enabled(not observer_large_view_enabled)
end

function GLOBAL.BirdObserverIsLargeViewEnabled()
    return observer_large_view_enabled and is_observer_owner(ThePlayer)
end

local function set_observer_nightvision_enabled(enabled)
    observer_nightvision_enabled = enabled == true
    sync_observer_client_enhancements(ThePlayer)
    return observer_nightvision_enabled and is_observer_owner(ThePlayer)
end

function GLOBAL.BirdObserverSetNightVision(enabled)
    return set_observer_nightvision_enabled(enabled)
end

function GLOBAL.BirdObserverToggleNightVision()
    return set_observer_nightvision_enabled(not observer_nightvision_enabled)
end

function GLOBAL.BirdObserverIsNightVisionEnabled()
    return observer_nightvision_enabled and is_observer_owner(ThePlayer)
end

local function sync_hud_status_visibility(hud)
    if hud == nil or hud.controls == nil then
        return
    end

    local owner = hud.owner or ThePlayer
    local is_observer = is_observer_owner(owner)
    if hud.controls.status ~= nil then
        if is_observer then
            hud.controls.status:Hide()
        end
    end
    if hud.controls.inv ~= nil then
        if is_observer then
            hud.controls.inv:Hide()
        end
    end
end

local function is_observer_allowed_action(buffered_action)
    if buffered_action == nil or ACTIONS == nil then
        return false
    end

    local action = buffered_action.action
    return action == ACTIONS.WALKTO
        or action == ACTIONS.MIGRATE
end

AddComponentPostInit("locomotor", function(self)
    local PushAction = self.PushAction
    if PushAction == nil then
        return
    end

    function self:PushAction(action, ...)
        if is_observer_owner(self.inst)
            and not is_observer_allowed_action(action) then
            return false
        end
        return PushAction(self, action, ...)
    end
end)

AddPlayerPostInit(function(inst)
    local function delayed_sync()
        sync_visual_state(inst)
        if inst == ThePlayer then
            sync_observer_client_enhancements(inst)
        end
    end

    inst:ListenForEvent(player_state.EVENT_READY, delayed_sync)
    if TheGlobalInstance ~= nil then
        TheGlobalInstance:ListenForEvent("bird_lobby_teams_dirty", delayed_sync)
    end
    inst:DoTaskInTime(0, delayed_sync)
    inst:DoTaskInTime(0.5, delayed_sync)
    inst:DoTaskInTime(2, delayed_sync)
end)
local function disable_observer_status_display(status)
    if status == nil or not is_observer_owner(status.owner) then
        return
    end

    status:Hide()
end
AddClassPostConstruct("widgets/statusdisplays", function(self)
    disable_observer_status_display(self)
    self.inst:DoTaskInTime(0, function()
        disable_observer_status_display(self)
    end)
    self.inst:DoTaskInTime(0.1, function()
        disable_observer_status_display(self)
    end)
end)

AddClassPostConstruct("screens/playerhud", function(self)
    local OnUpdate = self.OnUpdate
    function self:OnUpdate(...)
        sync_hud_status_visibility(self)
        sync_observer_client_enhancements(self.owner or ThePlayer)
        if OnUpdate ~= nil then
            return OnUpdate(self, ...)
        end
    end

    self.inst:DoTaskInTime(0, function()
        sync_hud_status_visibility(self)
        sync_observer_client_enhancements(self.owner or ThePlayer)
    end)
    self.inst:DoPeriodicTask(0.5, function()
        sync_hud_status_visibility(self)
        sync_observer_client_enhancements(self.owner or ThePlayer)
    end)
end)
local function sync_observer_crafting_hud(hud)
    if hud == nil then
        return false
    end

    local owner = hud.owner or ThePlayer
    if is_observer_owner(owner) then
        hud.is_open = false
        if hud.craftingmenu ~= nil then
            hud.craftingmenu:Disable()
            hud.craftingmenu:Hide()
        end
        if hud.pinbar ~= nil then
            hud.pinbar:Hide()
        end
        if hud.openhint ~= nil then
            hud.openhint:Hide()
        end
        if hud.ui_root ~= nil then
            hud.ui_root:Hide()
        end
        hud:Hide()
        return true
    end

    return false
end

AddClassPostConstruct("widgets/redux/craftingmenu_hud", function(self)
    local Open = self.Open
    function self:Open(...)
        if sync_observer_crafting_hud(self) then
            return
        end
        return Open(self, ...)
    end

    local OnUpdate = self.OnUpdate
    function self:OnUpdate(...)
        if sync_observer_crafting_hud(self) then
            return
        end
        return OnUpdate(self, ...)
    end

    local NeedsToUpdate = self.NeedsToUpdate
    function self:NeedsToUpdate(...)
        if is_observer_owner(self.owner or ThePlayer) then
            return false
        end
        return NeedsToUpdate(self, ...)
    end

    local UpdateRecipes = self.UpdateRecipes
    function self:UpdateRecipes(...)
        if sync_observer_crafting_hud(self) then
            return
        end
        return UpdateRecipes(self, ...)
    end

    local RebuildRecipes = self.RebuildRecipes
    function self:RebuildRecipes(...)
        if sync_observer_crafting_hud(self) then
            return
        end
        return RebuildRecipes(self, ...)
    end

    local RefreshControllers = self.RefreshControllers
    function self:RefreshControllers(...)
        if sync_observer_crafting_hud(self) then
            return
        end
        return RefreshControllers(self, ...)
    end

    self.inst:DoTaskInTime(0, function()
        sync_observer_crafting_hud(self)
    end)
    self.inst:DoPeriodicTask(0.5, function()
        sync_observer_crafting_hud(self)
    end)
end)
