-- [PATCH] 新增：每局结束时的结算面板，显示两队当局输出与承伤。

local Screen = require "widgets/screen"
local Widget = require "widgets/widget"
local Image = require "widgets/image"
local Text = require "widgets/text"
local TEMPLATES = require "widgets/redux/templates"

local TEAM_RED = 1
local TEAM_BLUE = 2

local PANEL_WIDTH = 520
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

local SettlementScreen = Class(Screen, function(self, data)
    Screen._ctor(self, "SettlementScreen")
    self.data = data or {}
    self:DoInit()
end)

function SettlementScreen:DoInit()
    -- DST screen space origin is bottom-left, y grows upward.
    local screen_w, screen_h = TheSim:GetScreenSize()
    if screen_w == nil or screen_w <= 0 then
        screen_w = 1920
    end
    if screen_h == nil or screen_h <= 0 then
        screen_h = 1080
    end
    self.root = self:AddChild(Widget("ROOT"))
    self.root:SetPosition(screen_w / 2, screen_h / 2, 0)

    -- Vanilla-style window frame.
    self.bg = self.root:AddChild(TEMPLATES.RectangleWindow(PANEL_WIDTH, PANEL_HEIGHT))
    self.bg:SetPosition(0, 0, 0)

    local winner = self.data.winner
    local winner_text = winner == TEAM_RED and "红队 获胜！" or (winner == TEAM_BLUE and "蓝队 获胜！" or "本局结束")
    local winner_colour = winner == TEAM_RED and { 0.95, 0.30, 0.24, 1 }
        or (winner == TEAM_BLUE and { 0.32, 0.58, 1.00, 1 } or UICOLOURS.GOLD)

    self.title = self.root:AddChild(Text(HEADERFONT, 38, winner_text, winner_colour))
    self.title:SetPosition(0, 120)

    local red = self.data.red or { dealt = 0, taken = 0 }
    local blue = self.data.blue or { dealt = 0, taken = 0 }

    self.red_label = self.root:AddChild(Text(HEADERFONT, 28, "红队", { 0.95, 0.30, 0.24, 1 }))
    self.red_label:SetPosition(-120, 55)

    self.blue_label = self.root:AddChild(Text(HEADERFONT, 28, "蓝队", { 0.32, 0.58, 1.00, 1 }))
    self.blue_label:SetPosition(120, 55)

    self.red_dealt = self.root:AddChild(Text(CHATFONT, 22, "输出: " .. FormatNumber(red.dealt), { 0.95, 0.30, 0.24, 1 }))
    self.red_dealt:SetPosition(-120, 20)

    self.red_taken = self.root:AddChild(Text(CHATFONT, 22, "承伤: " .. FormatNumber(red.taken), { 0.95, 0.30, 0.24, 1 }))
    self.red_taken:SetPosition(-120, -10)

    self.blue_dealt = self.root:AddChild(Text(CHATFONT, 22, "输出: " .. FormatNumber(blue.dealt), { 0.32, 0.58, 1.00, 1 }))
    self.blue_dealt:SetPosition(120, 20)

    self.blue_taken = self.root:AddChild(Text(CHATFONT, 22, "承伤: " .. FormatNumber(blue.taken), { 0.32, 0.58, 1.00, 1 }))
    self.blue_taken:SetPosition(120, -10)

    self.close_button = self.root:AddChild(TEMPLATES.StandardButton(function()
        self:Close()
    end, "关闭", { 120, 42 }))
    self.close_button:SetPosition(0, -110)
end

function SettlementScreen:Close()
    TheFrontEnd:PopScreen(self)
end

function SettlementScreen:OnControl(control, down)
    if Screen.OnControl(self, control, down) then
        return true
    end
    if not down and (control == CONTROL_PAUSE or control == CONTROL_CANCEL) then
        self:Close()
        return true
    end
    return false
end

if TheInput ~= nil then
    AddClientModRPCHandler("bird_pvp_settlement", "show", function(payload)
        if TheFrontEnd == nil then
            return
        end
        local ok, data = pcall(json.decode, payload)
        if not ok or type(data) ~= "table" then
            return
        end
        TheFrontEnd:PushScreen(SettlementScreen(data))
    end)
end
