-- Lobby team UI: grouped player roster, waiting layout, manual selection, and admin auto-team button.
-- Team assignment output remains the lobby team registry consumed by src/team/component.lua.
local Widget = require("widgets/widget")
local Image = require("widgets/image")
local ImageButton = require("widgets/imagebutton")
local Text = require("widgets/text")
local TEMPLATES = require("widgets/redux/templates")
local PopupDialogScreen = require("screens/redux/popupdialog")
local UserCommands = require("usercommands")
local TeamPlayerList = require("widgets/bird_team_playerlist")
local InstallTeamWaitingLayout = require("widgets/bird_team_waitingforplayers")
local lobby_team_state = require("src/team/lobby_team_state")
local admin_privileges = require("src/admin/privileges")

local TEAM_OBSERVER = 0
local TEAM_RED = 1
local TEAM_BLUE = 2
local TEAM_WAITING = 3
local ROLL_COMMAND_NAME = "bird_lobby_roll"
local ROLL_COOLDOWN_FALLBACK = 3
local BUTTON_SIZE = { 120, 46 }
local BUTTON_TEXT_SIZE = { 100, 30 }
local TEAM_SELECT_POSITION = { -475, 320 }
local AUTO_TEAM_POSITION = { -150, 320 }
local ROLL_BUTTON_POSITION = { 0, 320 }
local LOCK_BUTTON_POSITION = { 150, 320 }
local AUTO_ASSIGN_WAITING = "waiting"
local AUTO_ASSIGN_ALL = "all"

local TEAM_LABELS = {
    [TEAM_OBSERVER] = "OB",
    [TEAM_RED] = "红队",
    [TEAM_BLUE] = "蓝队",
    [TEAM_WAITING] = "等待",
}

local function IsRegularLobby()
    return TheNet ~= nil and TheNet:GetServerGameMode() == "survival"
end

local function GetLocalClient()
    local userid = TheNet ~= nil and TheNet:GetUserID() or nil
    return userid ~= nil and TheNet:GetClientTableForUser(userid) or nil
end

local function GetLocalCaller()
    local userid = TheNet ~= nil and TheNet:GetUserID() or nil
    return userid ~= nil and userid ~= "" and TheNet:GetClientTableForUser(userid) or nil
end

local function GetRollDisplayName(caller)
    local name = tostring(caller ~= nil and (caller.name or caller.userid) or "未知玩家")
    if ChatHistory ~= nil and ChatHistory.GetDisplayName ~= nil then
        local ok, display_name = pcall(ChatHistory.GetDisplayName, ChatHistory, name, caller ~= nil and caller.prefab or nil)
        if ok and display_name ~= nil then
            return display_name
        end
    end

    return name
end

local function GetRollCooldown()
    return TUNING ~= nil and TUNING.DICE_ROLL_COOLDOWN or ROLL_COOLDOWN_FALLBACK
end

local function CanRollNow(caller)
    if admin_privileges.is_lobby_admin(caller) then
        return true
    end

    local net = TheWorld ~= nil and TheWorld.net or nil
    if net == nil then
        return true
    end

    local userid = caller ~= nil and caller.userid or nil
    if userid == nil or userid == "" then
        return false
    end

    local now = GetTime ~= nil and GetTime() or 0
    net._bird_lobby_roll_cooldowns = net._bird_lobby_roll_cooldowns or {}
    local next_roll_time = net._bird_lobby_roll_cooldowns[userid] or 0
    if now <= next_roll_time then
        return false
    end

    net._bird_lobby_roll_cooldowns[userid] = now + GetRollCooldown()
    return true
end

local function RollLobbyDice(params, caller)
    if caller == nil or caller.userid == nil or caller.userid == "" then
        return
    end
    if not CanRollNow(caller) then
        return
    end

    local max = 100
    local value = math.random(max)
    local fmt = STRINGS ~= nil
        and STRINGS.UI ~= nil
        and STRINGS.UI.NOTIFICATION ~= nil
        and STRINGS.UI.NOTIFICATION.DICEROLLED
        or "%s rolls %s (1-%i)"

    if TheNet ~= nil then
        TheNet:Announce(string.format(fmt, GetRollDisplayName(caller), tostring(value), max), caller.colour or { 1, 1, 1, 1 })
    end
end

AddUserCommand(ROLL_COMMAND_NAME, {
    permission = COMMAND_PERMISSION.USER,
    slash = false,
    usermenu = false,
    servermenu = false,
    params = {},
    vote = false,
    serverfn = RollLobbyDice,
})

function GLOBAL.BirdRollLobbyDice()
    local caller = GetLocalCaller()
    if caller == nil or caller.userid == nil or caller.userid == "" then
        return false
    end

    UserCommands.RunUserCommand(ROLL_COMMAND_NAME, {}, caller, nil)
    return true
end

local function GetLocalTeam()
    local client = GetLocalClient()
    local userid = client ~= nil and client.userid or nil
    local team = userid ~= nil and lobby_team_state.get(userid) or nil
    if team ~= TEAM_OBSERVER and team ~= TEAM_RED and team ~= TEAM_BLUE then
        return TEAM_WAITING
    end
    return team
end

local function CanAutoAssignTeams()
    local client = GetLocalClient()
    if client == nil then
        return false
    end

    if admin_privileges.is_lobby_admin(client) or (TheNet ~= nil and TheNet:GetIsServer()) then
        return true
    end

    return UserCommands.CanUserAccessCommand("bird_auto_lobby_team", client, nil)
        and UserCommands.CanUserStartCommand("bird_auto_lobby_team", client, nil)
end

local function CanOverrideTeamLock(client)
    return admin_privileges.is_lobby_admin(client)
        or (TheNet ~= nil and TheNet:GetIsServer())
end

local function CanManageTeamLock()
    return CanOverrideTeamLock(GetLocalClient())
end

local function IsLocalTeamLockedForEdit()
    local client = GetLocalClient()
    return lobby_team_state.is_global_locked()
        and not CanOverrideTeamLock(client)
end

local function RefreshPlayerList(screen)
    if screen.playerList ~= nil and screen.playerList.Refresh ~= nil then
        screen.playerList:Refresh(true)
    end
end

local function PositionLobbyButton(button, position)
    button:SetPosition(position[1], position[2])
end

local function CloseTeamSelectDialog(screen)
    if screen.bird_team_select_dialog ~= nil then
        screen.bird_team_select_dialog:Kill()
        screen.bird_team_select_dialog = nil
    end
end

local function OpenTeamSelectDialog(screen, select_team)
    CloseTeamSelectDialog(screen)

    local dialog = screen:AddChild(Widget("bird_team_select_dialog"))
    screen.bird_team_select_dialog = dialog

    local blocker = dialog:AddChild(ImageButton("images/global.xml", "square.tex"))
    blocker.image:SetVRegPoint(ANCHOR_MIDDLE)
    blocker.image:SetHRegPoint(ANCHOR_MIDDLE)
    blocker.image:SetVAnchor(ANCHOR_MIDDLE)
    blocker.image:SetHAnchor(ANCHOR_MIDDLE)
    blocker.image:SetScaleMode(SCALEMODE_FILLSCREEN)
    blocker.image:SetTint(0, 0, 0, 0.3)
    blocker:SetOnClick(function()
        CloseTeamSelectDialog(screen)
    end)

    local root = dialog:AddChild(Widget("bird_team_select_dialog_root"))
    root:SetScaleMode(SCALEMODE_PROPORTIONAL)
    root:SetHAnchor(ANCHOR_MIDDLE)
    root:SetVAnchor(ANCHOR_MIDDLE)
    root:SetPosition(0, 0)

    local backdrop = root:AddChild(Image("images/scoreboard.xml", "scoreboard_frame.tex"))
    backdrop:SetScale(0.62, 0.78)

    local title = root:AddChild(Text(HEADERFONT, 36, "选择队伍"))
    title:SetPosition(0, 150)
    title:SetColour(1, 1, 1, 1)

    local choices = {
        { "等待", TEAM_WAITING },
        { "OB", TEAM_OBSERVER },
        { "红队", TEAM_RED },
        { "蓝队", TEAM_BLUE },
    }

    local function AddChoiceButton(label, team_id, y)
        local button = root:AddChild(TEMPLATES.StandardButton(function()
            select_team(team_id)
            CloseTeamSelectDialog(screen)
        end, label, { 240, 46 }))
        button:SetPosition(0, y)
        if button.text ~= nil then
            button.text:SetRegionSize(220, 40)
        end
    end

    for i, choice in ipairs(choices) do
        AddChoiceButton(choice[1], choice[2], 100 - (i - 1) * 52)
    end

    local cancel = root:AddChild(TEMPLATES.StandardButton(function()
        CloseTeamSelectDialog(screen)
    end, STRINGS.UI.LOBBYSCREEN.CANCEL or "取消", { 240, 46 }))
    cancel:SetPosition(0, -126)
    if cancel.text ~= nil then
        cancel.text:SetRegionSize(220, 40)
    end
end

local function ResetLocalTeamToWaiting(screen)
    if screen.bird_team_enter_waiting_submitted then
        return
    end

    screen.bird_team_enter_waiting_submitted = true
    if BirdSubmitLobbyTeam ~= nil and BirdSubmitLobbyTeam(TEAM_WAITING) then
        RefreshPlayerList(screen)
    end
end

local function GetPlayerListHost(screen)
    -- Some DST branches wrap the sidebar in chat_sidebar; the vanilla file
    -- supplied by the user stores playerList directly on LobbyScreen.
    if screen.chat_sidebar ~= nil then
        return screen.chat_sidebar, screen.chat_sidebar
    end
    return screen.sidebar_root, screen
end

local function ReplaceLobbyPlayerList(screen)
    local parent, holder = GetPlayerListHost(screen)
    if parent == nil or holder == nil or holder.bird_team_player_list_installed then
        return
    end

    holder.bird_team_player_list_installed = true

    local old_list = holder.playerList or screen.playerList
    if old_list ~= nil then
        old_list:Kill()
    end

    local chatbox = holder.chatbox or screen.chatbox
    local right_widget = screen.character_scroll_list
    local team_list = parent:AddChild(TeamPlayerList(screen, {
        right = right_widget,
        down = chatbox,
    }))

    holder.playerList = team_list
    screen.playerList = team_list

    -- Do not resize, reposition, wrap or replace LobbyChatQueue. Keeping the
    -- official chatbox/chatqueue hierarchy avoids clipping and offset bugs.
    if screen.DoFocusHookups ~= nil then
        screen:DoFocusHookups()
    elseif holder.DoFocusHookups ~= nil then
        holder:DoFocusHookups()
    end
end

local function AddTeamSelectButton(screen)
    if screen.bird_team_select_button ~= nil then
        return
    end

    local button
    local function Refresh()
        if button ~= nil then
            local locked = IsLocalTeamLockedForEdit()
            button:SetText((locked and "队伍已锁定：" or "队伍：") .. TEAM_LABELS[GetLocalTeam()])
            button:Show()
            if locked then
                button:Disable()
            else
                button:Enable()
            end
        end
    end

    local function SelectTeam(team_id)
        if IsLocalTeamLockedForEdit() then
            Refresh()
            return
        end
        if BirdSubmitLobbyTeam ~= nil and BirdSubmitLobbyTeam(team_id) then
            RefreshPlayerList(screen)
        end
    end

    local parent = screen.root or screen
    button = parent:AddChild(TEMPLATES.StandardButton(function()
        if IsLocalTeamLockedForEdit() then
            Refresh()
            return
        end
        OpenTeamSelectDialog(screen, SelectTeam)
    end, "队伍：等待", BUTTON_SIZE))
    button:SetScale(1)
    PositionLobbyButton(button, TEAM_SELECT_POSITION)
    if button.text ~= nil then
        button.text:SetRegionSize(BUTTON_TEXT_SIZE[1], BUTTON_TEXT_SIZE[2])
    end

    screen.bird_team_select_button = button
    screen.bird_team_select_refresh = Refresh
    Refresh()
end

local function AddAutoTeamButton(screen)
    if screen.bird_auto_team_button ~= nil then
        return
    end

    local button
    local function Refresh()
        if button == nil then
            return
        end

        if CanAutoAssignTeams() then
            button:Show()
            button:Enable()
        else
            button:Hide()
            button:Disable()
        end
    end

    local function SubmitAutoAssignTeams(mode)
        if not CanAutoAssignTeams() then
            Refresh()
            return
        end

        if BirdAutoAssignLobbyTeams ~= nil and BirdAutoAssignLobbyTeams(mode) then
            RefreshPlayerList(screen)
        end
    end

    local function OpenAutoAssignDialog()
        TheFrontEnd:PushScreen(PopupDialogScreen("自动分队", "", {
            { text = "等待人员分队", cb = function() SubmitAutoAssignTeams(AUTO_ASSIGN_WAITING) TheFrontEnd:PopScreen() end },
            { text = "全部人员分队", cb = function() SubmitAutoAssignTeams(AUTO_ASSIGN_ALL) TheFrontEnd:PopScreen() end },
            { text = STRINGS.UI.LOBBYSCREEN.CANCEL or "取消", cb = function() TheFrontEnd:PopScreen() end },
        }))
    end

    local parent = screen.root or screen
    button = parent:AddChild(TEMPLATES.StandardButton(OpenAutoAssignDialog, "自动分队", BUTTON_SIZE))
    button:SetScale(1)
    PositionLobbyButton(button, AUTO_TEAM_POSITION)
    if button.text ~= nil then
        button.text:SetRegionSize(BUTTON_TEXT_SIZE[1], BUTTON_TEXT_SIZE[2])
    end

    screen.bird_auto_team_button = button
    screen.inst:DoPeriodicTask(0.25, Refresh)

    Refresh()
end

local function AddRollDiceButton(screen)
    if screen.bird_lobby_roll_button ~= nil then
        return
    end

    local parent = screen.root or screen
    local button = parent:AddChild(TEMPLATES.StandardButton(function()
        if BirdRollLobbyDice ~= nil then
            BirdRollLobbyDice()
        end
    end, "Roll 骰子", BUTTON_SIZE))
    button:SetScale(1)
    PositionLobbyButton(button, ROLL_BUTTON_POSITION)
    if button.text ~= nil then
        button.text:SetRegionSize(BUTTON_TEXT_SIZE[1], BUTTON_TEXT_SIZE[2])
    end

    screen.bird_lobby_roll_button = button
end

local function AddTeamLockButton(screen)
    if screen.bird_team_lock_button ~= nil then
        return
    end

    local button
    local function Refresh()
        if button == nil then
            return
        end

        if CanManageTeamLock() then
            button:SetText(lobby_team_state.is_global_locked() and "解锁队伍" or "锁定队伍")
            button:Show()
            button:Enable()
        else
            button:Hide()
            button:Disable()
        end
    end

    local parent = screen.root or screen
    button = parent:AddChild(TEMPLATES.StandardButton(function()
        if not CanManageTeamLock() then
            Refresh()
            return
        end

        if BirdSetLobbyTeamGlobalLock ~= nil and BirdSetLobbyTeamGlobalLock(not lobby_team_state.is_global_locked()) then
            RefreshPlayerList(screen)
        end
        Refresh()
    end, "锁定队伍", BUTTON_SIZE))
    button:SetScale(1)
    PositionLobbyButton(button, LOCK_BUTTON_POSITION)
    if button.text ~= nil then
        button.text:SetRegionSize(BUTTON_TEXT_SIZE[1], BUTTON_TEXT_SIZE[2])
    end

    screen.bird_team_lock_button = button
    screen.bird_team_lock_refresh = Refresh
    screen.inst:DoPeriodicTask(0.25, Refresh)
    Refresh()
end

local function AddTeamRefreshHooks(screen)
    if screen.bird_team_refresh_hooks_installed then
        return
    end
    screen.bird_team_refresh_hooks_installed = true

    screen.inst:ListenForEvent("bird_lobby_teams_dirty", function()
        RefreshPlayerList(screen)
        if screen.bird_team_select_refresh ~= nil then
            screen.bird_team_select_refresh()
        end
        if screen.bird_auto_team_button ~= nil then
            if CanAutoAssignTeams() then
                screen.bird_auto_team_button:Show()
                screen.bird_auto_team_button:Enable()
            else
                screen.bird_auto_team_button:Hide()
                screen.bird_auto_team_button:Disable()
            end
        end
        if screen.bird_team_lock_refresh ~= nil then
            screen.bird_team_lock_refresh()
        end
    end, TheGlobalInstance)
end

AddClassPostConstruct("widgets/waitingforplayers", function(self)
    if IsRegularLobby() then
        InstallTeamWaitingLayout(self)
    end
end)

AddClassPostConstruct("screens/redux/lobbyscreen", function(self)
    if not IsRegularLobby() then
        return
    end

    ReplaceLobbyPlayerList(self)
    ResetLocalTeamToWaiting(self)
    AddTeamSelectButton(self)
    AddAutoTeamButton(self)
    AddRollDiceButton(self)
    AddTeamLockButton(self)
    AddTeamRefreshHooks(self)
end)
