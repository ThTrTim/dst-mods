-- Original scoreboard with a team filter bar.
local Widget = require("widgets/widget")
local TEMPLATES = require("widgets/redux/templates")

local team_state = require("src/team/lobby_team_state")

local TEAM_OBSERVER = team_state.TEAM_OBSERVER
local TEAM_RED = team_state.TEAM_RED
local TEAM_BLUE = team_state.TEAM_BLUE
local TEAM_WAITING = team_state.TEAM_WAITING

local FILTER_BUTTON_SIZE = { 112, 36 }
local FILTER_BUTTON_Y = 260
local FILTER_BUTTON_SPACING = 118
local ORIGINAL_LIST_X = 210
local FILTERED_LIST_Y = -35
local FILTER_CHECK_INTERVAL = 0.2

local FILTERS = {
    { team_id = TEAM_RED, label = "红队", colour = { 0.95, 0.30, 0.24, 1 } },
    { team_id = TEAM_BLUE, label = "蓝队", colour = { 0.32, 0.58, 1.00, 1 } },
    { team_id = TEAM_OBSERVER, label = "OB", colour = { 1, 1, 1, 1 } },
    { team_id = TEAM_WAITING, label = "等待", colour = { 0.92, 0.78, 0.30, 1 } },
}

local function FindPlayerByUserId(userid)
    if userid == nil or AllPlayers == nil then
        return nil
    end

    for _, player in ipairs(AllPlayers) do
        if player.userid == userid then
            return player
        end
    end
end

local function IsDedicatedServerRow(client)
    return client ~= nil
        and client.performance ~= nil
        and TheNet ~= nil
        and not TheNet:GetServerIsClientHosted()
end

local function ResolveClientTeam(client)
    if client == nil or client.userid == nil then
        return TEAM_WAITING
    end

    local player = FindPlayerByUserId(client.userid)
    if player ~= nil then
        local team_id, pending = team_state.get_player_team(player)
        if not pending and team_state.is_valid(team_id) then
            return team_id
        end
    end

    local world_team, world_ready = team_state.get_world_team(client.userid)
    if world_ready and team_state.is_valid(world_team) then
        return world_team
    end

    if team_state.is_remote_ready() then
        return team_state.get(client.userid)
    end

    return TEAM_WAITING
end

local function GetClientTable()
    return TheNet ~= nil and TheNet:GetClientTable() or {}
end

local function BuildFilteredClients(clients, selected_team)
    local filtered = {}
    local counts = {
        [TEAM_OBSERVER] = 0,
        [TEAM_RED] = 0,
        [TEAM_BLUE] = 0,
        [TEAM_WAITING] = 0,
    }
    local signature = { tostring(selected_team) }

    for _, client in ipairs(clients) do
        if IsDedicatedServerRow(client) then
            filtered[#filtered + 1] = client
            signature[#signature + 1] = "server"
        else
            local team_id = ResolveClientTeam(client)
            counts[team_id] = (counts[team_id] or 0) + 1
            signature[#signature + 1] = tostring(client.userid or "") .. "=" .. tostring(team_id)
            if team_id == selected_team then
                filtered[#filtered + 1] = client
            end
        end
    end

    return filtered, counts, table.concat(signature, ";")
end

local function GetInitialTeam(screen)
    local owner = screen ~= nil and screen.owner or ThePlayer
    if owner ~= nil then
        local team_id, pending = team_state.get_player_team(owner)
        if not pending and team_state.is_valid(team_id) then
            return team_id
        end

        if owner.userid ~= nil and team_state.is_remote_ready() then
            team_id = team_state.get(owner.userid)
            if team_state.is_valid(team_id) then
                return team_id
            end
        end
    end

    return TEAM_RED
end

local function SetOriginalListPosition(screen)
    if screen.list_root ~= nil then
        screen.list_root:SetPosition(ORIGINAL_LIST_X, FILTERED_LIST_Y)
        screen.list_root:Show()
    end
    if screen.row_root ~= nil then
        screen.row_root:SetPosition(ORIGINAL_LIST_X, FILTERED_LIST_Y)
        screen.row_root:Show()
    end
    if screen.bgs ~= nil then
        for _, bg in ipairs(screen.bgs) do
            bg:Show()
        end
    end
end

local function RefreshFilterBar(screen, counts)
    if screen.bird_team_filter_buttons == nil then
        return
    end

    local selected_button = nil
    for _, filter in ipairs(FILTERS) do
        local button = screen.bird_team_filter_buttons[filter.team_id]
        if button ~= nil then
            button:SetText(filter.label .. " " .. tostring(counts[filter.team_id] or 0))
            if button.text ~= nil then
                button.text:SetColour(unpack(filter.colour))
            end
            if screen.bird_team_filter == filter.team_id then
                button:Select()
                selected_button = button
            else
                button:Unselect()
            end
        end
    end

    if screen.scroll_list ~= nil and selected_button ~= nil then
        screen.scroll_list:SetFocusChangeDir(MOVE_UP, selected_button)
    end
end

local function SelectFilter(screen, team_id)
    if screen.bird_team_filter == team_id then
        return
    end

    screen.bird_team_filter = team_id
    screen:DoInit(GetClientTable())

    local button = screen.bird_team_filter_buttons ~= nil
        and screen.bird_team_filter_buttons[team_id]
        or nil
    if button ~= nil then
        button:SetFocus()
    end
end

local function EnsureFilterBar(screen)
    if screen.bird_team_filter_root ~= nil or screen.root == nil then
        return
    end

    local root = screen.root:AddChild(Widget("BirdTeamScoreboardFilters"))
    root:SetPosition(0, FILTER_BUTTON_Y)
    screen.bird_team_filter_root = root
    screen.bird_team_filter_buttons = {}

    local first_x = -FILTER_BUTTON_SPACING * (#FILTERS - 1) * 0.5
    local previous = nil
    for index, filter in ipairs(FILTERS) do
        local team_id = filter.team_id
        local button = root:AddChild(TEMPLATES.StandardButton(function()
            SelectFilter(screen, team_id)
        end, filter.label, FILTER_BUTTON_SIZE))
        button:SetPosition(first_x + (index - 1) * FILTER_BUTTON_SPACING, 0)
        screen.bird_team_filter_buttons[team_id] = button

        if previous ~= nil then
            button:SetFocusChangeDir(MOVE_LEFT, previous)
            previous:SetFocusChangeDir(MOVE_RIGHT, button)
        end
        previous = button
    end
end

AddClassPostConstruct("screens/playerstatusscreen", function(screen)
    screen.bird_team_filter = GetInitialTeam(screen)

    local OldDoInit = screen.DoInit
    function screen:DoInit(_)
        local clients = GetClientTable()
        local filtered, counts, signature = BuildFilteredClients(clients, self.bird_team_filter)

        OldDoInit(self, filtered)
        SetOriginalListPosition(self)
        EnsureFilterBar(self)
        RefreshFilterBar(self, counts)

        self.bird_team_filter_signature = signature
        self.bird_team_filter_revision = team_state.get_revision()
        self.bird_team_filter_check_time = FILTER_CHECK_INTERVAL

        if self.scroll_list ~= nil and self.bird_team_filter_buttons ~= nil then
            for _, filter in ipairs(FILTERS) do
                local button = self.bird_team_filter_buttons[filter.team_id]
                if button ~= nil then
                    button:SetFocusChangeDir(MOVE_DOWN, self.scroll_list)
                end
            end
        end
    end

    local OldOnUpdate = screen.OnUpdate
    function screen:OnUpdate(dt)
        OldOnUpdate(self, dt)

        self.bird_team_filter_check_time = (self.bird_team_filter_check_time or 0) - dt
        if self.bird_team_filter_check_time <= 0 then
            self.bird_team_filter_check_time = FILTER_CHECK_INTERVAL
            local clients = GetClientTable()
            local _, _, signature = BuildFilteredClients(clients, self.bird_team_filter)
            local revision = team_state.get_revision()
            if signature ~= self.bird_team_filter_signature
                or revision ~= self.bird_team_filter_revision then
                self:DoInit(clients)
            end
        end
    end
end)
