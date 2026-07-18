
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local ImageButton = require "widgets/imagebutton"
local TEMPLATES = require "widgets/redux/templates"
local TextButton = require "widgets/textbutton"
local atlas = "images/crafting_menu.xml"
local Screen = require "widgets/screen"
local PlayerBadge = require "widgets/playerbadge"
local Image = require "widgets/image"
local PlayerBadge = require "widgets/playerbadge"
local PopupDialogScreen = require "screens/redux/popupdialog"

local equipui
local hz_quanx =Class(Widget,function(self, owner)
    Widget._ctor(self, "hz_quanx")
    self.owner = owner

	self.root = self:AddChild(Widget("root"))
	self.root:SetPosition(0, -200)

    self.left = self:AddChild(Widget("root"))
	self.left:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self.left:SetHAnchor(ANCHOR_LEFT)
    self.left:SetVAnchor(ANCHOR_MIDDLE)
	self.left:SetPosition(0, 0)

    self.right = self:AddChild(Widget("root"))
	self.right:SetScaleMode(SCALEMODE_PROPORTIONAL)
    self.right:SetHAnchor(ANCHOR_RIGHT)
    self.right:SetVAnchor(ANCHOR_MIDDLE)
	self.right:SetPosition(0, 0)

    self:Players()

    self.playersshow = true

    self.bird_save_handler = TheInput:AddKeyDownHandler(KEY_J, function()
        if self.playersshow then
            self.left:Hide()
            self.right:Hide()
            self.playersshow = false
            self.owner.components.talker:Say("隐藏队伍界面")
        else
            self.owner.components.talker:Say("显示队伍界面")
            self.left:Show()
            self.right:Show()
            self.playersshow = true   
        end
    end)
    self.inst:ListenForEvent("onremove", function()
        if self.bird_save_handler ~= nil then
            self.bird_save_handler:Remove()
        end
    end)
end)

function hz_quanx:Players()
    self.hongdui = self.left:AddChild(self:CreatPlayers(self.owner.duiwuinfo[1],{1,0,0,1}))
    self.hongdui:SetPosition(120, -70,0)

    self.landui = self.right:AddChild(self:CreatPlayers(self.owner.duiwuinfo[2],{0,126/255,234/255,1},true))
    self.landui:SetPosition(-120, -70,0)
    
    self.inst:ListenForEvent("updateduiwuinfo",function()
        if self.hongdui and self.hongdui.shown then
            self.hongdui:SetItemsData(self.owner.duiwuinfo[1])
        end
        if self.landui and self.landui.shown then
            self.landui:SetItemsData(self.owner.duiwuinfo[2])
        end
    end,self.owner)
end

local function OnControl(self,control, down)
	if not self:IsEnabled() or not self.focus then return false end

	if self:IsSelected() and not self.AllowOnControlWhenSelected then return false end

	if ( control == CONTROL_ACCEPT or control == CONTROL_SECONDARY ) and (not self.mouseonly or TheFrontEnd.isprimary) then
		if down then
			if not self.down then
				TheFrontEnd:GetSound():PlaySound("dontstarve/HUD/click_move")
				self.o_pos = self:GetLocalPosition()
				self:SetPosition(self.o_pos + self.clickoffset)
				self.down = true
				if self.whiledown then
					self:StartUpdating()
				end
				if self.ondown then
					self.ondown()
				end
			end
		else
			if self.down then
				self.down = false
                self:ResetPreClickPosition()
                if control == CONTROL_ACCEPT then
                    if self.onclick then
                        self.onclick(false)
                    end	
                elseif control == CONTROL_SECONDARY then
                    if self.onclick then
                        self.onclick(true)
                    end
                end
				self:StopUpdating()
			end
		end

		return true
	end
end  

local function addequipsui(self)
    self.equipslotinfo = {}
    if ThePlayer and ThePlayer.HUD then
        for k, v in ipairs(ThePlayer.HUD.controls.inv.equipslotinfo) do
            self.equipslotinfo[v.slot] = self.proot:AddChild(Image(v.atlas,v.image))
            self.equipslotinfo[v.slot]:SetScale(1)
            self.equipslotinfo[v.slot]:SetPosition(-160 + 80* k,30,0)
            self.equipslotinfo[v.slot].image = self.equipslotinfo[v.slot]:AddChild(Image())
            self.equipslotinfo[v.slot].percent = self.equipslotinfo[v.slot]:AddChild(Text(NUMBERFONT,42,""))
            self.equipslotinfo[v.slot].percent:SetColour(255/255,255/255,255/255,1)
            self.equipslotinfo[v.slot].percent:SetPosition(5,-32+15,0)
        end
    end
end

local normal_list_item_bg_tint = { 1,1,1,0.5 }
local focus_list_item_bg_tint  = { 1,1,1,0.7 }
local normal_red_item_bg_tint = { 1,0,0,1 }
local focus_red_item_bg_tint  = { 1,0,0,1 }
local function setred(row,head)
    row:SetImageNormalColour(  unpack(normal_red_item_bg_tint))
    row:SetImageFocusColour(   unpack(focus_red_item_bg_tint))
    row:SetImageSelectedColour(unpack(normal_red_item_bg_tint))
    row:SetImageDisabledColour(unpack(normal_red_item_bg_tint))
    head.headbg:SetTint(1,0,0,1)
    row.inst:DoTaskInTime(0.2,function()
        row:SetImageNormalColour(  unpack(normal_list_item_bg_tint))
        row:SetImageFocusColour(   unpack(focus_list_item_bg_tint))
        row:SetImageSelectedColour(unpack(normal_list_item_bg_tint))
        row:SetImageDisabledColour(unpack(normal_list_item_bg_tint))
        head.headbg:SetTint(1,1,1,1)
    end)
end

local function IsLocalAdmin()
    return TheNet ~= nil
        and TheNet.GetIsServerAdmin ~= nil
        and TheNet:GetIsServerAdmin()
end

function hz_quanx:CreatPlayers(data,colour,right)
    if not data then
        return
    end
    local cell_size = 60
    local row_w = 190
    local row_h = 50
    local row_spacing = 6
    local function ScrollWidgetsCtor(context, index)
        local w = Widget("mulu-players-".. index)
        local item_width, item_height = 150, 50
        w.backing = w:AddChild(TEMPLATES.ListItemBackground(item_width, item_height, function() end))
        w.backing.move_on_click = true
        w.backing:SetPosition(right and -10 or 10, 0)
        w.backing.OnControl = OnControl

		w.name = w:AddChild(Text(NEWFONT, 24,nil,{0,0,0,1}))
        w.name:SetHAlign(right and ANCHOR_RIGHT or ANCHOR_LEFT)
        w.name:SetRegionSize(200, 60)
        w.name:SetPosition(right and -50 or 50, 14)
        w.name:SetScale(.9)

        w.characterBadge = w:AddChild(PlayerBadge("", colour, true, 0))
        w.characterBadge:SetScale(.7)
        w.characterBadge:SetPosition(right and 70 or -70,0,0)
        w.characterBadge:Hide()

        w.hunger = w:AddChild(Text(NUMBERFONT,23,"󰀎".."123"))
        w.hunger:SetRegionSize(100, 60)
        w.hunger:SetPosition(right and 25 or -25, -10)

        w.sanity = w:AddChild(Text(NUMBERFONT,23,"󰀓".."123"))
        w.sanity:SetRegionSize(100, 60)
        w.sanity:SetPosition(right and -20 or 20, -10)

        w.health = w:AddChild(Text(NUMBERFONT,23,"󰀍".."123"))
        w.health:SetRegionSize(100, 60)
        w.health:SetPosition(right and -60 or 60, -10)

		return w
    end
    local function ScrollWidgetSetData(context, widget, data, index)
		if data ~= nil then
            if data.nm then
                widget.name:SetString(data.nm)
                widget.name:SetColour(PLAYERCOLOURS.YELLOW)
                if data.pr then
                    widget.characterBadge:Set(data.pr, colour, data.dd and true or false, data.dd and 1 or 0)
                    widget.characterBadge:Show()
                else
                    widget.characterBadge:Hide()
                end
                widget.backing:SetOnClick(function(right)
                    if not IsLocalAdmin() then
                        return
                    end

                    if right then
                        SendModRPCToServer( MOD_RPC["bird_mode_rpc"]["bird_mode_rpc"],"wanjia",1,data.id)
                        return
                    else
                        local ui = PopupDialogScreen("玩家"..(data.nm or ""), "", {
                            {text="复活", cb = function() 
                                SendModRPCToServer( MOD_RPC["bird_mode_rpc"]["bird_mode_rpc"],"wanjia",2,data.id)
                                TheFrontEnd:PopScreen() 
                            end},
                            {text="杀死玩家", cb = function() 
                                 SendModRPCToServer( MOD_RPC["bird_mode_rpc"]["bird_mode_rpc"],"wanjia",3,data.id)
                                TheFrontEnd:PopScreen() 
                            end},
                            {text="返回", cb = function() TheFrontEnd:PopScreen() end},
                        })
                        TheFrontEnd:PushScreen(ui)
                        if ui then
                            addequipsui(ui)
                            equipui = ui
                            equipui.id = data.id or "00000000"
                        end
                    end
                end)
            end
            if data.sw then
                if widget.oldhealth ~= nil and data.sw[3] and data.sw[3] < widget.oldhealth then
                    self:CreatTip(data.sw[3] - widget.oldhealth,widget.health)
                    setred(widget.backing,widget.characterBadge)
                end
                widget.hunger:SetString("󰀎"..(data.sw[1] or ""))
                widget.sanity:SetString("󰀓"..(data.sw[2] or ""))
                widget.health:SetString("󰀍"..(data.sw[3] or ""))

                widget.oldhealth = data.sw[3]
            end
            if data.eq and equipui and equipui.inst:IsValid() and equipui.id == data.id  then
                for k,v in pairs(equipui.equipslotinfo) do
                    if data.eq[k] ~= nil then
                        v.image:SetTexture(GetInventoryItemAtlas(data.eq[k][1]), data.eq[k][1])
                        v.image:Show()
                        if data.eq[k][2] ~= nil then
                            local val_to_show = data.eq[k][2]*100
                            if val_to_show > 0 and val_to_show < 1 then
                                val_to_show = 1
                            end
                            v.percent:SetString(string.format("%2.0f%%", val_to_show))
                            v.percent:Show()
                        else
                            v.percent:Hide()
                        end
                    else
                        v.image:Hide()
                    end
                end
            end
			widget:Enable()
            widget:Show()
		else
			widget:Disable()
            widget:Hide()
		end
		widget.data = data
    end

	local grid = TEMPLATES.ScrollingGrid(
        data,
        {
            context = {},
            widget_width  = row_w+row_spacing,
            widget_height = row_h+row_spacing,
			peek_percent     = 0.5,
            num_visible_rows = 6.5,
            num_columns      = 1,
            item_ctor_fn = ScrollWidgetsCtor,
            apply_fn     = ScrollWidgetSetData,
            scrollbar_offset = 0,
            scrollbar_height_offset = -26
        })
        grid.up_button:SetTextures("images/ui.xml", "arrow_scrollbar_up.tex")
        grid.up_button:SetScale(1)
        grid.up_button:Hide()
    
        grid.down_button:SetTextures("images/ui.xml", "arrow_scrollbar_down.tex")
        grid.down_button:SetScale(1)
        grid.down_button:Hide()
    
        grid.scroll_bar_line:SetTexture("images/ui.xml", "scrollbarline.tex")
        grid.scroll_bar_line:SetScale(.8)
        grid.scroll_bar_line:Hide()
    
        grid.position_marker:SetTextures("images/ui.xml", "scrollbarbox.tex")
        grid.position_marker.image:SetTexture("images/ui.xml", "scrollbarbox.tex")
        grid.position_marker:SetScale(.5)
        grid.position_marker:Hide()

    return grid
end

function hz_quanx:CreatTip(str,aaa)
    local text = aaa:AddChild(Text(NUMBERFONT, 30, str,PLAYERCOLOURS.RED))
    text.addhight = 0
    text:SetPosition(0 ,10)
    text.inst:DoPeriodicTask(0,function()
        text.addhight = text.addhight + 1.2
        text:SetPosition(0 ,10+text.addhight)
    end)
    text.inst:DoTaskInTime(0.5,function()
        if text and text.inst:IsValid() then
            text:Kill()
        end
    end)
end

return hz_quanx

--[[
    local  a = DebugSpawn(MAIN_CHARACTERLIST[math.random(#MAIN_CHARACTERLIST)]) 
        a.components.player_duiwu_qe:Choose(1)
        a.components.inventory:Equip(SpawnPrefab("flowerhat"))
        a.userid = tostring(math.random(999))
         local aaaa = GetAvailablePlayerColours()
        a.colour = aaaa[math.random(#aaaa)]


    local  a = DebugSpawn(MAIN_CHARACTERLIST[math.random(#MAIN_CHARACTERLIST)]) 
        a.userid = tostring(math.random(999))
         local aaaa = GetAvailablePlayerColours()
        a.colour = aaaa[math.random(#aaaa)]
]]
