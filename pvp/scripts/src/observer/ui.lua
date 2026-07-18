-- OB/referee HUD and OB map controls.
local Widget = require("widgets/widget")
local ImageButton = require("widgets/imagebutton")
local RefereePanel = require("widgets/birdui1")
local TeamStatusPanel = require("widgets/birdduiwu")
local observer_privileges = require("src/observer/privileges")
local team_state = require("src/team/lobby_team_state")
local player_state = require("src/team/player_state")

local function can_use_referee_panel(player)
    local fn = observer_privileges.can_use_referee_panel or observer_privileges.is_observer
    return fn ~= nil and fn(player) == true
end

local function get_or_create_root(self)
    if self.bird_root ~= nil then
        return self.bird_root
    end

    local anchor = self:AddChild(Widget("bird_root1"))
    anchor:SetScaleMode(SCALEMODE_PROPORTIONAL)
    anchor:SetHAnchor(ANCHOR_LEFT)
    anchor:SetVAnchor(ANCHOR_BOTTOM)
    anchor:SetMaxPropUpscale(MAX_HUD_SCALE)

    self.bird_root = anchor:AddChild(Widget("bird_root2"))
    return self.bird_root
end

local function set_widget_visible(widget, visible)
    if widget == nil then
        return
    end

    if visible then
        if widget.Show ~= nil then
            widget:Show()
        end
        if widget.Enable ~= nil then
            widget:Enable()
        end
    else
        if widget.DoHide ~= nil then
            widget:DoHide()
        elseif widget.Hide ~= nil then
            widget:Hide()
        end
        if widget.Disable ~= nil then
            widget:Disable()
        end
    end
end

local function set_observer_controls_visible(self, visible)
    set_widget_visible(self.caipanbutton, visible)
    set_widget_visible(self.birdduiwu_ui, visible)

    if not visible then
        set_widget_visible(self.caipanbutton_ui, false)
    end
end

local function add_observer_controls(self)
    if self.caipanbutton ~= nil then
        return
    end

    local root = get_or_create_root(self)
    self.caipanbutton_ui = root:AddChild(RefereePanel(self.owner))
    self.birdduiwu_ui = self:AddChild(TeamStatusPanel(self.owner))

    self.caipanbutton = root:AddChild(ImageButton(
        "images/loading_screen_icons.xml",
        "icon_tooltips.tex"
    ))
    self.caipanbutton:SetPosition(80, 60)
    self.caipanbutton:SetScale(0.4)
    self.caipanbutton:SetOnClick(function()
        if not can_use_referee_panel(self.owner) then
            set_observer_controls_visible(self, false)
            return
        end

        if not self.caipanbutton_ui.shown then
            self.caipanbutton_ui:NeedShow()
        else
            self.caipanbutton_ui:DoHide()
        end
    end)
end

local function refresh_observer_controls(self)
    local visible = can_use_referee_panel(self.owner)
    if visible then
        add_observer_controls(self)
    end
    set_observer_controls_visible(self, visible)
end

local function is_local_observer()
    if ThePlayer == nil then
        return false
    end

    local team_id, pending = team_state.get_player_team(ThePlayer)
    if pending or team_state.is_playing_team(team_id) then
        return false
    end
    if team_id == team_state.TEAM_OBSERVER then
        return true
    end

    return ThePlayer:HasTag("bird_observer_camera") or ThePlayer.bird_observer_camera == true
end

local function install_hud()
    AddClassPostConstruct("widgets/controls", function(self)
        local function refresh_controls()
            refresh_observer_controls(self)
        end

        refresh_controls()
        self.inst:DoTaskInTime(0, refresh_controls)
        self.inst:DoTaskInTime(0.5, refresh_controls)
        self.inst:DoTaskInTime(2, refresh_controls)
        self.inst:DoTaskInTime(5, refresh_controls)

        if self.owner ~= nil then
            self.owner:ListenForEvent(player_state.EVENT_READY, refresh_controls)
        end
        if TheGlobalInstance ~= nil then
            TheGlobalInstance:ListenForEvent("bird_lobby_teams_dirty", refresh_controls)
        end
    end)
end

local function install_map_teleport()
    AddClassPostConstruct("screens/mapscreen", function(self)
        local OnControl = self.OnControl

        function self:OnControl(control, down)
            if control == CONTROL_SECONDARY
                and down
                and is_local_observer()
                and (self._bird_last_ob_teleport_time == nil or GetTime() - self._bird_last_ob_teleport_time > 0.2) then
                self._bird_last_ob_teleport_time = GetTime()
                local screen = TheFrontEnd:GetActiveScreen()
                if screen ~= nil and screen.minimap ~= nil then
                    local screen_pos = TheInput:GetScreenPosition()
                    local widget_pos = screen:ScreenPosToWidgetPos(screen_pos)
                    local map_pos = screen:WidgetPosToMapPos(widget_pos)
                    local x, z = screen.minimap:MapPosToWorldPos(map_pos:Get())
                    SendModRPCToServer(
                        MOD_RPC.bird_mode_rpc.bird_mode_rpc,
                        "chuansong",
                        x,
                        z
                    )
                end
            end

            return OnControl(self, control, down)
        end
    end)
end

install_hud()
install_map_teleport()
