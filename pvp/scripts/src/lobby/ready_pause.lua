-- [PATCH] 新增：开局后的“两队确认准备”暂停释放逻辑。
-- 游戏开始并自动暂停后，需红队和蓝队各自至少有一名玩家输入 /ready
-- 或发送“ready”/“准备好”确认，暂停才会解除。确认人数通过 NetVar 同步
-- 到大厅界面实时显示。

local team_state = require("src/team/lobby_team_state")

local TEAM_RED = team_state.TEAM_RED
local TEAM_BLUE = team_state.TEAM_BLUE

local ENABLED = GetModConfigData("KEEP_PAUSED_AFTER_START") == true

-- Net vars attached to TheWorld.net so both server and clients can read them.
local _red_ready_net = nil
local _blue_ready_net = nil
local _ready_count_net = nil

-- Server-side bookkeeping.
local _red_ready_players = {}
local _blue_ready_players = {}
local _game_started = false
local _release_on_both_ready = false

local function IsAuthorityShard()
    if TheWorld == nil then
        return false
    end
    if TheWorld.HasTag ~= nil and TheWorld:HasTag("cave") then
        return false
    end
    return TheWorld.worldprefab ~= "cave" and TheWorld.prefab ~= "cave"
end

local function GetWorldLobby()
    local net = TheWorld ~= nil and TheWorld.net or nil
    return net ~= nil and net.components ~= nil and net.components.worldcharacterselectlobby or nil
end

local function GetPlayerTeam(userid)
    if userid == nil or userid == "" then
        return nil
    end
    -- Prefer the authoritative server lobby team table.
    local net = TheWorld ~= nil and TheWorld.net or nil
    local teams = net ~= nil and net._bird_lobby_teams or nil
    if teams ~= nil then
        local team = team_state.normalize(teams[userid])
        if team == TEAM_RED or team == TEAM_BLUE then
            return team
        end
    end
    -- Fall back to the spawned player entity team var.
    local client = TheNet:GetClientTableForUser(userid)
    if client ~= nil then
        for _, player in ipairs(AllPlayers or {}) do
            if player.userid == userid then
                local team, _ = team_state.get_player_team(player, nil)
                return team
            end
        end
    end
    return nil
end

local function UpdateNetVars()
    if not TheWorld.ismastersim then
        return
    end
    local red_count = 0
    local blue_count = 0
    for _ in pairs(_red_ready_players) do red_count = red_count + 1 end
    for _ in pairs(_blue_ready_players) do blue_count = blue_count + 1 end

    if _red_ready_net ~= nil then
        _red_ready_net:set(red_count > 0)
    end
    if _blue_ready_net ~= nil then
        _blue_ready_net:set(blue_count > 0)
    end
    if _ready_count_net ~= nil then
        _ready_count_net:set(red_count + blue_count)
    end
end

local function BothTeamsReady()
    local red = next(_red_ready_players) ~= nil
    local blue = next(_blue_ready_players) ~= nil
    return red and blue
end

local function TryReleasePause()
    if not _release_on_both_ready then
        return
    end
    if not BothTeamsReady() then
        return
    end
    _release_on_both_ready = false

    local lobby = GetWorldLobby()
    if lobby ~= nil and lobby.ReleaseStartPause ~= nil then
        lobby:ReleaseStartPause()
        if TheNet ~= nil and TheNet.Announce ~= nil then
            TheNet:Announce("两队均已准备就绪，游戏开始！")
        end
    end
end

local function MarkPlayerReady(userid, source)
    if not _game_started or not _release_on_both_ready then
        return false
    end
    local team = GetPlayerTeam(userid)
    if team == TEAM_RED then
        if _red_ready_players[userid] then
            return false
        end
        _red_ready_players[userid] = true
    elseif team == TEAM_BLUE then
        if _blue_ready_players[userid] then
            return false
        end
        _blue_ready_players[userid] = true
    else
        return false
    end

    UpdateNetVars()

    local client = TheNet:GetClientTableForUser(userid)
    local name = client ~= nil and client.name or userid or "某玩家"
    local ready_count = 0
    for _ in pairs(_red_ready_players) do ready_count = ready_count + 1 end
    for _ in pairs(_blue_ready_players) do ready_count = ready_count + 1 end
    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce(tostring(name) .. " 已准备好（当前 " .. tostring(ready_count) .. " 人）")
    end

    TryReleasePause()
    return true
end

local function ResetReadyState()
    _red_ready_players = {}
    _blue_ready_players = {}
    _game_started = false
    _release_on_both_ready = false
    UpdateNetVars()
end

local function OnGameStarted()
    if not ENABLED or not IsAuthorityShard() then
        return
    end
    _game_started = true
    _release_on_both_ready = true
    _red_ready_players = {}
    _blue_ready_players = {}
    UpdateNetVars()
    if TheNet ~= nil and TheNet.Announce ~= nil then
        TheNet:Announce("游戏已开始，请两队各输入 /ready 或发送“准备好”确认开局。")
    end
end

local function OnPlayerChat(guid, userid, name, prefab, message, colour, iswhisper, ...)
    if TheWorld == nil or not TheWorld.ismastersim then
        return
    end
    if not _release_on_both_ready then
        return
    end
    if message == nil then
        return
    end
    local text = string.lower(tostring(message))
    if text == "/ready" or text == "/zhunbei" or text == "/ok"
        or string.find(text, "准备好", 1, true)
        or string.find(text, "ready", 1, true) then
        MarkPlayerReady(userid, "chat")
    end
end

-- Public helper used by the lobby UI to show "X / total ready".
function GLOBAL.BirdGetBothTeamsReadyCount()
    if _ready_count_net ~= nil then
        return _ready_count_net:value()
    end
    return 0
end

function GLOBAL.BirdIsRedTeamReady()
    if _red_ready_net ~= nil then
        return _red_ready_net:value()
    end
    return false
end

function GLOBAL.BirdIsBlueTeamReady()
    if _blue_ready_net ~= nil then
        return _blue_ready_net:value()
    end
    return false
end

-- Register the /ready user command.
AddUserCommand("birdreadystart", {
    prettyname = "准备好",
    desc = "在本局开局暂停期间确认队伍已准备好",
    permission = COMMAND_PERMISSION.USER,
    slash = true,
    usermenu = false,
    servermenu = false,
    params = {},
    vote = false,
    canstartfn = function(command, caller, targetid)
        return _release_on_both_ready
    end,
    serverfn = function(params, caller)
        if MarkPlayerReady(caller.userid, "command") then
            -- announcement is handled inside MarkPlayerReady
        else
            if TheNet ~= nil and TheNet.Announce ~= nil then
                local name = caller ~= nil and (caller.name or caller.userid) or "某玩家"
                TheNet:Announce(tostring(name) .. " 的准备状态未变更")
            end
        end
    end,
})

-- Install hooks.
AddPrefabPostInit("world", function(inst)
    if not inst.ismastersim then
        return
    end

    inst:ListenForEvent("ms_playerspawn", function()
        local lobby = GetWorldLobby()
        if lobby ~= nil and lobby.HasGameStarted ~= nil and lobby:HasGameStarted() then
            -- First spawn after game started: this is when the start pause is applied.
            OnGameStarted()
        end
    end, inst)

    -- Reset on a fresh lobby (e.g. server reset to lobby).
    inst:ListenForEvent("ms_clientauthenticationcomplete", function()
        if GetWorldLobby() ~= nil and GetWorldLobby():IsAllowingCharacterSelect() then
            ResetReadyState()
        end
    end, inst)
end)

-- Network variable setup: attach to forest_network / cave_network.
AddPrefabPostInit("forest_network", function(inst)
    if _red_ready_net == nil then
        _red_ready_net = net_bool(inst.GUID, "birdpvp.redteamready", "birdpvp_redteamready_dirty")
    end
    if _blue_ready_net == nil then
        _blue_ready_net = net_bool(inst.GUID, "birdpvp.blueteamready", "birdpvp_blueteamready_dirty")
    end
    if _ready_count_net == nil then
        _ready_count_net = net_byte(inst.GUID, "birdpvp.readycount", "birdpvp_readycount_dirty")
    end
end)

AddPrefabPostInit("cave_network", function(inst)
    if _red_ready_net == nil then
        _red_ready_net = net_bool(inst.GUID, "birdpvp.redteamready", "birdpvp_redteamready_dirty")
    end
    if _blue_ready_net == nil then
        _blue_ready_net = net_bool(inst.GUID, "birdpvp.blueteamready", "birdpvp_blueteamready_dirty")
    end
    if _ready_count_net == nil then
        _ready_count_net = net_byte(inst.GUID, "birdpvp.readycount", "birdpvp_readycount_dirty")
    end
end)

-- Hook server chat to accept "ready" / "准备好" messages.
if TheNet ~= nil and TheNet.GetIsServer ~= nil and TheNet:GetIsServer() then
    local old_Networking_Say = GLOBAL.Networking_Say
    if old_Networking_Say ~= nil then
        GLOBAL.Networking_Say = function(guid, userid, name, prefab, message, colour, iswhisper, ...)
            pcall(OnPlayerChat, guid, userid, name, prefab, message, colour, iswhisper, ...)
            return old_Networking_Say(guid, userid, name, prefab, message, colour, iswhisper, ...)
        end
    end
end
