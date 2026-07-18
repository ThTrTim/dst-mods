-- Vanilla lobby PlayerList with a team filter bar.
local PlayerList = require("widgets/redux/playerlist")
local Widget = require("widgets/widget")
local TEMPLATES = require("widgets/redux/templates")

local lobby_team_state = require("src/team/lobby_team_state")

local TEAM_OBSERVER = lobby_team_state.TEAM_OBSERVER
local TEAM_RED = lobby_team_state.TEAM_RED
local TEAM_BLUE = lobby_team_state.TEAM_BLUE
local TEAM_WAITING = lobby_team_state.TEAM_WAITING

local FILTER_BUTTON_SIZE = { 60, 30 }
local FILTER_BUTTON_SPACING = 64
local FILTER_ROOT_X = -15
local FILTER_ROOT_Y = 40
local FILTERED_LIST_X = -40
local FILTERED_LIST_Y = -143

local FILTERS = {
    { team_id = TEAM_RED, label = "红队", colour = { 0.95, 0.30, 0.24, 1 } },
    { team_id = TEAM_BLUE, label = "蓝队", colour = { 0.32, 0.58, 1.00, 1 } },
    { team_id = TEAM_OBSERVER, label = "OB", colour = { 1, 1, 1, 1 } },
    { team_id = TEAM_WAITING, label = "等待", colour = { 0.92, 0.78, 0.30, 1 } },
}

local function CopyClientTable()
    local source = TheNet ~= nil and TheNet:GetClientTable() or nil
    local players = {}

    if source ~= nil then
        for _, client in ipairs(source) do
            if client.userid ~= nil and client.userid ~= "" then
                players[#players + 1] = client
            end
        end
    end

    if TheNet ~= nil and not TheNet:GetServerIsClientHosted() then
        for index = #players, 1, -1 do
            if players[index].performance ~= nil then
                table.remove(players, index)
            end
        end
    end

    return players
end

local function GetPlayerTeam(player)
    if player == nil or player.userid == nil then
        return TEAM_WAITING
    end

    local team_id = lobby_team_state.get(player.userid)
    return lobby_team_state.is_valid(team_id) and team_id or TEAM_WAITING
end

local function GetInitialFilter()
    local userid = TheNet ~= nil and TheNet:GetUserID() or nil
    if userid ~= nil and userid ~= "" then
        local team_id = lobby_team_state.get(userid)
        if lobby_team_state.is_valid(team_id) then
            return team_id
        end
    end

    return TEAM_WAITING
end

local function BuildFilteredPlayers(players, selected_team)
    local filtered = {}
    local counts = {
        [TEAM_OBSERVER] = 0,
        [TEAM_RED] = 0,
        [TEAM_BLUE] = 0,
        [TEAM_WAITING] = 0,
    }

    for _, player in ipairs(players) do
        local team_id = GetPlayerTeam(player)
        counts[team_id] = (counts[team_id] or 0) + 1
        if team_id == selected_team then
            filtered[#filtered + 1] = player
        end
    end

    return filtered, counts
end

local function SetTotalPlayerCount(self, count)
    if self.players_number == nil then
        return
    end

    local max_players = TheNet ~= nil and TheNet:GetServerMaxPlayers() or "?"
    self.players_number:SetString(subfmt(
        STRINGS.UI.LOBBYSCREEN.NUM_PLAYERS_FMT,
        { num = count, max = tostring(max_players or "?") }
    ))
end

local TeamPlayerList = Class(PlayerList, function(self, owner, next_widgets)
    self.bird_team_filter = GetInitialFilter()
    self.bird_next_widgets = next_widgets or {}

    PlayerList._ctor(self, owner, next_widgets)
    self.focus_forward = self.scroll_list
end)

local function RefreshFilterBar(self, counts)
    if self.bird_team_filter_buttons == nil then
        return
    end

    local selected_button = nil
    for _, filter in ipairs(FILTERS) do
        local button = self.bird_team_filter_buttons[filter.team_id]
        if button ~= nil then
            button:SetText(filter.label .. " " .. tostring(counts[filter.team_id] or 0))
            if button.text ~= nil then
                button.text:SetColour(unpack(filter.colour))
            end
            if self.bird_team_filter == filter.team_id then
                button:Select()
                selected_button = button
            else
                button:Unselect()
            end
        end
    end

    if self.scroll_list ~= nil and selected_button ~= nil then
        self.scroll_list:SetFocusChangeDir(MOVE_UP, selected_button)
    end
end

local function SelectFilter(self, team_id)
    if self.bird_team_filter == team_id then
        return
    end

    self.bird_team_filter = team_id
    self:Refresh()

    local button = self.bird_team_filter_buttons ~= nil
        and self.bird_team_filter_buttons[team_id]
        or nil
    if button ~= nil then
        button:SetFocus()
    end
end

local function EnsureFilterBar(self)
    if self.bird_team_filter_root ~= nil or self.player_list == nil then
        return
    end

    local root = self.player_list:AddChild(Widget("BirdLobbyTeamFilters"))
    root:SetPosition(FILTER_ROOT_X, FILTER_ROOT_Y)
    self.bird_team_filter_root = root
    self.bird_team_filter_buttons = {}

    local first_x = -FILTER_BUTTON_SPACING * (#FILTERS - 1) * 0.5
    local previous = nil
    for index, filter in ipairs(FILTERS) do
        local team_id = filter.team_id
        local button = root:AddChild(TEMPLATES.StandardButton(function()
            SelectFilter(self, team_id)
        end, filter.label, FILTER_BUTTON_SIZE))
        button:SetPosition(first_x + (index - 1) * FILTER_BUTTON_SPACING, 0)
        self.bird_team_filter_buttons[team_id] = button

        if previous ~= nil then
            button:SetFocusChangeDir(MOVE_LEFT, previous)
            previous:SetFocusChangeDir(MOVE_RIGHT, button)
        end
        previous = button
    end
end

local function ApplyFilterFocus(self)
    if self.scroll_list == nil or self.bird_team_filter_buttons == nil then
        return
    end

    for _, filter in ipairs(FILTERS) do
        local button = self.bird_team_filter_buttons[filter.team_id]
        if button ~= nil then
            button:SetFocusChangeDir(MOVE_DOWN, self.scroll_list)
        end
    end
end

function TeamPlayerList:GetPlayerTable()
    return CopyClientTable()
end

function TeamPlayerList:GetTeamForPlayer(player)
    return GetPlayerTeam(player)
end

function TeamPlayerList:BuildPlayerList(players, next_widgets)
    if next_widgets ~= nil then
        self.bird_next_widgets = next_widgets
    end

    local all_players = players or self:GetPlayerTable()
    local filtered, counts = BuildFilteredPlayers(all_players, self.bird_team_filter)

    PlayerList.BuildPlayerList(self, filtered, self.bird_next_widgets)
    if self.scroll_list ~= nil then
        self.scroll_list:SetPosition(FILTERED_LIST_X, FILTERED_LIST_Y)
    end

    EnsureFilterBar(self)
    RefreshFilterBar(self, counts)
    ApplyFilterFocus(self)
    SetTotalPlayerCount(self, #all_players)
end

function TeamPlayerList:Refresh(next_widgets)
    if type(next_widgets) == "table" then
        self.bird_next_widgets = next_widgets
    end

    local all_players = self:GetPlayerTable()
    local filtered, counts = BuildFilteredPlayers(all_players, self.bird_team_filter)

    if self.scroll_list ~= nil then
        self.scroll_list:SetItemsData(filtered)
        self.scroll_list:SetPosition(FILTERED_LIST_X, FILTERED_LIST_Y)
    end

    EnsureFilterBar(self)
    RefreshFilterBar(self, counts)
    ApplyFilterFocus(self)
    SetTotalPlayerCount(self, #all_players)
end

return TeamPlayerList
