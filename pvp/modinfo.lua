name = "【月落繁星】饥荒pvp专用mod（测试版）"
description = "更新日志\n1.队伍聊天可跨世界\n2.本地mod检测增强\n3.J键隐藏玩家面板(ob使用)\n4.裁判功能添加随机分队(将所有非裁判玩家分成两队，以服务器公告形式输出)\n5.添加boss三倍掉落开关\n6.第一天玩家免疫催眠，冰冻，不会着火，旋风杖不能在第一天对玩家使用"..
"\n7.添加队内快捷宣告功能\n8.添加功能:队友位置共享 黑暗中显示队友脚下圈\n9.科技书只对本队生效。无视距离(只在第一天黄昏以后的地上有效)\n10.老麦影人第一天无法锁对面"
author = "乔尔,冷泠,蔡鸟bird"
version = "1.0beta.17"
priority = 9007199254740991

forumthread = ""

dst_compatible = true
all_clients_require_mod = true

api_version = 10  

icon_atlas = "modicon.xml"
icon = "modicon.tex"




configuration_options =
{
	{
		name = "extra_loot",
		label = "boss三倍掉落",
		hover = "",
		options =	{
			{description = "开启", data = true, hover = ""},
			{description = "关闭", data = false, hover = ""},
					},
		default = true,
	},
	{
		name = "quick_announce",
		label = "队内快捷宣告",
		hover = "",
		options =	{
			{description = "开启", data = true, hover = ""},
			{description = "关闭", data = false, hover = ""},
					},
		default = true,
	},
	{
		name = "better_show_teammate",
		label = "队友显示优化",
		hover = "",
		options =	{
			{description = "开启", data = true, hover = ""},
			{description = "关闭", data = false, hover = ""},
					},
		default = true,
	},
	{
		name = "hbstyle",
		label = "Style样式",
		hover = "",
		options =	{
						{description = "Hidden隐藏", data = "hidden", hover = "Hide healthbar 隐藏血条"},
						{description = "♥♥♥♡♡", data = "heart", hover = "Heart. 心形血格"},
						{description = "●●●○○", data = "circle", hover = "Circle. 圆形血格"},
						{description = "■■■□□", data = "square", hover = "Square. 方块形血格"},
						{description = "◆◆◆◇◇", data = "diamond", hover = "Diamond. 菱形血格"},
						{description = "★★★☆☆", data = "star", hover = "Star. 星形血格"},
					},
		default = "heart",
	},
	
	{
		name = "value",
		label = "Value数值",
		hover = "Show health value?是否显示生命值",
		options =	{
						{description = "Shown显示", data = true, hover = ""},
						{description = "Hidden隐藏", data = false, hover = ""},
					},
		default = true,
	},
	
	{
		name = "hblength",
		label = "Length长度",
		hover = "",
		options =	{
						{description = "5", data = 5, hover = ""},
						{description = "6", data = 6, hover = ""},
						{description = "8", data = 8, hover = ""},
						{description = "10", data = 10, hover = ""},
					},
		default = 10,
	},
	
	{
		name = "hbpos",
		label = "Pos位置",
		hover = "",
		options =	{
						{description = "Bottom脚下", data = 0, hover = ""},
						{description = "OverHead头顶", data = 1, hover = ""},
					},
		default = 1,
	},
	
	{
		name = "hbcolor",
		label = "Color颜色",
		hover = "",
		options =	{
						{description = "Dynamic动态", data = "dynamic", hover = ""},
						{description = "White白", data = "white", hover = ""},
						{description = "Black黑", data = "black", hover = ""},
						{description = "Red红", data = "red", hover = ""},
						{description = "Green绿", data = "green", hover = ""},
						{description = "Blue蓝", data = "blue", hover = ""},
						{description = "Yellow黄", data = "yellow", hover = ""},
						{description = "Cyan青", data = "cyan", hover = ""},
						{description = "Magenta品红", data = "magenta", hover = ""},
						{description = "Gray灰", data = "gray", hover = ""},
						{description = "Orange橙", data = "orange", hover = ""},
						{description = "Purple紫", data = "purple", hover = ""},
					},
		default = "dynamic",
	},
	
	{
		name = "ddon",
		label = "DD显伤",
		hover = "Damage display. 伤害显示",
		options =	{
						{description = "On开启", data = true, hover = ""},
						{description = "Off关闭", data = false, hover = ""},
					},
		default = true,
	},

	

    -- Shuiyue extension merged options
    {
        name = "preselect_lobby",
        label = "预选角色界面",
        hover = "在初始选人流程中插入一个预选确认界面。",
        options = {
            {description = "开启", data = true, hover = ""},
            {description = "关闭", data = false, hover = ""},
        },
        default = true,
    },
    {
        name = "ADMIN_MODE",
        label = "开局条件",
        hover = "决定什么时候开始游戏。",
        options = {
            {description = "全员准备", data = "ALL", hover = ""},
            {description = "达到最低人数", data = "MIN", hover = ""},
            {description = "管理员控制", data = "ADMIN", hover = ""},
        },
        default = "ALL",
    },
    {
        name = "MIN_PLAYERS",
        label = "最低人数",
        hover = "开始游戏前至少需要多少名玩家准备。",
        options = {
            {description = "1", data = 1, hover = ""},
            {description = "2", data = 2, hover = ""},
            {description = "3", data = 3, hover = ""},
            {description = "4", data = 4, hover = ""},
            {description = "5", data = 5, hover = ""},
            {description = "6", data = 6, hover = ""},
            {description = "8", data = 8, hover = ""},
            {description = "10", data = 10, hover = ""},
            {description = "12", data = 12, hover = ""},
            {description = "16", data = 16, hover = ""},
            {description = "24", data = 24, hover = ""},
            {description = "32", data = 32, hover = ""},
            {description = "64", data = 64, hover = ""},
        },
        default = 1,
    },
    {
        name = "LATE_JOIN",
        label = "允许中途加入",
        hover = "游戏开始后是否允许新玩家继续连接。",
        options = {
            {description = "是", data = true, hover = ""},
            {description = "否", data = false, hover = ""},
        },
        default = true,
    },
    {
        name = "KEEP_PAUSED_AFTER_START",
        label = "开始后暂停一次",
        hover = "开始游戏并生成首个玩家后自动暂停一次，需要管理员手动继续。",
        options = {
            {description = "开启", data = true, hover = ""},
            {description = "关闭", data = false, hover = ""},
        },
        default = true,
    },
    {
        name = "shadowprotector_change",
        label = "影人修改",
        hover = "老麦影人第一天不会攻击非队友的玩家。",
        options = {
            {description = "开启", data = true, hover = ""},
            {description = "关闭", data = false, hover = ""},
        },
        default = true,
    },}

