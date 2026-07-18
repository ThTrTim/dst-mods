local Widget = require("widgets/widget")
local Text = require("widgets/text")
local TextButton = require("widgets/textbutton")
local Image = require("widgets/image")
local ImageButton = require("widgets/imagebutton")
local PopupDialogScreen = require("screens/redux/popupdialog")

local BUTTON_COLOUR = { 240 / 255, 218 / 255, 131 / 255, 1 }
local BUTTON_FOCUS_COLOUR = { 1, 1, 1, 1 }
local TEAM_RED = 1
local TEAM_BLUE = 2
local WALKING_STICK_PREFAB = "walking_stick"

local ACTIONS = {
    { id = "large_view", label = "大视野", options = { { "开启", 1 } } },
    { id = "night_vision", label = "夜视", options = { { "开启", 1 } } },
    { id = "give_team_item", label = "木手杖", options = { { "红队", TEAM_RED }, { "蓝队", TEAM_BLUE } }, item = WALKING_STICK_PREFAB },
    { id = "zhaoji", label = "召集", options = { { "召集", 1 } }, confirm = true },
    { id = "youxi", label = "游戏", options = { { "暂停/继续", 1 } } },
}

local ADMIN_ACTION_IDS = {
    give_team_item = true,
    zhaoji = true,
    youxi = true,
}

local RefereePanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "hz_quanx")
    self.owner = owner

    local blocker = self:AddChild(ImageButton("images/global.xml", "square.tex"))
    blocker.image:SetVRegPoint(ANCHOR_MIDDLE)
    blocker.image:SetHRegPoint(ANCHOR_MIDDLE)
    blocker.image:SetVAnchor(ANCHOR_MIDDLE)
    blocker.image:SetHAnchor(ANCHOR_MIDDLE)
    blocker.image:SetScaleMode(SCALEMODE_FILLSCREEN)
    blocker.image:SetTint(0, 0, 0, 0.2)
    blocker:SetOnClick(function()
        self:DoHide()
    end)

    self.root = self:AddChild(Widget("root"))
    self.root:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self.root:SetHAnchor(ANCHOR_MIDDLE)
    self.root:SetVAnchor(ANCHOR_MIDDLE)
    self.root:SetPosition(0, 0)

    local backdrop = self.root:AddChild(Image("images/scoreboard.xml", "scoreboard_frame.tex"))
    backdrop:SetScale(0.96, 0.9)

    self.title = self.root:AddChild(TextButton())
    self.title:SetPosition(0, 210, 0)
    self.title:SetText("功能")
    self.title:SetTextSize(45)
    self.title:SetTextColour(BUTTON_COLOUR)
    self.title:SetTextFocusColour(BUTTON_FOCUS_COLOUR)
    self.title:SetOnClick(function()
        self:GongNeng()
    end)

    self.close = self.root:AddChild(ImageButton("images/global_redux.xml", "close.tex"))
    self.close:SetPosition(350, 210, 0)
    self.close:SetOnClick(function()
        self:DoHide()
    end)

    self:Hide()
end)

function RefereePanel:DoHide()
    self:Hide()
end

function RefereePanel:NeedShow()
    self:Show()
    self:GongNeng()
end

local function SendAction(action_id, value, extra)
    SendModRPCToServer(MOD_RPC.bird_mode_rpc.bird_mode_rpc, action_id, value, extra)
end

local function GetGlobalFunction(name)
    return _G ~= nil and rawget(_G, name) or nil
end

local function IsLocalAdmin()
    return TheNet ~= nil
        and TheNet.GetIsServerAdmin ~= nil
        and TheNet:GetIsServerAdmin()
end

local function CanShowAction(action)
    return action ~= nil
        and (ADMIN_ACTION_IDS[action.id] ~= true or IsLocalAdmin())
end

local function IsLargeViewEnabled()
    local fn = GetGlobalFunction("BirdObserverIsLargeViewEnabled")
    return fn ~= nil and fn()
end

local function ToggleLargeView()
    local fn = GetGlobalFunction("BirdObserverToggleLargeView")
    if fn == nil then
        return false
    end

    return fn()
end

local function IsNightVisionEnabled()
    local fn = GetGlobalFunction("BirdObserverIsNightVisionEnabled")
    return fn ~= nil and fn()
end

local function ToggleNightVision()
    local fn = GetGlobalFunction("BirdObserverToggleNightVision")
    if fn == nil then
        return false
    end

    return fn()
end

local function UpdateLargeViewButton(button)
    button:SetText(IsLargeViewEnabled() and "关闭" or "开启")
end

local function UpdateNightVisionButton(button)
    button:SetText(IsNightVisionEnabled() and "关闭" or "开启")
end

function RefereePanel:GongNeng()
    if self.players_ui ~= nil then
        self.players_ui:Kill()
    end
    self.players_ui = self.root:AddChild(Widget("bird_referee_actions"))

    local index = 0
    for _, action in ipairs(ACTIONS) do
        if CanShowAction(action) then
            index = index + 1
        local label = self.players_ui:AddChild(Text(UIFONT, 30, action.label))
        label:SetHAlign(ANCHOR_LEFT)
        label:SetRegionSize(110, 60)
        label:SetPosition(-210, 140 - index * 40, 0)

        for option_index, option in ipairs(action.options) do
            local button = label:AddChild(TextButton())
            button:SetPosition(45 + option_index * 88, 0, 0)
            button.text:SetRegionSize(105, 30)
            button.text:SetHAlign(ANCHOR_LEFT)
            button.image:SetSize(button.text:GetRegionSize())
            if action.id == "large_view" then
                UpdateLargeViewButton(button)
            elseif action.id == "night_vision" then
                UpdateNightVisionButton(button)
            else
                button:SetText(option[1])
            end
            button:SetTextSize(30)
            button:SetTextColour(BUTTON_COLOUR)
            button:SetTextFocusColour(BUTTON_FOCUS_COLOUR)
            button:SetOnClick(function()
                local function run_action()
                    if action.id == "large_view" then
                        ToggleLargeView()
                        UpdateLargeViewButton(button)
                    elseif action.id == "night_vision" then
                        ToggleNightVision()
                        UpdateNightVisionButton(button)
                    else
                        SendAction(action.id, option[2], action.item)
                    end
                end

                if action.confirm then
                    TheFrontEnd:PushScreen(PopupDialogScreen("该操作具有不可逆性", "是否继续", {
                        { text = "确定", cb = function() run_action() TheFrontEnd:PopScreen() end },
                        { text = "取消", cb = function() TheFrontEnd:PopScreen() end },
                    }))
                else
                    run_action()
                end
            end)
        end
        end
    end
end

return RefereePanel
