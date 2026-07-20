-- [PATCH] 新增：客户端输出/承伤统计面板。
-- 按 P 键打开，只显示当前对局的个人输出、承伤与叫醒次数。

local Screen = require "widgets/screen"
local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Text = require "widgets/text"
local TextButton = require "widgets/textbutton"
local TEMPLATES = require "widgets/redux/templates"

local PANEL_WIDTH = 620
local PANEL_HEIGHT = 360

local function FormatNumber(n)
    n = tonumber(n) or 0
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return string.format("%.0f", n)
end

local function SanitizeName(name)
    if name == nil then
        return nil
    end
    name = tostring(name)
    name = string.gsub(name, "[%c]", "")
    name = string.gsub(name, "^%s*(.-)%s*$", "%1")
    if name == "" then
        return nil
    end
    return name
end

local DamageStatsScreen = Class(Screen, function(self, owner)
    Screen._ctor(self, "DamageStatsScreen")
    self.owner = owner
    self.stats = nil
    self.is_fetching = false

    self:DoInit()
    self:FetchStats()
end)

function DamageStatsScreen:DoInit()
    local screen_w, screen_h = TheSim:GetScreenSize()
    if screen_w == nil or screen_w <= 0 then
        screen_w = 1920
    end
    if screen_h == nil or screen_h <= 0 then
        screen_h = 1080
    end

    self.root = self:AddChild(Widget("ROOT"))
    -- Center the panel on screen.
    self.root:SetPosition((screen_w - PANEL_WIDTH) / 2, (screen_h - PANEL_HEIGHT) / 2, 0)

    self.bg = self.root:AddChild(TEMPLATES.RectangleWindow(PANEL_WIDTH, PANEL_HEIGHT))
    self.bg:SetPosition(PANEL_WIDTH / 2, PANEL_HEIGHT / 2, 0)

    self.title = self.root:AddChild(Text(HEADERFONT, 34, "输出 / 承伤统计", UICOLOURS.GOLD))
    self.title:SetPosition(PANEL_WIDTH / 2, PANEL_HEIGHT - 35)

    -- Team totals header.
    self.header = self.root:AddChild(Widget("Header"))
    self.header:SetPosition(0, PANEL_HEIGHT - 120)

    self.red_team_label = self.header:AddChild(Text(CHATFONT_OUTLINE, 24, "红队", { 0.95, 0.30, 0.24, 1 }))
    self.red_team_label:SetPosition(110, 0)

    self.blue_team_label = self.header:AddChild(Text(CHATFONT_OUTLINE, 24, "蓝队", { 0.32, 0.58, 1.00, 1 }))
    self.blue_team_label:SetPosition(PANEL_WIDTH - 110, 0)

    self.red_dealt = self.header:AddChild(Text(CHATFONT, 20, "输出: -", { 0.95, 0.30, 0.24, 1 }))
    self.red_dealt:SetPosition(110, -28)

    self.blue_dealt = self.header:AddChild(Text(CHATFONT, 20, "输出: -", { 0.32, 0.58, 1.00, 1 }))
    self.blue_dealt:SetPosition(PANEL_WIDTH - 110, -28)

    self.red_taken = self.header:AddChild(Text(CHATFONT, 20, "承伤: -", { 0.95, 0.30, 0.24, 1 }))
    self.red_taken:SetPosition(110, -52)

    self.blue_taken = self.header:AddChild(Text(CHATFONT, 20, "承伤: -", { 0.32, 0.58, 1.00, 1 }))
    self.blue_taken:SetPosition(PANEL_WIDTH - 110, -52)

    -- Single player row (panel is per-player).
    self.player_row = self.root:AddChild(Widget("PlayerRow"))
    self.player_row:SetPosition(PANEL_WIDTH / 2, PANEL_HEIGHT - 210)

    self.no_data_label = self.root:AddChild(Text(CHATFONT, 22, "正在从服务器获取数据...", UICOLOURS.GOLD))
    self.no_data_label:SetPosition(PANEL_WIDTH / 2, PANEL_HEIGHT / 2)

    self.player_row:Hide()
end

function DamageStatsScreen:Close()
    TheFrontEnd:PopScreen(self)
end

function DamageStatsScreen:OnControl(control, down)
    if Screen.OnControl(self, control, down) then
        return true
    end
    if not down and (control == CONTROL_PAUSE or control == CONTROL_CANCEL) then
        self:Close()
        return true
    end
    return false
end

function DamageStatsScreen:FetchStats()
    if self.is_fetching then
        return
    end
    self.is_fetching = true
    if self.no_data_label ~= nil then
        self.no_data_label:SetString("正在从服务器获取数据...")
        self.no_data_label:Show()
    end
    if self.player_row ~= nil then
        self.player_row:Hide()
    end
    SendModRPCToServer(GetModRPC("bird_pvp_stats", "request"))
end

function DamageStatsScreen:OnStatsReceived(payload)
    self.is_fetching = false
    local ok, data = pcall(json.decode, payload)
    if not ok or type(data) ~= "table" then
        if self.no_data_label ~= nil then
            self.no_data_label:SetString("数据解析失败")
        end
        return
    end
    self.stats = data
    self:Refresh()
end

function DamageStatsScreen:Refresh()
    if self.stats == nil then
        return
    end

    local source = self.stats.round
    if source == nil then
        if self.no_data_label ~= nil then
            self.no_data_label:SetString("暂无数据")
            self.no_data_label:Show()
        end
        if self.player_row ~= nil then
            self.player_row:Hide()
        end
        return
    end

    local teams = source.teams or {}
    local red = teams.red or { dealt = 0, taken = 0 }
    local blue = teams.blue or { dealt = 0, taken = 0 }

    self.red_dealt:SetString("输出: " .. FormatNumber(red.dealt))
    self.blue_dealt:SetString("输出: " .. FormatNumber(blue.dealt))
    self.red_taken:SetString("承伤: " .. FormatNumber(red.taken))
    self.blue_taken:SetString("承伤: " .. FormatNumber(blue.taken))

    -- Extract the single player entry the server sent for us.
    local players = source.players or {}
    local row = nil
    for _, pdata in pairs(players) do
        row = pdata
        break
    end

    if row == nil then
        if self.no_data_label ~= nil then
            self.no_data_label:SetString("暂无玩家数据")
            self.no_data_label:Show()
        end
        if self.player_row ~= nil then
            self.player_row:Hide()
        end
        return
    end

    if self.no_data_label ~= nil then
        self.no_data_label:Hide()
    end

    self.player_row:KillAllChildren()
    self.player_row:Show()

    local name = SanitizeName(row.name) or "未知玩家"

    local row_w = PANEL_WIDTH - 80
    local name_text = self.player_row:AddChild(Text(CHATFONT, 22, name, UICOLOURS.WHITE))
    name_text:SetHAlign(ANCHOR_LEFT)
    name_text:SetRegionSize(row_w * 0.45, 28)
    name_text:SetPosition(-row_w * 0.26, 0)

    local dealt_text = self.player_row:AddChild(Text(CHATFONT, 20, "输出 " .. FormatNumber(row.dealt), UICOLOURS.WHITE))
    dealt_text:SetHAlign(ANCHOR_RIGHT)
    dealt_text:SetRegionSize(row_w * 0.18, 28)
    dealt_text:SetPosition(row_w * 0.08, 0)

    local taken_text = self.player_row:AddChild(Text(CHATFONT, 20, "承伤 " .. FormatNumber(row.taken), UICOLOURS.WHITE))
    taken_text:SetHAlign(ANCHOR_RIGHT)
    taken_text:SetRegionSize(row_w * 0.18, 28)
    taken_text:SetPosition(row_w * 0.27, 0)

    local wakes_text = self.player_row:AddChild(Text(CHATFONT, 20, "叫醒 " .. FormatNumber(row.wakes), UICOLOURS.WHITE))
    wakes_text:SetHAlign(ANCHOR_RIGHT)
    wakes_text:SetRegionSize(row_w * 0.18, 28)
    wakes_text:SetPosition(row_w * 0.46, 0)
end

-- Shared state and core function for opening the panel.
local _active_screen = nil

local function OpenDamageStatsPanel()
    if TheFrontEnd == nil or ThePlayer == nil then
        return
    end
    if _active_screen ~= nil then
        _active_screen:Close()
        _active_screen = nil
        return
    end
    _active_screen = DamageStatsScreen(ThePlayer)
    TheFrontEnd:PushScreen(_active_screen)
end

-- RPC response handler registration (client only).
if TheInput ~= nil then
    AddClientModRPCHandler("bird_pvp_stats", "response", function(payload)
        if _active_screen ~= nil and _active_screen.OnStatsReceived ~= nil then
            _active_screen:OnStatsReceived(payload)
        end
    end)

    AddClientModRPCHandler("bird_pvp_stats", "open", function()
        OpenDamageStatsPanel()
    end)
end

-- Key binding: P key.
if TheInput ~= nil and TheInput.AddKeyDownHandler ~= nil then
    TheInput:AddKeyDownHandler(GLOBAL.KEY_P, function()
        if ThePlayer == nil or ThePlayer.HUD == nil then
            return
        end
        if ThePlayer.HUD:IsChatInputScreenOpen() then
            return
        end
        OpenDamageStatsPanel()
    end)
end
